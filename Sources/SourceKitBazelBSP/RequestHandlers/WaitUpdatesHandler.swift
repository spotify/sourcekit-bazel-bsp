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

/// Handles the `waitForBuildSystemUpdates` request.
///
/// This just checks if the target store is processing updates.
final class WaitUpdatesHandler: @unchecked Sendable {

    private let targetStore: BazelTargetStore
    private weak var connection: LSPConnection?

    // We need to reply on the background because we may need to wait a while
    // for any pending updates to complete.
    private let queue = DispatchQueue(label: "WaitUpdatesHandler", qos: .userInitiated)

    init(
        targetStore: BazelTargetStore,
        connection: LSPConnection? = nil
    ) {
        self.targetStore = targetStore
        self.connection = connection
    }

    func workspaceWaitForBuildSystemUpdates(
        _ request: WorkspaceWaitForBuildSystemUpdatesRequest,
        _ id: RequestID,
        _ reply: @escaping (Result<VoidResponse, Error>) -> Void
    ) {
        let taskId = TaskId(id: "waitForBuild-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "Waiting for build system updates...")
        queue.async { [weak self] in
            guard let self = self else {
                reply(.failure(ResponseError.cancelled))
                return
            }
            self.targetStore.waitForUpdates()
            connection?.finishTask(id: taskId, status: .ok)
            reply(.success(VoidResponse()))
        }
    }
}
