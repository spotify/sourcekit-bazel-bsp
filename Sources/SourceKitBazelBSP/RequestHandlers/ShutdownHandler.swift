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

/// Handles the `build/shutdown` and `onBuildExit` messages.
///
/// According to the BSP spec, the server should first receive the `build/shutdown` request,
/// and then the `onBuildExit` notification. We then exit with different codes depending on
/// whether the LSP followed the spec correctly or not.
final class ShutdownHandler {

    private var didAskToShutdown = false
    private var terminateHandler: ((Int32) -> Void)

    init(terminateHandler: ((Int32) -> Void)? = nil) {
        self.terminateHandler = terminateHandler ?? { code in safeTerminate(code) }
    }

    func buildShutdown(_ request: BuildShutdownRequest, _ id: RequestID) throws -> VoidResponse {
        didAskToShutdown = true
        return VoidResponse()
    }

    func onBuildExit(_ notification: OnBuildExitNotification) throws { terminateHandler(didAskToShutdown ? 0 : 1) }
}

func safeTerminate(_ code: Int32) {
    // Use _Exit to avoid running static destructors due to https://github.com/swiftlang/swift/issues/55112.
    // (Copied from sourcekit-lsp)
    _Exit(code)
}
