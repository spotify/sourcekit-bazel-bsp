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
    func fetchTargets() throws -> [BuildTarget]
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> [URI]
    func bspURIs(containingSrc src: URI) throws -> [URI]
    func platformBuildLabel(forBSPURI uri: URI) throws -> (String, TopLevelRuleType)
    func clearCache()
    func waitForUpdates()
}

enum BazelTargetStoreError: Error, LocalizedError {
    case unknownBSPURI(URI)
    case unknownBazelLabel(String)

    var errorDescription: String? {
        switch self {
        case .unknownBSPURI(let uri): return "Requested data about a URI, but couldn't find it in the store: \(uri)"
        case .unknownBazelLabel(let label):
            return "Requested data about a Bazel label, but couldn't find it in the store: \(label)"
        }
    }
}

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
final class BazelTargetStoreImpl: BazelTargetStore {

    // The list of kinds we currently care about and can query for.
    static let supportedKinds: Set<String> = ["source file", "swift_library", "objc_library"]

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier

    // This class needs to be thread-safe because it's state can be pulled / wiped
    // from several threads at the same time.
    private let stateLock = OSAllocatedUnfairLock()

    private var bspURIsToBazelLabelsMap: [URI: String] = [:]
    private var bspURIsToSrcsMap: [URI: [URI]] = [:]
    private var srcToBspURIsMap: [URI: [URI]] = [:]
    private var availableBazelLabels: Set<String> = []
    private var bazelLabelToParentsMap: [String: [String]] = [:]
    private var topLevelLabelToRuleMap: [String: TopLevelRuleType] = [:]
    private var cachedTargets: [BuildTarget]? = nil

    init(initializedConfig: InitializedServerConfig, bazelTargetQuerier: BazelTargetQuerier = BazelTargetQuerier()) {
        self.initializedConfig = initializedConfig
        self.bazelTargetQuerier = bazelTargetQuerier
    }

    /// Converts a BSP BuildTarget URI to its underlying Bazel target label.
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let label = bspURIsToBazelLabelsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return label
    }

    /// Retrieves the list of registered source files for a given a BSP BuildTarget URI.
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> [URI] {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let srcs = bspURIsToSrcsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        return srcs
    }

    /// Retrieves the list of BSP BuildTarget URIs that contain a given source file.
    func bspURIs(containingSrc src: URI) throws -> [URI] {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let bspURIs = srcToBspURIsMap[src] else {
            throw BazelTargetStoreError.unknownBSPURI(src)
        }
        return bspURIs
    }

    /// Retrieves the list of top-level apps that a given Bazel target label belongs to.
    func bazelLabelToParents(forBazelLabel label: String) throws -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let parents = bazelLabelToParentsMap[label] else {
            throw BazelTargetStoreError.unknownBazelLabel(label)
        }
        return parents
    }

    /// Retrieves the top-level rule type for a given Bazel **top-level** target label.
    func topLevelRuleType(forBazelLabel label: String) throws -> TopLevelRuleType {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let ruleType = topLevelLabelToRuleMap[label] else {
            throw BazelTargetStoreError.unknownBazelLabel(label)
        }
        return ruleType
    }

    func waitForUpdates() {
        // If we can acquire the lock, it means we're not updating the internal store.
        stateLock.lock()
        stateLock.unlock()
    }

    /// Provides the bazel label containing **platform information** for a given BSP URI.
    /// This is used to determine the correct set of compiler flags for the target / platform combo.
    func platformBuildLabel(forBSPURI uri: URI) throws -> (String, TopLevelRuleType) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let bazelLabel = bspURIsToBazelLabelsMap[uri] else {
            throw BazelTargetStoreError.unknownBSPURI(uri)
        }
        guard let parents = bazelLabelToParentsMap[bazelLabel] else {
            throw BazelTargetStoreError.unknownBazelLabel(bazelLabel)
        }
        // FIXME: When a target can compile to multiple platforms, the way Xcode handles it is by selecting
        // the one matching your selected simulator in the IDE. We don't have any sort of special IDE integration
        // at the moment, so for now we just select the first parent.
        let parentToUse = parents[0]
        guard let rule = topLevelLabelToRuleMap[parentToUse] else {
            throw BazelTargetStoreError.unknownBazelLabel(parentToUse)
        }
        return (
            "\(bazelLabel)_\(rule.platform)\(initializedConfig.baseConfig.buildTestSuffix)",
            rule
        )
    }

    @discardableResult
    func fetchTargets() throws -> [BuildTarget] {
        stateLock.lock()
        defer { stateLock.unlock() }

        // This request needs caching because it gets called after file changes,
        // even if nothing was invalidated.
        if let cachedTargets = cachedTargets {
            return cachedTargets
        }

        // Start by determining which platforms each top-level app is for.
        // This will allow us to later determine which sets of flags to provide
        // depending on the target / platform combo the LSP is interested in,
        // as well as throwing an error if the user provided something that we
        // don't currently know how to process.
        let topLevelTargetData = try bazelTargetQuerier.queryTopLevelRuleTypes(
            forConfig: initializedConfig.baseConfig,
            rootUri: initializedConfig.rootUri,
        )
        let topLevelTargets = topLevelTargetData.map { $0.0 }

        logger.debug("Queried top-level target data: \(topLevelTargetData)")

        // Parse the target dependencies for the top-level targets.
        // This doesn't include information about which top-level app a target belongs to,
        // but we'll fill that in below.
        let targets: [BlazeQuery_Target] = try bazelTargetQuerier.queryTargetDependencies(
            forTargets: topLevelTargets,
            forConfig: initializedConfig.baseConfig,
            rootUri: initializedConfig.rootUri,
            kinds: Self.supportedKinds
        )

        let targetData = try BazelQueryParser.parseTargetsWithProto(
            from: targets,
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
        for (target, ruleType) in topLevelTargetData {
            topLevelLabelToRuleMap[target] = ruleType
        }

        // We need to now map which targets belong to which top-level apps,
        // to further support the target / platform combo differentiation mentioned above.

        // We need to include the top-level data here as well to be able to traverse the graph correctly.
        let depGraphKinds = Self.supportedKinds.union(TopLevelRuleType.allCases.map { $0.rawValue })

        let depGraph = try bazelTargetQuerier.queryDependencyGraph(
            ofTargets: topLevelTargets,
            forConfig: initializedConfig.baseConfig,
            rootUri: initializedConfig.rootUri,
            kinds: depGraphKinds
        )

        // We should ignore any app -> app nodes as we don't want to follow things such
        // as the watchos_application field in ios_application rules. Otherwise some targets
        // will be misclassified.
        let targetsToIgnore = Set(topLevelTargets)

        for topLevelTarget in topLevelTargets {
            let deps = traverseGraph(from: topLevelTarget, in: depGraph, ignoring: targetsToIgnore)
            for dep in deps {
                guard availableBazelLabels.contains(dep) else {
                    // Ignore any labels that we also ignored above
                    continue
                }
                bazelLabelToParentsMap[dep, default: []].append(topLevelTarget)
            }
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
        stateLock.lock()
        defer { stateLock.unlock() }

        bspURIsToBazelLabelsMap = [:]
        bspURIsToSrcsMap = [:]
        srcToBspURIsMap = [:]
        bazelLabelToParentsMap = [:]
        availableBazelLabels = []
        topLevelLabelToRuleMap = [:]
        bazelTargetQuerier.clearCache()
        cachedTargets = nil
    }
}
