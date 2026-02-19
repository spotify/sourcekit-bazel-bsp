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

import BazelProtobufBindings
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Testing

@testable import SourceKitBazelBSP

@Suite
struct PrepareHandlerTests {

    static func makeHandler() -> (PrepareHandler, CommandRunnerFake, BaseServerConfig, String) {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()

        let baseConfig = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld", "//HelloWorld2"],
            indexFlags: ["--config=index"],
            filesToWatch: nil
        )

        let initializedConfig = InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: "/path/to/project",
            workspaceName: "_main",
            outputBase: "/tmp/output_base",
            outputPath: "/tmp/output_path",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100",
            devToolchainPath: "/a/b/XcodeDefault.xctoolchain/",
            executionRoot: "/tmp/output_path/execroot/_main",
            sdkRootPaths: ["iphonesimulator": "bar"]
        )

        return (
            PrepareHandler(
                initializedConfig: initializedConfig,
                targetStore: BazelTargetStoreImpl(initializedConfig: initializedConfig),
                commandRunner: commandRunner,
                connection: connection
            ), commandRunner, baseConfig, initializedConfig.rootUri
        )
    }

    @Test
    func buildExecutesCorrectBazelCommand() throws {
        let (handler, commandRunner, _, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld --foo --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, cwd: rootUri, response: "")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: [["//HelloWorld:HelloWorld"]], extraArgs: [["--foo"]], id: RequestID.number(1)) {
            error in
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
        let (handler, commandRunner, baseConfig, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld //HelloWorld2:HelloWorld2 --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, response: "Build completed")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: [baseConfig.targets], extraArgs: [[]], id: RequestID.number(1)) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    func buildWithMutipleInvocations() throws {
        let (handler, commandRunner, _, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld --foo --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index && bazel --output_base=/tmp/output_base --preemptible build //HelloWorld2:HelloWorld2 --bar --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, response: "Build completed")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(
            bazelLabels: [["//HelloWorld:HelloWorld"], ["//HelloWorld2:HelloWorld2"]],
            extraArgs: [["--foo"], ["--bar"]],
            id: RequestID.number(1)
        ) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    @Test
    func sanitizesLabelCorrectly() {
        #expect(PrepareHandler.sanitizeLabel("//path/to/library:LibraryName") == "aspect_path_to_library_LibraryName")
        #expect(PrepareHandler.sanitizeLabel("//path/to/library") == "aspect_path_to_library")
        #expect(PrepareHandler.sanitizeLabel("//path-with-dashes:Target.Name") == "aspect_path_with_dashes_Target_Name")
    }
}
