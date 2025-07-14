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

let logger = makeBSPLogger()

/// The higher-level class that bootstraps and manages the BSP server.
package final class SourceKitBazelBSPServer {

    let connection: LSPConnection
    let handler: MessageHandler

    package convenience init(
        baseConfig: BaseServerConfig,
        inputHandle: FileHandle = .standardInput,
        outputHandle: FileHandle = .standardOutput
    ) {
        let connection = JSONRPCConnection(
            name: "sourcekit-lsp",
            protocol: BuildServerProtocol.bspRegistry,
            inFD: inputHandle,
            outFD: outputHandle
        )
        let baseHandler = BSPServerMessageHandlerImpl(
            baseConfig: baseConfig,
            connection: connection
        )
        // FIXME: Will be divided into multiple handlers, just doing one thing at a time
        let requestHandlers = BSPMessageHandler.RequestHandlers(
            initializeBuild: baseHandler.initializeBuild,
            waitForBuildSystemUpdates: baseHandler.waitForBuildSystemUpdates,
            buildTargetPrepare: baseHandler.prepareTarget,
            buildShutdown: baseHandler.buildShutdown,
            workspaceBuildTargets: baseHandler.workspaceBuildTargets,
            buildTargetSources: baseHandler.buildTargetSources,
        )
        let notificationHandlers = BSPMessageHandler.NotificationHandlers(
            cancelRequest: baseHandler.cancelRequest,
            onBuildExit: baseHandler.onBuildExit,
            onBuildInitialized: baseHandler.onBuildInitialized,
            onWatchedFilesDidChange: baseHandler.onWatchedFilesDidChange,
        )
        let handler = BSPMessageHandler(
            requestHandlers: requestHandlers,
            notificationHandlers: notificationHandlers
        )
        self.init(connection: connection, handler: handler)
    }

    package init(
        connection: LSPConnection,
        handler: MessageHandler
    ) {
        self.connection = connection
        self.handler = handler
    }

    /// Launches a connection to sourcekit-lsp and wires it to our  BSP server.
    /// This code never returns; it locks the thread it was called from until
    /// we get a shutdown request from sourcekit-lsp.
    package func run(parkThread: Bool = true) {
        logger.info("Connecting to sourcekit-lsp...")

        connection.start(
            receiveHandler: handler,
            closeHandler: {
                logger.info("Connection closed, exiting.")
                // Use _Exit to avoid running static destructors due to https://github.com/swiftlang/swift/issues/55112.
                // (Copied from sourcekit-lsp)
                _Exit(0)
            }
        )

        // For usage with unit tests, since we don't want to block the thread when using mocks
        guard parkThread else {
            return
        }

        logger.info("Connection established, parking thread.")

        // Park the thread by sleeping for 10 years.
        // All request handling is done on other threads and sourcekit-bazel-bsp exits by calling `_Exit` when it receives a
        // shutdown notification.
        // (Copied from sourcekit-lsp)
        while true {
            sleep(60 * 60 * 24 * 365 * 10)
        }
    }
}
