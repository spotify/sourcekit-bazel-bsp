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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct PrepareHandlerTests {

    @Test
    func buildExecutesCorrectBazelCommand() throws {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()

        let rootUri = "/path/to/project"
        let baseConfig = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld"],
            indexFlags: ["--config=index"],
            buildTestSuffix: "_skbsp",
            filesToWatch: nil
        )

        let initializedConfig = InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: rootUri,
            outputBase: "/tmp/output_base",
            outputPath: "/tmp/output_path",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            devToolchainPath: "/a/b/XcodeDefault.xctoolchain/"
        )

        let expectedCommand = "bazel --output_base=/tmp/output_base build //HelloWorld --config=index"
        commandRunner.setResponse(for: expectedCommand, cwd: rootUri, response: "")

        let handler = PrepareHandler(
            initializedConfig: initializedConfig,
            targetStore: BazelTargetStoreImpl(initializedConfig: initializedConfig),
            commandRunner: commandRunner,
            connection: connection
        )

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: baseConfig.targets, id: RequestID.number(1)) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    func buildWithMultipleTargets() throws {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()

        let baseConfig = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld", "//HelloWorld2"],
            indexFlags: ["--config=index"],
            buildTestSuffix: "_skbsp",
            filesToWatch: nil
        )

        let initializedConfig = InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: "/path/to/project",
            outputBase: "/tmp/output_base",
            outputPath: "/tmp/output_path",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            devToolchainPath: "/a/b/XcodeDefault.xctoolchain/"
        )

        let expectedCommand = "bazel --output_base=/tmp/output_base build //HelloWorld //HelloWorld2 --config=index"
        commandRunner.setResponse(for: expectedCommand, response: "Build completed")

        let handler = PrepareHandler(
            initializedConfig: initializedConfig,
            targetStore: BazelTargetStoreImpl(initializedConfig: initializedConfig),
            commandRunner: commandRunner,
            connection: connection
        )

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: baseConfig.targets, id: RequestID.number(1)) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == "/path/to/project")
    }
}
