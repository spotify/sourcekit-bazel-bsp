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
import os

final class BSPServerMessageHandlerImpl: BSPServerMessageHandler, @unchecked Sendable {

    // FIXME: Make it work without locking
    let lock: OSAllocatedUnfairLock<Void> = OSAllocatedUnfairLock<Void>()

    let baseConfig: BaseServerConfig
    let connection: JSONRPCConnection
    let taskLogger: TaskLogger

    lazy var workspaceBuildTargetsHandler = WorkspaceBuildTargetsHandler(
        initializedConfig: initializedConfig
    )
    lazy var textDocumentSourceKitOptionsHandler = TextDocumentSourceKitOptionsHandler(
        initializedConfig: initializedConfig
    )
    lazy var prepareTargetHandler = PrepareTargetHandler(
        initializedConfig: initializedConfig
    )
    lazy var buildTargetSourcesHandler = BuildTargetSourcesHandler(
        initializedConfig: initializedConfig
    )

    private var initializedConfig: InitializedServerConfig!
    private var didAskToShutdown = false

    init(
        baseConfig: BaseServerConfig,
        connection: JSONRPCConnection
    ) {
        self.baseConfig = baseConfig
        self.connection = connection
        self.taskLogger = TaskLogger(connection: connection)
    }

    func initializeBuild(
        _ request: InitializeBuildRequest,
        _ id: RequestID
    ) throws -> InitializeBuildResponse {
        let taskId = TaskId(id: "initializeBuild-\(id.description)")
        taskLogger.startWorkTask(
            id: taskId, title: "Indexing: Initializing sourcekit-bazel-bsp")
        do {
            let rootUri = request.rootUri.arbitrarySchemeURL.path
            logger.info("rootUri: \(rootUri, privacy: .public)")
            let regularOutputBase = URL(
                fileURLWithPath: try shell(
                    baseConfig.bazelWrapper + " info output_base",
                    cwd: rootUri
                ))
            logger.info("regularOutputBase: \(regularOutputBase, privacy: .public)")
            let lastPath = regularOutputBase.lastPathComponent
            let outputBase =
                regularOutputBase
                .deletingLastPathComponent()
                .appendingPathComponent("\(lastPath)-sourcekit-bazel-bsp")
                .path
            // let outputBase = rootUri + "/bazel-out-sourcekit-bazel-bsp"
            logger.info("outputBase: \(outputBase, privacy: .public)")
            let flags = baseConfig.indexFlags.joined(separator: " ")
            let outputPath = try shell(
                baseConfig.bazelWrapper + " --output_base=\(outputBase) info output_path \(flags)",
                cwd: rootUri
            )
            logger.info("outputPath: \(outputPath, privacy: .public)")
            let devDir = try shell("xcode-select --print-path")
            let sdkRoot = try shell("xcrun --sdk iphonesimulator --show-sdk-path")
            self.initializedConfig = InitializedServerConfig(
                baseConfig: baseConfig,
                rootUri: rootUri,
                outputBase: outputBase,
                outputPath: outputPath,
                devDir: devDir,
                sdkRoot: sdkRoot,
                taskLogger: taskLogger
            )
            let result = try InitializeRequestHandler().handle(
                request: request,
                initializedConfig: initializedConfig,
            )
            taskLogger.finishTask(id: taskId, status: .ok)
            return result
        } catch {
            taskLogger.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func onBuildInitialized(_ notification: OnBuildInitializedNotification) throws {
        logger.info("Received onBuildInitialized notification")
    }

    func waitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest,
        _ id: RequestID
    ) -> VoidResponse {
        return VoidResponse()
    }

    func buildShutdown(
        _ request: BuildShutdownRequest,
        _ id: RequestID
    ) throws -> VoidResponse {
        didAskToShutdown = true
        return VoidResponse()
    }

    func onBuildExit(_ notification: OnBuildExitNotification) throws {
        logger.info("Received onBuildExit notification")
        exit(didAskToShutdown ? 0 : 1)
    }

    func workspaceBuildTargets(
        _ request: WorkspaceBuildTargetsRequest,
        _ id: RequestID
    ) throws -> WorkspaceBuildTargetsResponse {
        let taskId = TaskId(id: "buildTargets-\(id.description)")
        taskLogger.startWorkTask(
            id: taskId,
            title: "Indexing: Processing build graph"
        )
        do {
            let result = try workspaceBuildTargetsHandler.handle(
                request: request,
                id: id,
            )
            taskLogger.finishTask(id: taskId, status: .ok)
            return result
        } catch {
            taskLogger.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func buildTargetSources(
        _ request: BuildTargetSourcesRequest,
        _ id: RequestID
    ) throws -> BuildTargetSourcesResponse {
        return try buildTargetSourcesHandler.handle(
            request: request,
            srcsMap: workspaceBuildTargetsHandler.targetsToSrcsMap,
        )
    }

    func textDocumentSourceKitOptions(
        _ request: TextDocumentSourceKitOptionsRequest,
        _ id: RequestID
    ) throws -> TextDocumentSourceKitOptionsResponse? {
        let taskId = TaskId(id: "getSKOptions-\(id.description)")
        taskLogger.startWorkTask(
            id: taskId,
            title: "Indexing: Getting compiler arguments"
        )
        do {
            let result = try textDocumentSourceKitOptionsHandler.handle(
                request: request,
                id: id,
                targetsToBazelMap: workspaceBuildTargetsHandler.targetsToBazelMap,
            )
            taskLogger.finishTask(id: taskId, status: .ok)
            return result
        } catch {
            taskLogger.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func prepareTarget(
        _ request: BuildTargetPrepareRequest,
        _ id: RequestID
    ) throws -> VoidResponse {
        let taskId = TaskId(id: "buildPrepare-\(id.description)")
        taskLogger.startWorkTask(id: taskId, title: "Indexing: Building targets")
        do {
            try prepareTargetHandler.handle(
                request: request,
                id: id,
                targetsToBazelMap: workspaceBuildTargetsHandler.targetsToBazelMap,
            )
            taskLogger.finishTask(id: taskId, status: .ok)
            return VoidResponse()
        } catch {
            taskLogger.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws {
        // FIXME: This only deals with changes, not deletions or creations
        // For those, we need to invalidate the compilation options cache too
        // and probably also re-compile the app
        let changes = notification.changes
            .filter { $0.type == .changed }
            .map { $0.uri }
        var affectedTargets: Set<URI> = []
        for change in changes {
            let targetsForSrc = workspaceBuildTargetsHandler.srcToTargetsMap[change] ?? []
            targetsForSrc.forEach { affectedTargets.insert($0) }
        }
        let response = OnBuildTargetDidChangeNotification(
            changes: affectedTargets.map {
                BuildTargetEvent(
                    target: BuildTargetIdentifier(uri: $0),
                    kind: .changed,
                    dataKind: nil,
                    data: nil
                )
            }
        )
        connection.send(response)
    }

    func cancelRequest(_ notification: CancelRequestNotification) throws {
        // FIXME: implement
    }
}
