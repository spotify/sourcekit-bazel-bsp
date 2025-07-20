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

private let logger = makeFileLevelBSPLogger()

/// Handles the `buildTarget/sources` request.
///
/// Returns the sources for the provided target based on previously gathered information.
final class TargetSourcesHandler {

    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore

    init(initializedConfig: InitializedServerConfig, targetStore: BazelTargetStore) {
        self.initializedConfig = initializedConfig
        self.targetStore = targetStore
    }

    func buildTargetSources(
        _ request: BuildTargetSourcesRequest,
        _ id: RequestID
    ) throws -> BuildTargetSourcesResponse {
        let targets = request.targets
        logger.info("Fetching sources for \(targets.count) targets")

        var srcs: [SourcesItem] = []
        for target in targets {
            let targetSrcs = try targetStore.bazelTargetSrcs(forBSPURI: target.uri)
            let sources = convertToSourceItems(targetSrcs)
            srcs.append(SourcesItem(target: target, sources: sources))
        }

        let count = srcs.reduce(0) { $0 + $1.sources.count }

        logger.info("Returning \(srcs.count) source specs (\(count) total source entries)")

        return BuildTargetSourcesResponse(items: srcs)
    }

    func convertToSourceItems(_ targetSrcs: [URI]) -> [SourceItem] {
        var result: [SourceItem] = []
        for src in targetSrcs {
            let srcString = src.stringValue
            let kind: SourceKitSourceItemKind
            if srcString.hasSuffix("h") {
                kind = .header
            } else {
                kind = .source
            }
            let language: Language?
            if srcString.hasSuffix("swift") {
                language = .swift
            } else if srcString.hasSuffix("m") || kind == .header {
                language = .objective_c
            } else {
                language = nil
            }
            result.append(
                SourceItem(
                    uri: src,
                    kind: .file,
                    generated: false,  // FIXME: Need to handle this properly
                    dataKind: .sourceKit,
                    data: SourceKitSourceItemData(
                        language: language,
                        kind: kind,
                        outputPath: nil  // FIXME: Related to the same flag on initialize?
                    ).encodeToLSPAny()
                )
            )
        }
        return result
    }
}
