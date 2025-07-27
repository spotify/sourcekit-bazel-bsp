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

import BuildServerProtocol
import Foundation
import LanguageServerProtocol

enum BazelTargetStoreError: Error, LocalizedError {
    case unknownBSPURI(URI)

    var errorDescription: String? {
        switch self {
        case .unknownBSPURI(let uri): return "Requested data about a URI, but couldn't find it in the store: \(uri)"
        }
    }
}

/// Abstraction that can queries, processes, and stores the project's dependency graph and its files.
/// Used by many of the requests to calculate and provide data about the project's targets.
final class BazelTargetStore {

    // The list of rules we currently care about and can process
    static let supportedRuleTypes: Set<String> = ["swift_library", "objc_library"]

    private let initializedConfig: InitializedServerConfig
    private let bazelTargetQuerier: BazelTargetQuerier

    private var bspURIsToBazelLabelsMap: [URI: String] = [:]
    private var bspURIsToSrcsMap: [URI: [URI]] = [:]
    private var srcToBspURIsMap: [URI: [URI]] = [:]

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

    func fetchTargets() throws -> [BuildTarget] {
        let xml = try bazelTargetQuerier.queryTargets(
            forConfig: initializedConfig.baseConfig,
            rootUri: initializedConfig.rootUri,
            kinds: Self.supportedRuleTypes
        )

        let targetData = try BazelQueryParser.parseTargets(
            from: xml,
            supportedRuleTypes: Self.supportedRuleTypes,
            rootUri: initializedConfig.rootUri,
            toolchainPath: initializedConfig.devToolchainPath
        )

        // Fill the local cache based on the data we got from the query
        for (target, srcs) in targetData {
            let uri = target.id.uri
            bspURIsToBazelLabelsMap[uri] = target.displayName
            bspURIsToSrcsMap[uri] = srcs
            for src in srcs {
                srcToBspURIsMap[src, default: []].append(uri)
            }
        }

        return targetData.map { $0.0 }
    }

    func clearCache() {
        bspURIsToBazelLabelsMap = [:]
        bspURIsToSrcsMap = [:]
        srcToBspURIsMap = [:]
        bazelTargetQuerier.clearCache()
    }
}
