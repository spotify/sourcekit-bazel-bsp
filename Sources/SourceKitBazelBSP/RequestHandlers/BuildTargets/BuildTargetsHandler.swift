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

/// Handles the `workspace/buildTargets` request.
///
/// Processes the project's dependency graph and returns it to the LSP.
final class BuildTargetsHandler {

    private let targetStore: BazelTargetStore
    private weak var connection: LSPConnection?

    private var isFirstTime = true

    init(targetStore: BazelTargetStore, connection: LSPConnection? = nil) {
        self.targetStore = targetStore
        self.connection = connection
    }

    func workspaceBuildTargets(
        _ request: WorkspaceBuildTargetsRequest,
        _ id: RequestID,
        _ reply: @escaping (Result<WorkspaceBuildTargetsResponse, Error>) -> Void
    ) {
        let taskId = TaskId(id: "buildTargets-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "sourcekit-bazel-bsp: Processing the build graph...")
        do {
            nonisolated(unsafe) var shouldDispatchNotification = false
            let result = try targetStore.stateLock.withLockUnchecked {
                shouldDispatchNotification = isFirstTime
                isFirstTime = false
                return try targetStore.fetchTargets()
            }
            logger.debug("Found \(result.count, privacy: .public) targets")
            logger.logFullObjectInMultipleLogMessages(
                level: .debug,
                header: "Target list",
                result.map { $0.id.uri.stringValue }.joined(separator: ", "),
            )
            connection?.finishTask(id: taskId, status: .ok)
            reply(.success(WorkspaceBuildTargetsResponse(targets: result)))
            // If this is the first time we're responding to buildTargets, send an empty notification.
            // This triggers sourcekit-lsp to calculate the file mappings which enables jump-to-definition to work.
            // We only need to do this because we're replying to this request incorrectly.
            // We should also be able to drop this if we figure out how to make the actual LSP --index-prefix-map flag work.
            // See https://github.com/spotify/sourcekit-bazel-bsp/issues/102
            if shouldDispatchNotification {
                let notification = OnBuildTargetDidChangeNotification(changes: [])
                connection?.send(notification)
            }
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            reply(.failure(error))
        }
    }
}
