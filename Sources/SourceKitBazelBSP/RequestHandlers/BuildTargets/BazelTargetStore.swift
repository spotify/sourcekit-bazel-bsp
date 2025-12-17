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
    func fetchTargets() throws -> [BuildTarget]
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> [URI]
    func bspURIs(containingSrc src: URI) throws -> [URI]
    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo
    func targetsAqueryForArgsExtraction() throws -> AqueryResult
    func clearCache()
}

enum BazelTargetStoreError: Error, LocalizedError {
    case noTopLevelTargets([TopLevelRuleType])
    case unsupportedTargetType(target: String, type: String, supportedTypes: [TopLevelRuleType])
    case unknownBSPURI(URI)
    case unableToMapBazelLabelToParents(String)
    case unableToMapBazelLabelToTopLevelRuleType(String)
    case unableToMapBazelLabelToTopLevelConfig(String)
    case noCachedAquery

    var errorDescription: String? {
        switch self {
        case .noTopLevelTargets(let rules):
            return """
                No top-level targets found in the store for query of kind: \
                \(rules.map { $0.rawValue }.joined(separator: ", "))
                """
        case .unsupportedTargetType(let target, let type, let supportedTypes):
            return """
                Unsupported top-level target type: '\(type)' for target: \
                '\(target)' supported types: \(supportedTypes.map { $0.rawValue }.joined(separator: ", "))
                """
        case .unknownBSPURI(let uri):
            return "Unable to map '\(uri)' to a Bazel target label"
        case .unableToMapBazelLabelToParents(let label):
            return "Unable to map '\(label)' to its parents"
        case .unableToMapBazelLabelToTopLevelRuleType(let label):
            return "Unable to map '\(label)' to its top-level rule type"
        case .unableToMapBazelLabelToTopLevelConfig(let label):
            return "Unable to map '\(label)' to its top-level configuration"
        case .noCachedAquery:
            return "No cached aquery result found in the store."
        }
    }
}

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
final class BazelTargetStoreImpl: BazelTargetStore {

    // The list of kinds that provide compilation params that are used by the BSP.
    // These are collected from the top-level targets that depend on them.
    static let supportedKinds: Set<String> = ["source file", "swift_library", "objc_library"]

    // The mnemonics representing compilation actions
    static let compileMnemonics: Set<String> = ["SwiftCompile", "ObjcCompile", "CppCompile"]

    // The mnemonics representing top-level rule actions
    // - `BundleTreeApp` for finding bundling rules like `ios_unit_test`, `ios_application`
    // - `SignBinary` for finding macOS CLI app rules like `macos_command_line_application`
    // - `TestRunner` for finding build test rules like `ios_build_test`
    static let topLevelMnemonics: Set<String> = ["BundleTreeApp", "SignBinary", "TestRunner"]

    // Users of BazelTargetStore are expected to acquire this lock before reading or writing any of the internal state.
    // This is to prevent race conditions between concurrent requests. It's easier to have each request handle critical sections
    // on their own instead of trying to solve it entirely within this class.
    let stateLock = OSAllocatedUnfairLock()

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier
    private let bazelTargetAquerier: BazelTargetAquerier

    private var bspURIsToBazelLabelsMap: [URI: String] = [:]
    private var bspURIsToSrcsMap: [URI: [URI]] = [:]
    private var srcToBspURIsMap: [URI: [URI]] = [:]
    private var availableBazelLabels: Set<String> = []
    private var bazelLabelToParentsMap: [String: [String]] = [:]
    private var topLevelLabelToRuleMap: [String: TopLevelRuleType] = [:]
    private var topLevelLabelToConfigMap: [String: BazelTargetConfigurationInfo] = [:]
    private var cachedTargets: [BuildTarget]? = nil
    private var targetsAqueryResult: AqueryResult? = nil

    init(
        initializedConfig: InitializedServerConfig,
        bazelTargetQuerier: BazelTargetQuerier = BazelTargetQuerier(),
        bazelTargetAquerier: BazelTargetAquerier = BazelTargetAquerier()
    ) {
        self.initializedConfig = initializedConfig
        self.bazelTargetQuerier = bazelTargetQuerier
        self.bazelTargetAquerier = bazelTargetAquerier
    }

    /// Converts a BSP BuildTarget URI to its underlying Bazel target label.
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String {
        guard let label = bspURIsToBazelLabelsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return label
    }

    /// Retrieves the list of registered source files for a given a BSP BuildTarget URI.
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> [URI] {
        guard let srcs = bspURIsToSrcsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return srcs
    }

