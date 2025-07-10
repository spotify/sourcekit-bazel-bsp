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
import LanguageServerProtocolJSONRPC

final class BSPServer {

    let baseConfig: BaseServerConfig
    let connection: JSONRPCConnection

    init(
        baseConfig: BaseServerConfig,
        connection: JSONRPCConnection
    ) {
        self.baseConfig = baseConfig
        self.connection = connection
    }

    func run() throws {
        logger.info("Starting bazel bsp")
        connection.start(
            receiveHandler: BSPServerMessageHandlerImpl(
                baseConfig: baseConfig,
                connection: connection
            ),
            closeHandler: {
                // Use _Exit to avoid running static destructors due to https://github.com/swiftlang/swift/issues/55112.
                // (Copied from sourcekit-lsp)
                _Exit(0)
            }
        )

        // Park the main function by sleeping for 10 years.
        // All request handling is done on other threads and sourcekit-bazel-bsp exits by calling `_Exit` when it receives a
        // shutdown notification.
        // (Copied from sourcekit-lsp)
        while true {
            sleep(60 * 60 * 24 * 365 * 10)
        }
    }
}
