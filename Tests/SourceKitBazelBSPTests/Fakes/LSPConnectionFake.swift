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
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC

@testable import SourceKitBazelBSP

final class LSPConnectionFake: LSPConnection {

    nonisolated(unsafe) private(set) var startCalled = false
    nonisolated(unsafe) private(set) var startReceivedHandler: MessageHandler?

    func start(receiveHandler: MessageHandler, closeHandler: @escaping @Sendable () async -> Void) {
        startCalled = true
        startReceivedHandler = receiveHandler
    }

    func nextRequestID() -> LanguageServerProtocol.RequestID { unimplemented() }

    func send(_ notification: some NotificationType) { unimplemented() }

    func send<Request>(
        _ request: Request,
        id: LanguageServerProtocol.RequestID,
        reply: @escaping @Sendable (LanguageServerProtocol.LSPResult<Request.Response>) -> Void
    ) where Request: LanguageServerProtocol.RequestType { unimplemented() }

    func startWorkTask(id: TaskId, title: String) {
        // no-op
    }

    func finishTask(id: TaskId, status: StatusCode) {
        // no-op
    }
}
