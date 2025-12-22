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
    private let targetStore: BazelTargetStore

    init(targetStore: BazelTargetStore) {
        self.targetStore = targetStore
    }

    func buildTargetSources(
        _ request: BuildTargetSourcesRequest,
        _: RequestID
    ) throws -> BuildTargetSourcesResponse {
        let targets = request.targets
        logger.info("Fetching sources for \(targets.count, privacy: .public) targets")

        let srcs: [SourcesItem] = try targetStore.stateLock.withLockUnchecked {
            try targets.map { try targetStore.bazelTargetSrcs(forBSPURI: $0.uri) }
        }

        logger.info(
            "Returning \(srcs.count, privacy: .public) source specs"
        )

        return BuildTargetSourcesResponse(items: srcs)
    }
}
