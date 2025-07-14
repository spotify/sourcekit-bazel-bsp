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

/// Base object that can handle receiving and replying to BSP requests and notifications.
/// It does not provide any functionality by itself; all handling logic is intended to be passed
/// to the `requestHandlers` and `notificationHandlers` properties.
final class BSPMessageHandler: MessageHandler {

    // We currently use a single-threaded setup for simplicity,
    // but we can eventually reply asynchronously if we find a need for it.
    private let lock: OSAllocatedUnfairLock<Void> = .init()

    nonisolated(unsafe) let requestHandlers: RequestHandlers
    nonisolated(unsafe) let notificationHandlers: NotificationHandlers

    init(
        requestHandlers: RequestHandlers = .init(),
        notificationHandlers: NotificationHandlers = .init()
    ) {
        self.requestHandlers = requestHandlers
        self.notificationHandlers = notificationHandlers
    }

    func handle<Notification: NotificationType>(_ notification: Notification) {
        lock.lock()
        defer { lock.unlock() }
        let method = Notification.method
        logger.info("Handling notification: \(method, privacy: .public)")
        do {
            switch notification {
            case let notification as CancelRequestNotification:
                try _handle(notification, using: notificationHandlers.cancelRequest)
            case let notification as OnBuildExitNotification:
                try _handle(notification, using: notificationHandlers.onBuildExit)
            case let notification as OnBuildInitializedNotification:
                try _handle(notification, using: notificationHandlers.onBuildInitialized)
            case let notification as OnWatchedFilesDidChangeNotification:
                try _handle(notification, using: notificationHandlers.onWatchedFilesDidChange)
            default:
                logger.error("Unexpected notification: \(method, privacy: .public)")
                throw ResponseError.methodNotFound(type(of: notification).method)
            }
        } catch {
            logger.error("Error while handling BSP notification: \(error.localizedDescription)")
        }
    }

    private func _handle<N: NotificationType>(
        _ notification: N, using handler: BSPNotificationHandler<N>?
    ) throws {
        guard let handler = handler else {
            logger.error("Missing notification handler for: \(N.method, privacy: .public)")
            throw ResponseError.internalError("Missing notification handler for: \(N.method)")
        }
        try handler(notification)
    }

    func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping (LSPResult<Request.Response>) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        let method = Request.method
        let requestType = String(describing: type(of: request))
        // Trick to get past Swift typechecking weirdness.
        // For some reason Swift doesn't understand that the downcasted requests can still fulfill
        // `reply`'s type requirements. sourcekit-lsp uses the same trick under the hood.
        func _handle<R: RequestType>(
            _ request: R, using handler: BSPRequestHandler<R>?
        ) {
            guard let handler = handler else {
                logger.error("Missing request handler for: \(method, privacy: .public)")
                reply(
                    .failure(ResponseError.internalError("Missing request handler for: \(method)")))
                return
            }
            do {
                let response = try handler(request, id) as! Request.Response
                logger.info("Responding to \(method, privacy: .public)")
                reply(.success(response))
            } catch {
                logger.error(
                    "Error while responding to \(method, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                reply(
                    .failure(
                        ResponseError.internalError(
                            "Error while responding to \(method): \(error.localizedDescription)")))
            }
        }
        logger.info(
            "Handling request: \(method, privacy: .public) (\(requestType, privacy: .public))"
        )
        switch request {
        case let request as BuildShutdownRequest:
            _handle(request, using: requestHandlers.buildShutdown)
        case let request as BuildTargetSourcesRequest:
            _handle(request, using: requestHandlers.buildTargetSources)
        case let request as InitializeBuildRequest:
            _handle(request, using: requestHandlers.initializeBuild)
        case let request as TextDocumentSourceKitOptionsRequest:
            _handle(request, using: requestHandlers.textDocumentSourceKitOptions)
        case let request as WorkspaceBuildTargetsRequest:
            _handle(request, using: requestHandlers.workspaceBuildTargets)
        case let request as WorkspaceWaitForBuildSystemUpdatesRequest:
            _handle(request, using: requestHandlers.waitForBuildSystemUpdates)
        case let request as BuildTargetPrepareRequest:
            _handle(request, using: requestHandlers.prepareTarget)
        default:
            logger.error("Unexpected request: \(method, privacy: .public)")
            reply(.failure(ResponseError.methodNotFound(method)))
        }
    }
}
