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

/// Handles the `buildTarget/prepare` request.
///
/// Builds the provided list of targets upon request.
final class PrepareHandler {
    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let commandRunner: CommandRunner
    private weak var connection: LSPConnection?

    // Prevent redundant builds of the same targets
    // FIXME: Need to understand how exactly this request is dispatched from sourcekit-lsp, as
    // we see for example multiple build requests for the same target. So we have this
    // for now just to make sure the example project works.
    private var didRun = false

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

    func prepareTarget(_: BuildTargetPrepareRequest, _ id: RequestID) throws -> VoidResponse {
        guard !didRun else {
            logger.info("Build already completed, skipping redundant build")
            return VoidResponse()
        }

        let taskId = TaskId(id: "buildPrepare-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "Indexing: Building targets")
        do {
            // FIXME: See same FIXME on Serve.swift.
            // What we should pass here is the list of individual targets received in the request,
            // but it's not clear how to do that correctly. ios_applications apply special transitions
            // and these are lost if you build the libs directly. We need those transitions here too.
            try build(bazelLabels: initializedConfig.baseConfig.targets)
            connection?.finishTask(id: taskId, status: .ok)
            didRun = true
            return VoidResponse()
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func prepare(bspURIs: [URI]) throws {
        let labelsToBuild = try bspURIs.map { try targetStore.bazelTargetLabel(forBSPURI: $0) }
        try build(bazelLabels: labelsToBuild)
    }

    func build(bazelLabels labelsToBuild: [String]) throws {
        logger.info("Will build \(labelsToBuild.count) targets")
        logger.info("Target to build: \(labelsToBuild)")

        // Build the provided targets, on our special output base and taking into account special index flags.
        _ = try commandRunner.bazelIndexAction(
            initializedConfig: initializedConfig,
            cmd: "build \(labelsToBuild.joined(separator: " "))"
        )

        logger.info("Finished building targets!")
    }

    func invalidateBuildCache() {
        didRun = false
    }
}
