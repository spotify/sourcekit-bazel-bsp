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

// Represents a type that can query, processes, and store
// the project's dependency graph and its files.
protocol BazelTargetStore: AnyObject {
    func fetchTargets() throws -> [BuildTarget]
    func bazelTargetLabel(forBSPURI uri: URI) throws -> String
    func bazelTargetSrcs(forBSPURI uri: URI) throws -> [URI]
    func bspURIs(containingSrc src: URI) throws -> [URI]
    func clearCache()
}

enum BazelTargetStoreError: Error, LocalizedError {
    case unknownBSPURI(URI)
    case unknownBazelLabel(String)

    var errorDescription: String? {
        switch self {
        case .unknownBSPURI(let uri): return "Requested data about a URI, but couldn't find it in the store: \(uri)"
        case .unknownBazelLabel(let label): return "Requested data about a Bazel label, but couldn't find it in the store: \(label)"
        }
    }
}

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
final class BazelTargetStoreImpl: BazelTargetStore {
    // The list of **library** rules we currently care about and can process
    // Other things like source files are handled separately.
    static let supportedRuleTypes: Set<String> = ["swift_library", "objc_library"]

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier

    private var bspURIsToBazelLabelsMap: [URI: String] = [:]
    private var bspURIsToSrcsMap: [URI: [URI]] = [:]
    private var srcToBspURIsMap: [URI: [URI]] = [:]
    private var availableBazelLabels: Set<String> = []
    private var bazelLabelToParentsMap: [String: [String]] = [:]

    init(initializedConfig: InitializedServerConfig, bazelTargetQuerier: BazelTargetQuerier = BazelTargetQuerier()) {
        self.initializedConfig = initializedConfig
        self.bazelTargetQuerier = bazelTargetQuerier
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
            throw BazelTargetStoreError.unknownBazelLabel(label)
        }
        return parents
    }

    @discardableResult
    func fetchTargets() throws -> [BuildTarget] {
        let targets: [BlazeQuery_Target] = try bazelTargetQuerier.queryTargetDependencies(
            forConfig: initializedConfig.baseConfig,
            rootUri: initializedConfig.rootUri,
            kinds: Self.supportedRuleTypes.union(["source file"])
        )

        let targetData = try BazelQueryParser.parseTargetsWithProto(
            from: targets,
            supportedRuleTypes: Self.supportedRuleTypes,
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

        // We need to now map which targets belong to which top-level apps.
        // This will allow us to provide different sets of compiler flags depending
        // on which target platform the LSP is interested in, for the case where
        // a target is shared between multiple top-level apps.
        for topLevelTarget in initializedConfig.baseConfig.targets {
            let deps = try bazelTargetQuerier.queryDependencyLabels(
                ofTarget: topLevelTarget,
                forConfig: initializedConfig.baseConfig,
                rootUri: initializedConfig.rootUri,
                kinds: Self.supportedRuleTypes
            )
            for dep in deps {
                guard availableBazelLabels.contains(dep) else {
                    // Ignore any labels that we also ignored above
                    continue
                }
                bazelLabelToParentsMap[dep, default: []].append(topLevelTarget)
            }
        }

        return targetData.map { $0.0 }
    }

    func clearCache() {
        bspURIsToBazelLabelsMap = [:]
        bspURIsToSrcsMap = [:]
        srcToBspURIsMap = [:]
        bazelLabelToParentsMap = [:]
        availableBazelLabels = []
        bazelTargetQuerier.clearCache()
    }
}
