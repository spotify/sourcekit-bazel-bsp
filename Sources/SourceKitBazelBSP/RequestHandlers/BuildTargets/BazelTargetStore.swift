// Copyright (c) 2025 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import BazelProtobufBindings
import BuildServerProtocol
import Foundation
import LanguageServerProtocol

import struct os.OSAllocatedUnfairLock

private let logger = makeFileLevelBSPLogger()

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
protocol BazelTargetStore: AnyObject {
    /// Users of BazelTargetStore are expected to acquire this lock before reading or writing any of the internal state.
    /// This is to prevent race conditions between concurrent requests. It's easier to have each request handle critical sections
    /// on their own instead of trying to solve it entirely within this class.
    var stateLock: OSAllocatedUnfairLock<Void> { get }
    /// Returns true if the store has actually processed something.
    var isInitialized: Bool { get }
    /// Processes the project's dependency graph according to the user's configuration.
    func fetchTargets() throws -> [BuildTarget]
    /// Converts a BSP BuildTarget URI to its underlying Bazel target label.
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String
    /// Retrieves the SourcesItem for a given a BSP BuildTarget URI.
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> SourcesItem
    /// Retrieves the list of BSP BuildTarget URIs that contain a given source file.
    func bspURIs(containingSrc src: URI) throws -> [URI]
    /// Provides the bazel label containing **platform information** for a given BSP URI.
    /// This is used to determine the correct set of compiler flags for the target / platform combo.
    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo
    /// Returns the processed broad aquery containing compiler arguments for all targets we're interested in.
    func targetsAqueryForArgsExtraction() throws -> ProcessedAqueryResult
    /// Determines which targets an added/removed file belongs to and updates the store accordingly.
    /// Files that don't belong to any known targets are ignored.
    /// Returns the set of targets that were invalidated by the changes.
    func process(fileChanges: [FileEvent]) throws -> Set<BuildTargetIdentifier>
    /// Retrieves the configuration information for a given Bazel **top-level** target label.
    func topLevelConfigInfo(forConfigMnemonic mnemonic: String) throws -> BazelTargetConfigurationInfo
    /// Retrieves the available configurations for a given Bazel target label.
    func parentConfig(forBSPURI uri: URI) throws -> String
    /// Retrieves the list of top-level labels for a given configuration.
    func topLevelLabels(forConfig configMnemonic: String) throws -> [String]
    /// Retrieves the top-level rule type for a given top-level label.
    func topLevelRuleType(forLabel label: String) throws -> TopLevelRuleType
    /// Returns the best parent label for a given config, preferring apps over extensions/tests.
    func preferredTopLevelLabel(forConfig configMnemonic: String) throws -> String
    /// Clears the cache of the store.
    func clearCache()
}

enum BazelTargetStoreError: Error, LocalizedError {
    case unknownBSPURI(URI)
    case unableToMapBazelLabelToParents(String)
    case unableToMapConfigMnemonicToTopLevelConfig(String)
    case unableToMapBSPURIToParentConfig(URI)
    case unableToMapConfigMnemonicToTopLevelLabels(String)
    case unableToMapTopLevelLabelToConfig(String)
    case unableToMapLabelToTopLevelRuleType(String)
    case noCachedAquery

    var errorDescription: String? {
        switch self {
        case .unknownBSPURI(let uri):
            return "Unable to map '\(uri)' to a Bazel target label"
        case .unableToMapBazelLabelToParents(let label):
            return "Unable to map '\(label)' to its parents"
        case .unableToMapConfigMnemonicToTopLevelConfig(let config):
            return "Unable to map config mnemonic '\(config)' to its top-level configuration"
        case .unableToMapBSPURIToParentConfig(let uri):
            return "Unable to map '\(uri)' to its parent configuration"
        case .unableToMapConfigMnemonicToTopLevelLabels(let config):
            return "Unable to map config mnemonic '\(config)' to its top-level labels"
        case .unableToMapTopLevelLabelToConfig(let label):
            return "Unable to map top-level label '\(label)' to its configuration"
        case .unableToMapLabelToTopLevelRuleType(let label):
            return "Unable to map label '\(label)' to its top-level rule type"
        case .noCachedAquery:
            return "No cached aquery result found in the store."
        }
    }
}

