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

import struct os.OSAllocatedUnfairLock

private let logger = makeFileLevelBSPLogger()

/// Handles the `buildTarget/prepare` request.
///
/// Builds the provided list of targets upon request.
final class PrepareHandler {
    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let commandRunner: CommandRunner
    private weak var connection: LSPConnection?

    // The current Bazel build is always stored so that we can cancel it if requested by the LSP.
    private var currentTaskLock = OSAllocatedUnfairLock<(RunningProcess, RequestID)?>(initialState: nil)

    init(
        initializedConfig: InitializedServerConfig,
        targetStore: BazelTargetStore,
        commandRunner: CommandRunner = ShellCommandRunner(),
        connection: LSPConnection? = nil,
    ) {
        self.initializedConfig = initializedConfig
        self.targetStore = targetStore
        self.commandRunner = commandRunner
        self.connection = connection
    }

    func prepareTarget(
        _ request: BuildTargetPrepareRequest,
        _ id: RequestID,
        _ reply: @escaping (Result<VoidResponse, Error>) -> Void
    ) {
        let targetsToBuild = request.targets
        guard !targetsToBuild.isEmpty else {
            logger.info("No targets to build.")
            reply(.success(VoidResponse()))
            return
        }

        let taskId = TaskId(id: "buildPrepare-\(id.description)")
        let taskTitle: String = {
            guard targetsToBuild.count == 1 else {
                return "sourcekit-bazel-bsp: Building \(targetsToBuild.count) targets..."
            }
            let targetUrl = targetsToBuild[0].uri.fileURL
            let targetName = targetUrl?.lastPathComponent ?? targetsToBuild[0].uri.stringValue
            return "sourcekit-bazel-bsp: Building \(targetName)..."
        }()
        connection?.startWorkTask(
            id: taskId,
            title: taskTitle
        )
        do {
            let labels = try targetStore.stateLock.withLockUnchecked {
                return try targetsToBuild.map {
                    try targetStore.platformBuildLabelInfo(forBSPURI: $0.uri).buildTestLabel
                }
            }
            nonisolated(unsafe) let reply = reply
            try build(bazelLabels: labels, id: id) { [connection] error in
                if let error = error {
                    connection?.finishTask(id: taskId, status: .error)
                    reply(.failure(error))
                }
                connection?.finishTask(id: taskId, status: .ok)
                reply(.success(VoidResponse()))
            }
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            reply(.failure(error))
        }
    }

    func build(
        bazelLabels labelsToBuild: [String],
        id: RequestID,
        completion: @escaping ((ResponseError?) -> Void)
    ) throws {
        logger.info("Will build \(labelsToBuild.joined(separator: ", "))")

        nonisolated(unsafe) let completion = completion
        try currentTaskLock.withLock { [commandRunner, initializedConfig] currentTask in
            // Build the provided targets, on our special output base and taking into account special index flags.
            let process = try commandRunner.bazelIndexAction(
                baseConfig: initializedConfig.baseConfig,
                outputBase: initializedConfig.outputBase,
                cmd: "build \(labelsToBuild.joined(separator: " "))",
                rootUri: initializedConfig.rootUri
            )
            process.setTerminationHandler { code, stderr in
                if code == 0 {
                    logger.info("Finished building! (Request ID: \(id.description))")
                    completion(nil)
                } else {
                    if code == 8 {
                        logger.info("Build (Request ID: \(id.description)) was cancelled.")
                        completion(ResponseError.cancelled)
                    } else {
                        logger.logFullObjectInMultipleLogMessages(
                            level: .error,
                            header: "Failed to build targets.",
                            stderr
                        )
                        completion(ResponseError(code: .internalError, message: "The bazel build failed."))
                    }
                }
            }
            currentTask = (process, id)
        }
    }
}

// When the user changes targets in the IDE in the middle of a background index request,
// the LSP asks us to cancel the background one to be able to prioritize the IDE one.
extension PrepareHandler: CancelRequestObserver {
    func cancel(request: RequestID) throws {
        currentTaskLock.withLock { currentTaskData in
            guard let data = currentTaskData else {
                return
            }
            guard data.1 == request else {
                return
            }
            data.0.terminate()
            currentTaskData = nil
        }
    }
}
