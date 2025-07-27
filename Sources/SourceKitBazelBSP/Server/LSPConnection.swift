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

package protocol LSPTaskLogger: AnyObject {
    func startWorkTask(id: TaskId, title: String)
    func finishTask(id: TaskId, status: StatusCode)
}

/// Extends the original sourcekit-lsp `Connection` type to include JSONRPCConnection's start method
/// and task logging utilities.
package protocol LSPConnection: Connection, LSPTaskLogger, AnyObject {
    func start(receiveHandler: MessageHandler, closeHandler: @escaping @Sendable () async -> Void)
}

extension JSONRPCConnection: LSPConnection {
    package func startWorkTask(id: TaskId, title: String) {
        send(TaskStartNotification(taskId: id, data: WorkDoneProgressTask(title: title).encodeToLSPAny()))
    }

    package func finishTask(id: TaskId, status: StatusCode) {
        send(TaskFinishNotification(taskId: id, status: .ok, ))
    }
}