final class BazelTargetStoreImpl: BazelTargetStore, @unchecked Sendable {
    let stateLock = OSAllocatedUnfairLock()

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier

    private let supportedDependencyRuleTypes: [DependencyRuleType]
    private let compileMnemonicsToFilter: [String]
    private let topLevelMnemonicsToFilter: [String]
    private let reportQueue = DispatchQueue(label: "com.spotify.sourcekit-bazel-bsp.bazel-target-store.report-queue")

    private var cachedTargets: [BuildTarget]? = nil
    private var aqueryResult: ProcessedAqueryResult? = nil
    private var cqueryResult: ProcessedCqueryResult? = nil

    init(
        initializedConfig: InitializedServerConfig,
        bazelTargetQuerier: BazelTargetQuerier = BazelTargetQuerier(),
    ) {
        self.initializedConfig = initializedConfig
        self.bazelTargetQuerier = bazelTargetQuerier
        self.supportedDependencyRuleTypes = initializedConfig.baseConfig.dependencyRulesToDiscover
        self.compileMnemonicsToFilter = Set(
            initializedConfig.baseConfig.dependencyRulesToDiscover.map { $0.compileMnemonic }
        ).sorted()
        self.topLevelMnemonicsToFilter = Set(initializedConfig.baseConfig.topLevelRulesToDiscover.map { $0.mmnemonic })
            .sorted()
    }

    var isInitialized: Bool {
        return cachedTargets != nil
    }

    func bazelTargetLabel(forBSPURI uri: URI) throws -> String {
        guard let label = cqueryResult?.bspURIsToBazelLabelsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return label
    }

    func bazelTargetSrcs(forBSPURI uri: URI) throws -> SourcesItem {
        guard let sourcesItem = cqueryResult?.bspURIsToSrcsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return sourcesItem
    }

    func bspURIs(containingSrc src: URI) throws -> [URI] {
        guard let bspURIs = cqueryResult?.srcToBspURIsMap[src] else {
            throw BazelTargetStoreError.unknownBSPURI(src)
        }
        return bspURIs
    }

    func topLevelConfigInfo(forConfigMnemonic mnemonic: String) throws -> BazelTargetConfigurationInfo {
        guard let config = aqueryResult?.topLevelConfigMnemonicToInfoMap[mnemonic] else {
            throw BazelTargetStoreError.unableToMapConfigMnemonicToTopLevelConfig(mnemonic)
        }
        return config
    }

    func parentConfig(forBSPURI uri: URI) throws -> String {
        guard let configMnemonic = cqueryResult?.bspUriToParentConfigMap[uri] else {
            throw BazelTargetStoreError.unableToMapBSPURIToParentConfig(uri)
        }
        return configMnemonic
    }

    func topLevelLabels(forConfig configMnemonic: String) throws -> [String] {
        guard let labels = cqueryResult?.configurationToTopLevelLabelsMap[configMnemonic] else {
            throw BazelTargetStoreError.unableToMapConfigMnemonicToTopLevelLabels(configMnemonic)
        }
        return labels
    }

    func topLevelRuleType(forLabel label: String) throws -> TopLevelRuleType {
        guard let ruleType = cqueryResult?.topLevelLabelToRuleTypeMap[label] else {
            throw BazelTargetStoreError.unableToMapLabelToTopLevelRuleType(label)
        }
        return ruleType
    }

