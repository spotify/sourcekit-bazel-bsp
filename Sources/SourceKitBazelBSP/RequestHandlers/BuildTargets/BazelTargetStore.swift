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

// Represents a type that can query, processes, and store
// the project's dependency graph and its files.
protocol BazelTargetStore: AnyObject {
    var stateLock: OSAllocatedUnfairLock<Void> { get }
    var isInitialized: Bool { get }
    func fetchTargets() throws -> [BuildTarget]
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> SourcesItem
    func bspURIs(containingSrc src: URI) throws -> [URI]
    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo
    func targetsAqueryForArgsExtraction() throws -> ProcessedAqueryResult
    func clearCache()
}

enum BazelTargetStoreError: Error, LocalizedError {
    case unknownBSPURI(URI)
    case unableToMapBazelLabelToParents(String)
    case unableToMapConfigChecksumToTopLevelConfig(String)
    case unableToMapBSPURIToParentConfig(URI)
    case unableToMapConfigChecksumToTopLevelLabels(String)
    case unableToMapTopLevelLabelToConfig(String)
    case noCachedAquery

    var errorDescription: String? {
        switch self {
        case .unknownBSPURI(let uri):
            return "Unable to map '\(uri)' to a Bazel target label"
        case .unableToMapBazelLabelToParents(let label):
            return "Unable to map '\(label)' to its parents"
        case .unableToMapConfigChecksumToTopLevelConfig(let config):
            return "Unable to map config checksum '\(config)' to its top-level configuration"
        case .unableToMapBSPURIToParentConfig(let uri):
            return "Unable to map '\(uri)' to its parent configuration"
        case .unableToMapConfigChecksumToTopLevelLabels(let config):
            return "Unable to map config checksum '\(config)' to its top-level labels"
        case .unableToMapTopLevelLabelToConfig(let label):
            return "Unable to map top-level label '\(label)' to its configuration"
        case .noCachedAquery:
            return "No cached aquery result found in the store."
        }
    }
}

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
final class BazelTargetStoreImpl: BazelTargetStore, @unchecked Sendable {
    // Users of BazelTargetStore are expected to acquire this lock before reading or writing any of the internal state.
    // This is to prevent race conditions between concurrent requests. It's easier to have each request handle critical sections
    // on their own instead of trying to solve it entirely within this class.
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

    /// Returns true if the store has actually processed something.
    var isInitialized: Bool {
        return cachedTargets != nil
    }

    /// Converts a BSP BuildTarget URI to its underlying Bazel target label.
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String {
        guard let label = cqueryResult?.bspURIsToBazelLabelsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return label
    }

    /// Retrieves the SourcesItem for a given a BSP BuildTarget URI.
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> SourcesItem {
        guard let sourcesItem = cqueryResult?.bspURIsToSrcsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return sourcesItem
    }

    /// Retrieves the list of BSP BuildTarget URIs that contain a given source file.
    func bspURIs(containingSrc src: URI) throws -> [URI] {
        guard let bspURIs = cqueryResult?.srcToBspURIsMap[src] else {
            throw BazelTargetStoreError.unknownBSPURI(src)
        }
        return bspURIs
    }

    /// Retrieves the configuration information for a given Bazel **top-level** target label.
    func topLevelConfigInfo(forConfigChecksum checksum: String) throws -> BazelTargetConfigurationInfo {
        guard let config = aqueryResult?.topLevelConfigChecksumToInfoMap[checksum] else {
            throw BazelTargetStoreError.unableToMapConfigChecksumToTopLevelConfig(checksum)
        }
        return config
    }

    /// Retrieves the available configurations for a given Bazel target label.
    func parentConfig(forBSPURI uri: URI) throws -> String {
        guard let configChecksum = cqueryResult?.bspUriToParentConfigMap[uri] else {
            throw BazelTargetStoreError.unableToMapBSPURIToParentConfig(uri)
        }
        return configChecksum
    }

    /// Retrieves the list of top-level labels for a given configuration.
    func topLevelLabels(forConfig configChecksum: String) throws -> [String] {
        guard let labels = cqueryResult?.configurationToTopLevelLabelsMap[configChecksum] else {
            throw BazelTargetStoreError.unableToMapConfigChecksumToTopLevelLabels(configChecksum)
        }
        return labels
    }

    /// Provides the bazel label containing **platform information** for a given BSP URI.
    /// This is used to determine the correct set of compiler flags for the target / platform combo.
    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo {
        let bazelLabel = try bazelTargetLabel(forBSPURI: uri)
        let configChecksum = try parentConfig(forBSPURI: uri)
        let config = try topLevelConfigInfo(forConfigChecksum: configChecksum)
        let parents = try topLevelLabels(forConfig: configChecksum)
        // Since the config of these parents are all the same, it doesn't matter which one we pick here.
        let parentToUse = parents[0]
        return BazelTargetPlatformInfo(
            label: bazelLabel,
            topLevelParentLabel: parentToUse,
            topLevelParentConfig: config
        )
    }

    /// Returns the processed broad aquery containing compiler arguments for all targets we're interested in.
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
        let aqueryResult = try bazelTargetQuerier.aquery(
            topLevelTargets: cqueryResult.topLevelTargets,
            config: initializedConfig,
            mnemonics: compileMnemonicsToFilter + topLevelMnemonicsToFilter
        )

        self.aqueryResult = aqueryResult
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

    func clearCache() {
        bazelTargetQuerier.clearCache()
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
        for (label, ruleType, configChecksum) in topLevelTargets {
            let topLevelConfig = try topLevelConfigInfo(forConfigChecksum: configChecksum)
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
                    configChecksum: configChecksum,
                    testSources: testSources
                )
            )
            reportConfigurations[configChecksum] = .init(
                .init(
                    checksum: configChecksum,
                    platform: topLevelConfig.platform,
                    minimumOsVersion: topLevelConfig.minimumOsVersion,
                    cpuArch: topLevelConfig.cpuArch,
                    sdkName: topLevelConfig.sdkName,
                    dependencyBuildArgs: PrepareHandler.buildArgs(
                        minimumOsVersion: topLevelConfig.minimumOsVersion,
                        platform: topLevelConfig.platform,
                        cpuArch: topLevelConfig.cpuArch,
                        devDir: initializedConfig.devDir,
                        xcodeVersion: initializedConfig.xcodeVersion,
                        appleSupportRepoName: initializedConfig.baseConfig.appleSupportRepoName
                    )
                )
            )
        }
        var reportDependencies: [BazelTargetGraphReport.DependencyTarget] = []
        if !initializedConfig.baseConfig.compileTopLevel {
            let dependencyTargets = cqueryResult?.buildTargets ?? []
            for target in dependencyTargets {
                guard let label = target.displayName else { continue }
                let configChecksum = try parentConfig(forBSPURI: target.id.uri)
                reportDependencies.append(.init(label: label, configChecksum: configChecksum))
            }
        }
        return BazelTargetGraphReport(
            topLevelTargets: reportTopLevel,
            dependencyTargets: reportDependencies,
            configurations: reportConfigurations.values.sorted(by: { $0.checksum < $1.checksum }),
            bazelWrapper: initializedConfig.baseConfig.bazelWrapper
        )
    }
}