    /// Retrieves the list of BSP BuildTarget URIs that contain a given source file.
    func bspURIs(containingSrc src: URI) throws -> [URI] {
        guard let bspURIs = srcToBspURIsMap[src] else {
            throw BazelTargetStoreError.unknownBSPURI(src)
        }
        return bspURIs
    }

    /// Retrieves the list of top-level apps that a given Bazel target label belongs to.
    func bazelLabelToParents(forBazelLabel label: String) throws -> [String] {
        guard let parents = bazelLabelToParentsMap[label] else {
            throw BazelTargetStoreError.unableToMapBazelLabelToParents(label)
        }
        return parents
    }

    /// Retrieves the top-level rule type for a given Bazel **top-level** target label.
    func topLevelRuleType(forBazelLabel label: String) throws -> TopLevelRuleType {
        guard let ruleType = topLevelLabelToRuleMap[label] else {
            throw BazelTargetStoreError.unableToMapBazelLabelToTopLevelRuleType(label)
        }
        return ruleType
    }

    /// Retrieves the configuration information for a given Bazel **top-level** target label.
    func topLevelConfigInfo(forBazelLabel label: String) throws -> BazelTargetConfigurationInfo {
        guard let config = topLevelLabelToConfigMap[label] else {
            throw BazelTargetStoreError.unableToMapBazelLabelToTopLevelConfig(label)
        }
        return config
    }

    /// Provides the bazel label containing **platform information** for a given BSP URI.
    /// This is used to determine the correct set of compiler flags for the target / platform combo.
    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo {
        let bazelLabel = try bazelTargetLabel(forBSPURI: uri)
        let parents = try bazelLabelToParents(forBazelLabel: bazelLabel)
        // FIXME: When a target can compile to multiple platforms, the way Xcode handles it is by selecting
        // the one matching your selected simulator in the IDE. We don't have any sort of special IDE integration
        // at the moment, so for now we just select the first parent.
        let parentToUse = parents[0]
        if parents.count > 1 {
            logger.warning(
                "Target \(uri.description, privacy: .public) has multiple top-level parents; will pick the first one: \(parentToUse, privacy: .public)"
            )
        }
        let rule = try topLevelRuleType(forBazelLabel: parentToUse)
        let config = try topLevelConfigInfo(forBazelLabel: parentToUse)
        return BazelTargetPlatformInfo(
            label: bazelLabel,
            topLevelParentLabel: parentToUse,
            topLevelParentRuleType: rule,
            topLevelParentConfig: config
        )
    }