    /// Returns the best parent label for a given config, preferring apps over extensions/tests.
    func preferredTopLevelLabel(forConfig configMnemonic: String) throws -> String {
        let labels = try topLevelLabels(forConfig: configMnemonic)
        guard !labels.isEmpty else {
            throw BazelTargetStoreError.unableToMapConfigMnemonicToTopLevelLabels(configMnemonic)
        }
        let ruleTypes = try labels.map { try topLevelRuleType(forLabel: $0) }
        return zip(labels, ruleTypes).labelWithHighestBuildPriority() ?? labels[0]
    }

    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo {
        let bazelLabel = try bazelTargetLabel(forBSPURI: uri)
        let configMnemonic = try parentConfig(forBSPURI: uri)
        let config = try topLevelConfigInfo(forConfigMnemonic: configMnemonic)
        // Use preferredTopLevelLabel to get the best parent (app over extension/test)
        let parentToUse = try preferredTopLevelLabel(forConfig: configMnemonic)
        return BazelTargetPlatformInfo(
            label: bazelLabel,
            topLevelParentLabel: parentToUse,
            topLevelParentConfig: config
        )
    }

    func targetsAqueryForArgsExtraction() throws -> ProcessedAqueryResult {
        guard let targetsAqueryResult = aqueryResult else {
            throw BazelTargetStoreError.noCachedAquery
        }
        return targetsAqueryResult
    }

    @discardableResult
    func fetchTargets() throws -> [BuildTarget] {
        // This request needs caching because it gets called after file changes,
        // even if nothing was invalidated.
        if let cachedTargets = cachedTargets {
            return cachedTargets
        }

        // Query all the targets we are interested in one invocation:
        //  - Top-level targets (e.g. `ios_application`, `ios_unit_test`, etc.)
        //  - Dependencies of the top-level targets (e.g. `swift_library`, `objc_library`, etc.)
        //  - Source files connected to these targets
        // And process the relation between these different targets and sources.
        let cqueryResult = try bazelTargetQuerier.cqueryTargets(
            config: initializedConfig,
            supportedDependencyRuleTypes: initializedConfig.baseConfig.dependencyRulesToDiscover,
            supportedTopLevelRuleTypes: initializedConfig.baseConfig.topLevelRulesToDiscover
        )

        // Run a broad aquery against all top-level targets
        // to get the compiler arguments for all targets we're interested in.
        // We pass top-level mnemonics in addition to compile ones as a method to gain access to the parent's configuration id.
        // We can then use this to locate the exact variant of the target we are looking for.
        // BundleTreeApp is used by most rule types, while SignBinary is for macOS CLI apps specifically.
        self.aqueryResult = try processCompilerArguments(from: cqueryResult)
        self.cqueryResult = cqueryResult

        let result = cqueryResult.buildTargets
        cachedTargets = result

        reportQueue.async { [weak self] in
            guard let self = self else { return }
            let graphDir = self.initializedConfig.rootUri + "/.bsp/skbsp_generated"
            let graphPath = graphDir + "/graph.json"
            self.writeReport(toPath: graphPath, creatingDirectoryAt: graphDir)
        }

        return result
    }

    func process(fileChanges: [FileEvent]) throws -> Set<BuildTargetIdentifier> {
        guard let cqueryResult = cqueryResult else {
            return []
        }

        // We only care about added and deleted files.
        // We also need to remove events that cancel each other out.
        let addedAndDeletedFiles = fileChanges.filter { $0.type != .changed }.cleaned()
        let addedFiles = addedAndDeletedFiles.filter { $0.type == .created }
        let deletedFiles = addedAndDeletedFiles.filter { $0.type == .deleted }

        // For the added files, we need to run an cquery to determine which targets they belong to.
        // This is not necessary for the deleted ones.
        let addedFilesResult = try bazelTargetQuerier.cqueryTargets(
            forAddedSrcs: addedFiles.map { $0.uri },
            inTopLevelTargets: cqueryResult.topLevelTargets.map { $0.0 },
            config: initializedConfig
        )
        guard
            let (newCqueryResult, invalidatedTargets) = cqueryResult.processFileChanges(
                addedFilesResult: addedFilesResult,
                deletedFiles: deletedFiles.map { $0.uri }
            )
        else {
            // If the files were all irrelevant, then there's nothing to do here.
            return []
        }
        // FIXME: We should try to edit the existing aquery instead of running a new one.
        self.aqueryResult = try processCompilerArguments(from: newCqueryResult)
        self.cqueryResult = newCqueryResult
        return invalidatedTargets
    }

