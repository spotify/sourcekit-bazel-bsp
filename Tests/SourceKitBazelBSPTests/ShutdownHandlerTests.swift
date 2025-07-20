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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct ShutdownHandlerTests {
    @Test
    func onBuildExitAfterShutdownTerminatesWithZero() throws {
        var terminateCode: Int32?

        let handler = ShutdownHandler { code in terminateCode = code }

        let shutdownRequest = BuildShutdownRequest()
        _ = try handler.buildShutdown(shutdownRequest, RequestID.number(1))

        let exitNotification = OnBuildExitNotification()
        try handler.onBuildExit(exitNotification)

        #expect(terminateCode == 0)
    }

    @Test
    func onBuildExitWithoutShutdownTerminatesWithOne() throws {
        var terminateCode: Int32?

        let handler = ShutdownHandler { code in terminateCode = code }

        let exitNotification = OnBuildExitNotification()
        try handler.onBuildExit(exitNotification)

        #expect(terminateCode == 1)
    }
}
