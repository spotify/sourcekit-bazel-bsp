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

import Foundation
import Testing

@testable import SourceKitBazelBSP

@Suite
struct BazelTargetQuerierTests {

    @Test
    func executesCorrectBazelCommand() throws {
        let runnerMock = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runnerMock)

        let config = BaseServerConfig(
            bazelWrapper: "bazelisk",
            targets: ["//HelloWorld"],
            indexFlags: ["--config=test"],
            buildTestSuffix: "_(PLAT)_skbsp",
            buildTestPlatformPlaceholder: "(PLAT)",
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"

        let initializedConfig = InitializedServerConfig(
            baseConfig: config,
            rootUri: mockRootUri,
            outputBase: "/path/to/output/base",
            outputPath: "/path/to/output/path",
            devDir: "/path/to/dev/dir",
            devToolchainPath: "/path/to/toolchain",
            executionRoot: "/path/to/execution/root",
            sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_application\", set(//HelloWorld)) in   $topLevelTargets   union   kind(\"source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: mockProtobuf)

        let topLevelRuleKinds: Set<String> = ["ios_application"]
        let kinds: Set<String> = ["source file", "swift_library"]
        let result = try querier.queryTargets(
            config: initializedConfig,
            topLevelRuleKinds: topLevelRuleKinds,
            dependencyKinds: kinds
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == mockRootUri)
        #expect(!result.isEmpty)
    }

    @Test
    func queryingMultipleKindsAndTargets() throws {
        let runnerMock = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runnerMock)

        let config = BaseServerConfig(
            bazelWrapper: "bazelisk",
            targets: ["//HelloWorld", "//Tests"],
            indexFlags: ["--config=test"],
            buildTestSuffix: "_(PLAT)_skbsp",
            buildTestPlatformPlaceholder: "(PLAT)",
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"

        let initializedConfig = InitializedServerConfig(
            baseConfig: config,
            rootUri: mockRootUri,
            outputBase: "/path/to/output/base",
            outputPath: "/path/to/output/path",
            devDir: "/path/to/dev/dir",
            devToolchainPath: "/path/to/toolchain",
            executionRoot: "/path/to/execution/root",
            sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_application|ios_unit_test\", set(//HelloWorld //Tests)) in   $topLevelTargets   union   kind(\"objc_library|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: mockProtobuf)

        let topLevelRuleKinds: Set<String> = ["ios_application", "ios_unit_test"]
        let kinds: Set<String> = ["swift_library", "objc_library"]
        let result = try querier.queryTargets(
            config: initializedConfig,
            topLevelRuleKinds: topLevelRuleKinds,
            dependencyKinds: kinds
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == mockRootUri)
        #expect(!result.isEmpty)
    }

    @Test
    func cachesQueryResults() throws {
        let runnerMock = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runnerMock)

        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld"],
            indexFlags: [],
            buildTestSuffix: "_(PLAT)_skbsp",
            buildTestPlatformPlaceholder: "(PLAT)",
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"

        let initializedConfig = InitializedServerConfig(
            baseConfig: config,
            rootUri: mockRootUri,
            outputBase: "/path/to/output/base",
            outputPath: "/path/to/output/path",
            devDir: "/path/to/dev/dir",
            devToolchainPath: "/path/to/toolchain",
            executionRoot: "/path/to/execution/root",
            sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
        )

        func run(topLevelRuleKinds: Set<String>, dependencyKinds: Set<String>) throws {
            _ = try querier.queryTargets(
                config: initializedConfig,
                topLevelRuleKinds: topLevelRuleKinds,
                dependencyKinds: kinds
            )
        }

        var topLevelKinds: Set<String> = ["ios_application"]
        var kinds: Set<String> = ["swift_library"]

        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_application\", set(//HelloWorld)) in   $topLevelTargets   union   kind(\"swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto",
            cwd: mockRootUri,
            response: mockProtobuf
        )
        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_unit_test\", set(//HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto",
            cwd: mockRootUri,
            response: mockProtobuf
        )

        try run(topLevelRuleKinds: topLevelKinds, dependencyKinds: kinds)
        try run(topLevelRuleKinds: topLevelKinds, dependencyKinds: kinds)

        #expect(runnerMock.commands.count == 1)

        // Querying something else then results in a new command
        topLevelKinds = ["ios_unit_test"]
        kinds = ["objc_library"]
        try run(topLevelRuleKinds: topLevelKinds, dependencyKinds: kinds)
        #expect(runnerMock.commands.count == 2)
        try run(topLevelRuleKinds: topLevelKinds, dependencyKinds: kinds)
        #expect(runnerMock.commands.count == 2)

        // But the original call is still cached
        topLevelKinds = ["ios_application"]
        kinds = ["swift_library"]
        try run(topLevelRuleKinds: topLevelKinds, dependencyKinds: kinds)
        #expect(runnerMock.commands.count == 2)
    }

    @Test("With given ServerConfig, ensure query is correct")
    func executeCorrectBazelCommandProto() throws {
        let runner = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runner)
        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld:HelloWorld"],
            indexFlags: [],
            buildTestSuffix: "_(PLAT)_skbsp",
            buildTestPlatformPlaceholder: "(PLAT)",
            filesToWatch: nil
        )

        let rootUri = "/path/to/project"

        let initializedConfig = InitializedServerConfig(
            baseConfig: config,
            rootUri: rootUri,
            outputBase: "/path/to/output/base",
            outputPath: "/path/to/output/path",
            devDir: "/path/to/dev/dir",
            devToolchainPath: "/path/to/toolchain",
            executionRoot: "/path/to/execution/root",
            sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
        )

        let command =
            "bazel --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_application\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library|source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto"
        guard let url = Bundle.module.url(forResource: "streamdeps", withExtension: "pb"),
            let data = try? Data(contentsOf: url)
        else {
            Issue.record("Failed get streamdeps.pb")
            return
        }

        runner.setResponse(for: command, cwd: rootUri, response: data)

        let topLevelRuleKinds: Set<String> = ["ios_application"]
        let dependencyKinds: Set<String> = ["objc_library", "source file", "swift_library"]

        let result = try querier.queryTargets(
            config: initializedConfig,
            topLevelRuleKinds: topLevelRuleKinds,
            dependencyKinds: dependencyKinds
        )

        let rules = result.filter { target in
            target.type == .rule
        }

        let ranCommands = runner.commands

        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == command)
        #expect(ranCommands[0].cwd == rootUri)
        #expect(rules.count == 5)
    }
}

let mockProtobuf: Data = {
    guard let url = Bundle.module.url(forResource: "streamdeps", withExtension: "pb"),
        let data = try? Data(contentsOf: url)
    else {
        fatalError("Failed get streamdeps.pb")
    }
    return data
}()
