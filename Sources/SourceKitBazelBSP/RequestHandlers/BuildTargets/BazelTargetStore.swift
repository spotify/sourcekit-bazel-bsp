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
    case unableToMapBazelLabelToTopLevelRuleType(String)
    case unableToMapBazelLabelToTopLevelConfig(String)
    case noCachedAquery

    var errorDescription: String? {
        switch self {
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
final class BazelTargetStoreImpl: BazelTargetStore, @unchecked Sendable {

    // The list of kinds that provide compilation params that are used by the BSP.
    // These are collected from the top-level targets that depend on them.
    static let libraryKinds: [String] = ["swift_library", "objc_library"]
    static let sourceFileKinds: [String] = ["source file"]

    // The mnemonics representing compilation actions
    static let compileMnemonics: [String] = ["SwiftCompile", "ObjcCompile", "CppCompile"]

    // The mnemonics representing top-level rule actions
    // - `BundleTreeApp` for finding bundling rules like `ios_unit_test`, `ios_application`
    // - `SignBinary` for finding macOS CLI app rules like `macos_command_line_application`
    // - `TestRunner` for finding build test rules like `ios_build_test`
    static let topLevelMnemonics: [String] = ["BundleTreeApp", "SignBinary", "TestRunner"]

    // Users of BazelTargetStore are expected to acquire this lock before reading or writing any of the internal state.
    // This is to prevent race conditions between concurrent requests. It's easier to have each request handle critical sections
    // on their own instead of trying to solve it entirely within this class.
    let stateLock = OSAllocatedUnfairLock()

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier

    private var cachedTargets: [BuildTarget]? = nil
    private var aqueryResult: ProcessedAqueryResult? = nil
    private var cqueryResult: ProcessedCqueryResult? = nil

    init(
        initializedConfig: InitializedServerConfig,
        bazelTargetQuerier: BazelTargetQuerier = BazelTargetQuerier(),
    ) {
        self.initializedConfig = initializedConfig
        self.bazelTargetQuerier = bazelTargetQuerier
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

    /// Retrieves the list of top-level apps that a given Bazel target label belongs to.
    func bazelLabelToParents(forBazelLabel label: String) throws -> [String] {
        guard let parents = cqueryResult?.bazelLabelToParentsMap[label] else {
            throw BazelTargetStoreError.unableToMapBazelLabelToParents(label)
        }
        return parents
    }

    /// Retrieves the top-level rule type for a given Bazel **top-level** target label.
    func topLevelRuleType(forBazelLabel label: String) throws -> TopLevelRuleType {
        guard let ruleType = cqueryResult?.topLevelLabelToRuleMap[label] else {
            throw BazelTargetStoreError.unableToMapBazelLabelToTopLevelRuleType(label)
        }
        return ruleType
    }

    /// Retrieves the configuration information for a given Bazel **top-level** target label.
    func topLevelConfigInfo(forBazelLabel label: String) throws -> BazelTargetConfigurationInfo {
        guard let config = aqueryResult?.topLevelLabelToConfigMap[label] else {
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
            dependencyKinds: Self.libraryKinds + Self.sourceFileKinds,
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
            mnemonics: Self.compileMnemonics + Self.topLevelMnemonics
        )

        self.aqueryResult = aqueryResult
        self.cqueryResult = cqueryResult

        let result = cqueryResult.buildTargets
        cachedTargets = result

        return result
    }

    func clearCache() {
        bazelTargetQuerier.clearCache()
        cachedTargets = nil
        aqueryResult = nil
        cqueryResult = nil
    }
}
