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
import LanguageServerProtocolJSONRPC

final class BuildTargetSourcesHandler {

    let initializedConfig: InitializedServerConfig

    init(initializedConfig: InitializedServerConfig) {
        self.initializedConfig = initializedConfig
    }

    func handle(
        request: BuildTargetSourcesRequest,
        srcsMap: [URI: [URI]]
    ) throws -> BuildTargetSourcesResponse {
        let targets = request.targets.map { $0.uri }

        logger.info("Getting sources for \(targets.count) targets")

        var srcs: [SourcesItem] = []
        for targetUri in targets {
            guard let targetSrcs = srcsMap[targetUri] else {
                logger.error("Target \(targetUri.stringValue) not found")
                return BuildTargetSourcesResponse(items: [])
            }
            let target = BuildTargetIdentifier(uri: targetUri)
            srcs.append(
                SourcesItem(
                    target: target,
                    sources: srcsToResponse(srcs: targetSrcs),
                ))
        }

        let count = srcs.reduce(0) { $0 + $1.sources.count }

        logger.info(
            "Returning \(srcs.count) source specs (\(count) total source entries)"
        )

        return BuildTargetSourcesResponse(items: srcs)
    }

    func srcsToResponse(srcs: [URI]) -> [SourceItem] {
        var result: [SourceItem] = []
        for src in srcs {
            let kind: SourceKitSourceItemKind
            if src.stringValue.hasSuffix("h") {
                kind = .header
            } else {
                kind = .source
            }
            let language: Language
            if src.stringValue.hasSuffix("swift") {
                language = .swift
            } else {
                language = .objective_c
            }
            result.append(
                SourceItem(
                    uri: src,
                    kind: .file,
                    generated: false,
                    dataKind: .sourceKit,
                    data: SourceKitSourceItemData(
                        language: language,
                        kind: kind,
                        outputPath: nil  // FIXME
                    ).encodeToLSPAny()
                )
            )
        }
        return result
    }
}
