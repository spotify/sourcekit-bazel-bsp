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

/// Base object that forwards BSP messages to a separate queue.
/// This exists simply to make sure we can continue to receive messages
/// as we process them. Otherwise, each request would require its own queue.
/// Messages can also be processed concurrently.
final class AsyncMessageHandler: MessageHandler {

    private let queue = DispatchQueue(
        label: "AsyncMessageHandler",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let messageHandler: MessageHandler

    init(wrapping handler: MessageHandler) {
        self.messageHandler = handler
    }

    func handle<Notification: NotificationType>(_ notification: Notification) {
        queue.async { [weak self] in
            self?.messageHandler.handle(notification)
        }
    }

    func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) {
        queue.async { [weak self] in
            self?.messageHandler.handle(request, id: id, reply: reply)
        }
    }
}
