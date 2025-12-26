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
            nonisolated(unsafe) var shouldReplyEmpty = false
            let result = try targetStore.stateLock.withLockUnchecked {
                shouldReplyEmpty = isFirstTime
                isFirstTime = false
                // If this is the first time we're responding to buildTargets, sourcekit-lsp will expect us to return an empty list
                // and then later send a notification containing the changes for performance reasons.
                // See https://github.com/spotify/sourcekit-bazel-bsp/issues/102
                if shouldReplyEmpty {
                    reply(.success(WorkspaceBuildTargetsResponse(targets: [])))
                }
                let result = try targetStore.fetchTargets()
                return result
            }
            connection?.finishTask(id: taskId, status: .ok)
            if shouldReplyEmpty {
                let targetEvents = result.map { target in
                    BuildTargetEvent(
                        target: target.id,
                        kind: .created,
                        dataKind: nil,
                        data: nil
                    )
                }
                let notification = OnBuildTargetDidChangeNotification(
                    changes: targetEvents
                )
                connection?.send(notification)
            } else {
                reply(.success(WorkspaceBuildTargetsResponse(targets: result)))
            }
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            reply(.failure(error))
        }
    }
}