    /// Returns the processed broad aquery containing compiler arguments for all targets we're interested in.
    func targetsAqueryForArgsExtraction() throws -> AqueryResult {
        guard let targetsAqueryResult = targetsAqueryResult else {
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

        let topLevelRuleTypes = initializedConfig.baseConfig.topLevelRulesToDiscover
        let topLevelRuleKinds = Set(topLevelRuleTypes.map(\.rawValue))

        // Query all the targets we are interested in one invocation:
        //  - Top-level targets (e.g. `ios_application`, `ios_unit_test`, etc.)
        //  - Dependencies of the top-level targets (e.g. `swift_library`, `objc_library`, etc.)
        let allTargets =
            try bazelTargetQuerier
            .queryTargets(
                config: initializedConfig,
                dependencyKinds: Self.supportedKinds
            )

        // Find the top-level targets (based on our supported rule kinds) from the query results.
        // We don't need to handle the case where a provided target is missing entirely
        // because Bazel itself will fail when this is the case.
        let userProvidedTargets = Set(initializedConfig.baseConfig.targets)
        var topLevelTargetLabels: [String] = []
        var topLevelTargetTypes: [TopLevelRuleType] = []
        var dependencyTargets: [BlazeQuery_Target] = []
        for target in allTargets {
            let kind = target.rule.ruleClass
            let name = target.rule.name
            if userProvidedTargets.contains(name) {
                guard let topLevelRuleType = TopLevelRuleType(rawValue: kind) else {
                    throw BazelTargetStoreError.unsupportedTargetType(
                        target: name,
                        type: kind,
                        supportedTypes: topLevelRuleTypes
                    )
                }
                topLevelTargetLabels.append(name)
                topLevelTargetTypes.append(topLevelRuleType)
            } else {
                dependencyTargets.append(target)
            }
        }

        guard !topLevelTargetLabels.isEmpty else {
            throw BazelTargetStoreError.noTopLevelTargets(topLevelRuleTypes)
        }

        logger.debug("Queried top-level targets: \(topLevelTargetLabels.joined(separator: " "), privacy: .public)")

        let targetData = try BazelQueryParser.parseTargetsWithProto(
            from: dependencyTargets,
            rootUri: initializedConfig.rootUri,
            toolchainPath: initializedConfig.devToolchainPath,
        )

        // Fill the local cache based on the data we got from the query
        for (target, srcs) in targetData {
            guard let displayName = target.displayName else {
                // Should not happen, but the property is an optional
                continue
            }
            let uri = target.id.uri
            bspURIsToBazelLabelsMap[uri] = displayName
            bspURIsToSrcsMap[uri] = srcs
            availableBazelLabels.insert(displayName)
            for src in srcs {
                srcToBspURIsMap[src, default: []].append(uri)
            }
        }

        let topLevelTargets = zip(topLevelTargetLabels, topLevelTargetTypes)
        for (target, ruleType) in topLevelTargets {
            topLevelLabelToRuleMap[target] = ruleType
        }

        // Now, run a broad aquery against all top-level targets
        // to get the compiler arguments for all targets we're interested in.
        // We pass top-level mnemonics in addition to compile ones as a method to gain access to the parent's configuration id.
        // We can then use this to locate the exact variant of the target we are looking for.
        // BundleTreeApp is used by most rule types, while SignBinary is for macOS CLI apps specifically.
        let targetsAqueryResult = try bazelTargetAquerier.aquery(
            targets: topLevelTargetLabels,
            config: initializedConfig,
            mnemonics: Self.compileMnemonics.union(Self.topLevelMnemonics),
            additionalFlags: [
                "--noinclude_artifacts",
                "--noinclude_aspects",
                "--features=-compiler_param_file",  // Context: https://github.com/spotify/sourcekit-bazel-bsp/pull/60
            ]
        )
        self.targetsAqueryResult = targetsAqueryResult

        logger.info("Finished gathering all compiler arguments")

        // We need to now map which targets belong to which top-level apps,
        // to further support the target / platform combo differentiation mentioned above.

        // We need to include the top-level data here as well to be able to traverse the graph correctly.
        let depGraphKinds = Self.supportedKinds.union(topLevelRuleKinds)
        let depGraph = try bazelTargetQuerier.queryDependencyGraph(
            ofTargets: topLevelTargetLabels,
            forConfig: initializedConfig,
            rootUri: initializedConfig.rootUri,
            kinds: depGraphKinds
        )

        // We should ignore any app -> app nodes as we don't want to follow things such
        // as the watchos_application field in ios_application rules. Otherwise some targets
        // will be misclassified.
        let targetsToIgnore = Set(topLevelTargetLabels)

        for topLevelTarget in topLevelTargetLabels {
            let deps = traverseGraph(from: topLevelTarget, in: depGraph, ignoring: targetsToIgnore)
            for dep in deps {
                guard availableBazelLabels.contains(dep) else {
                    // Ignore any labels that we also ignored above
                    continue
                }
                bazelLabelToParentsMap[dep, default: []].append(topLevelTarget)
            }
        }

        // Wrap up by fetching the info we need from the top-level targets that will allow us
        // to build individual targets via the CLI (if not passing --compile-top-level).
        for (target, ruleType) in topLevelTargets {
            let info = try BazelQueryParser.topLevelConfigInfo(
                ofTarget: target,
                withType: ruleType,
                in: targetsAqueryResult
            )
            topLevelLabelToConfigMap[target] = info
        }

        let result = targetData.map { $0.0 }
        cachedTargets = result
        return result
    }

    private func traverseGraph(from target: String, in graph: [String: [String]], ignoring: Set<String>) -> Set<String>
    {
        var visited = Set<String>()
        var result = Set<String>()
        var queue: [String] = graph[target, default: []]
        while let curr = queue.popLast() {
            guard !ignoring.contains(curr) else {
                continue
            }
            result.insert(curr)
            for dep in graph[curr, default: []] {
                if !visited.contains(dep) {
                    visited.insert(dep)
                    queue.append(dep)
                }
            }
        }
        return result
    }

    func clearCache() {
        bspURIsToBazelLabelsMap = [:]
        bspURIsToSrcsMap = [:]
        srcToBspURIsMap = [:]
        bazelLabelToParentsMap = [:]
        availableBazelLabels = []
        topLevelLabelToRuleMap = [:]
        topLevelLabelToConfigMap = [:]
        bazelTargetQuerier.clearCache()
        cachedTargets = nil
        targetsAqueryResult = nil
    }
}
