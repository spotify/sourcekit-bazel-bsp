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
final class PrepareHandler: @unchecked Sendable {
    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let commandRunner: CommandRunner
    private weak var connection: LSPConnection?

    // This request is handled on the background because it can take a while to complete.
    private let queue = DispatchQueue(label: "PrepareHandler", qos: .userInteractive)

    // The current Bazel build is always stored so that we can cancel it if requested by the LSP.
    private var currentTaskLock = OSAllocatedUnfairLock<RunningProcess?>(initialState: nil)

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
        let targetsToBuild = request.targets.map { $0.uri }
        guard !targetsToBuild.isEmpty else {
            logger.info("No targets to build, skipping redundant build")
            reply(.success(VoidResponse()))
            return
        }
        let taskId = TaskId(id: "buildPrepare-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "Indexing: Building targets")
        queue.async { [weak self] in
            guard let self = self else {
                reply(.failure(ResponseError.cancelled))
                return
            }
            do {
                try self.prepare(bspURIs: targetsToBuild)
                connection?.finishTask(id: taskId, status: .ok)
                reply(.success(VoidResponse()))
            } catch {
                connection?.finishTask(id: taskId, status: .error)
                reply(.failure(error))
            }
        }
    }

    func prepare(bspURIs: [URI]) throws {
        let labels = try bspURIs.map { try targetStore.platformBuildLabel(forBSPURI: $0).0 }
        try build(bazelLabels: labels)
    }

    func build(bazelLabels labelsToBuild: [String]) throws {
        logger.debug("Will build \(labelsToBuild.joined(separator: ", "))")

        // Build the provided targets, on our special output base and taking into account special index flags.
        currentTaskLock.withLock { currentTask in
            currentTask = try? commandRunner.bazelIndexAction(
                initializedConfig: initializedConfig,
                cmd: "build \(labelsToBuild.joined(separator: " "))"
            )
        }

        logger.debug("Finished building!")
    }
}

// When the user changes targets in the IDE in the middle of a background index request,
// the LSP asks us to cancel the background one to be able to prioritize the IDE one.
extension PrepareHandler: CancelRequestObserver {
    func cancel(request: RequestID) throws {
        currentTaskLock.withLock { currentTask in
            currentTask?.terminate()
            currentTask = nil
        }
    }
}
