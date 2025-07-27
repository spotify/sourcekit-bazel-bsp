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

/// Base object that can handle receiving and replying to BSP requests and notifications.
/// It does not provide any functionality by itself; all handling logic is intended to be registered
/// as `requestHandlers` and `notificationHandlers`.
final class BSPMessageHandler: MessageHandler {

    private final class State {
        var requestHandlers: [String: AnyRequestHandler] = [:]
        var notificationHandlers: [String: AnyNotificationHandler] = [:]
    }

    nonisolated(unsafe) private var state: State = State()

    init() {}

    func register<Request: RequestType>(requestHandler: @escaping BSPRequestHandler<Request>) {
        state.requestHandlers[Request.method] = AnyRequestHandler(handler: requestHandler)
    }

    func register<Notification: NotificationType>(notificationHandler: @escaping BSPNotificationHandler<Notification>) {
        state.notificationHandlers[Notification.method] = AnyNotificationHandler(handler: notificationHandler)
    }

    func handle<Notification: NotificationType>(_ notification: Notification) {
        logger.info("Received notification: \(Notification.method)")
        do {
            let handler = try getHandler(for: notification, state: state)
            try handler(notification)
        } catch { logger.error("Error while handling BSP notification: \(error.localizedDescription)") }
    }

    func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping (LSPResult<Request.Response>) -> Void
    ) {
        logger.info("Received request: \(Request.method)")
        do {
            let handler = try getHandler(for: request, id, reply, state: state)
            let response = try handler(request, id)
            logger.info("Replying to \(Request.method)")
            reply(.success(response))
        } catch {
            logger.error("Error while handling BSP request: \(error.localizedDescription)")
            if let responseError = error as? ResponseError {
                reply(.failure(responseError))
            } else {
                reply(.failure(ResponseError.internalError(error.localizedDescription)))
            }
        }
    }

    private func getHandler<Notification: NotificationType>(
        for notification: Notification,
        state: State
    ) throws -> BSPNotificationHandler<Notification> {
        guard let erasedHandler = state.notificationHandlers[Notification.method] else {
            throw ResponseError.methodNotFound(Notification.method)
        }
        guard let handler = erasedHandler.handler as? BSPNotificationHandler<Notification> else {
            // This should never happen with the current implementation, but let's log it just in case.
            throw ResponseError.internalError("Found notification, but it had the wrong type! (\(Notification.method))")
        }
        return handler
    }

    private func getHandler<Request: RequestType>(
        for request: Request,
        _ id: RequestID,
        _ reply: @escaping (LSPResult<Request.Response>) -> Void,
        state: State
    ) throws -> BSPRequestHandler<Request> {
        guard let erasedHandler = state.requestHandlers[Request.method] else {
            throw ResponseError.methodNotFound(Request.method)
        }
        guard let handler = erasedHandler.handler as? BSPRequestHandler<Request> else {
            // This should never happen with the current implementation, but let's log it just in case.
            throw ResponseError.internalError("Found request, but it had the wrong type! (\(Request.method))")
        }
        return handler
    }
}