    private func processCompilerArguments(
        from cqueryResult: ProcessedCqueryResult
    ) throws -> ProcessedAqueryResult {
        return try bazelTargetQuerier.aquery(
            topLevelTargets: cqueryResult.topLevelTargets,
            config: initializedConfig,
            mnemonics: compileMnemonicsToFilter + topLevelMnemonicsToFilter
        )
    }

    func clearCache() {
        cachedTargets = nil
        aqueryResult = nil
        cqueryResult = nil
    }
}

extension BazelTargetStoreImpl {
    private func writeReport(toPath path: String, creatingDirectoryAt directoryPath: String) {
        try? FileManager.default.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let report = try generateGraphReport()
            let json = try encoder.encode(report)
            try json.write(to: URL(fileURLWithPath: path), options: .atomic)
            logger.info("Graph report written to \(path, privacy: .public)")
        } catch {
            logger.error("Failed to write graph report: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func generateGraphReport() throws -> BazelTargetGraphReport {
        logger.info("Generating graph report")
        var reportTopLevel: [BazelTargetGraphReport.TopLevelTarget] = []
        var reportConfigurations: [String: BazelTargetGraphReport.Configuration] = [:]
        let topLevelTargets = cqueryResult?.topLevelTargets ?? []
        for (label, ruleType, configMnemonic) in topLevelTargets {
            let topLevelConfig = try topLevelConfigInfo(forConfigMnemonic: configMnemonic)
            let launchType: BazelTargetGraphReport.TopLevelTarget.LaunchType? = {
                if ruleType.testBundleRule != nil {
                    return .test
                } else if !ruleType.isBuildTestRule {
                    return .app
                } else {
                    return nil
                }
            }()
            let testSources: [String]? = {
                guard launchType == .test else { return nil }
                return cqueryResult?.bazelLabelToTestFilesMap[label]?.map { $0.stringValue }
            }()
            reportTopLevel.append(
                .init(
                    label: label,
                    launchType: launchType,
                    configMnemonic: configMnemonic,
                    testSources: testSources
                )
            )
            // Build invocation using the aspect approach
            let buildInvocation =
                "build \(label) --aspects=//.bsp/skbsp_generated:aspect.bzl%platform_deps_aspect --output_groups={OUTPUT_GROUP}"
            reportConfigurations[configMnemonic] = .init(
                mnemonic: configMnemonic,
                platform: topLevelConfig.platform,
                minimumOsVersion: topLevelConfig.minimumOsVersion,
                cpuArch: topLevelConfig.cpuArch,
                sdkName: topLevelConfig.sdkName,
                buildInvocation: buildInvocation
            )
        }
        var reportDependencies: [BazelTargetGraphReport.DependencyTarget] = []
        let dependencyTargets = cqueryResult?.buildTargets ?? []
        for target in dependencyTargets {
            guard let label = target.displayName else { continue }
            let configMnemonic = try parentConfig(forBSPURI: target.id.uri)
            let topLevelParent = try preferredTopLevelLabel(forConfig: configMnemonic)
            reportDependencies.append(
                .init(
                    label: label,
                    configMnemonic: configMnemonic,
                    topLevelParent: topLevelParent
                )
            )
        }
        return BazelTargetGraphReport(
            topLevelTargets: reportTopLevel,
            dependencyTargets: reportDependencies,
            configurations: reportConfigurations.values.sorted(by: { $0.mnemonic < $1.mnemonic }),
            bazelWrapper: initializedConfig.baseConfig.bazelWrapper
        )
    }
}
