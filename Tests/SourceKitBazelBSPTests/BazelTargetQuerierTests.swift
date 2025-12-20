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

// @Suite
// struct BazelTargetQuerierTests {

//     // @Test
//     // func executesCorrectBazelCommand() throws {
//     //     let runnerMock = CommandRunnerFake()
//     //     let querier = BazelTargetQuerier(commandRunner: runnerMock)

//     //     let config = BaseServerConfig(
//     //         bazelWrapper: "bazelisk",
//     //         targets: ["//HelloWorld"],
//     //         indexFlags: ["--config=test"],
//     //         filesToWatch: nil,
//     //         compileTopLevel: false
//     //     )

//     //     let mockRootUri = "/path/to/project"

//     //     let initializedConfig = InitializedServerConfig(
//     //         baseConfig: config,
//     //         rootUri: mockRootUri,
//     //         outputBase: "/path/to/output/base",
//     //         outputPath: "/path/to/output/path",
//     //         devDir: "/path/to/dev/dir",
//     //         xcodeVersion: "17B100",
//     //         devToolchainPath: "/path/to/toolchain",
//     //         executionRoot: "/path/to/execution/root",
//     //         sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
//     //     )

//     //     let expectedCommand =
//     //         "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output proto --config=test"
//     //     runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: exampleCqueryOutput)

//     //     let kinds: Set<String> = ["source file", "swift_library"]
//     //     let result = try querier.queryTargets(
//     //         config: initializedConfig,
//     //         dependencyKinds: kinds
//     //     )

//     //     let ranCommands = runnerMock.commands
//     //     #expect(ranCommands.count == 1)
//     //     #expect(ranCommands[0].command == expectedCommand)
//     //     #expect(ranCommands[0].cwd == mockRootUri)
//     //     #expect(result.rules.count > 0)
//     //     #expect(result.srcs.count > 0)
//     // }

//     // @Test
//     // func queryingMultipleKindsAndTargets() throws {
//     //     let runnerMock = CommandRunnerFake()
//     //     let querier = BazelTargetQuerier(commandRunner: runnerMock)

//     //     let config = BaseServerConfig(
//     //         bazelWrapper: "bazelisk",
//     //         targets: ["//HelloWorld", "//Tests"],
//     //         indexFlags: ["--config=test"],
//     //         filesToWatch: nil,
//     //         compileTopLevel: false
//     //     )

//     //     let mockRootUri = "/path/to/project"

//     //     let initializedConfig = InitializedServerConfig(
//     //         baseConfig: config,
//     //         rootUri: mockRootUri,
//     //         outputBase: "/path/to/output/base",
//     //         outputPath: "/path/to/output/path",
//     //         devDir: "/path/to/dev/dir",
//     //         xcodeVersion: "17B100",
//     //         devToolchainPath: "/path/to/toolchain",
//     //         executionRoot: "/path/to/execution/root",
//     //         sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
//     //     )

//     //     let expectedCommand =
//     //         "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld //Tests:Tests)) in   $topLevelTargets   union   kind(\"objc_library|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output proto --config=test"
//     //     runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: exampleCqueryOutput)

//     //     let kinds: Set<String> = ["objc_library", "swift_library"]
//     //     let result = try querier.queryTargets(
//     //         config: initializedConfig,
//     //         dependencyKinds: kinds
//     //     )

//     //     let ranCommands = runnerMock.commands
//     //     #expect(ranCommands.count == 1)
//     //     #expect(ranCommands[0].command == expectedCommand)
//     //     #expect(ranCommands[0].cwd == mockRootUri)
//     //     #expect(result.rules.count > 0)
//     //     #expect(result.srcs.count > 0)
//     // }

//     // @Test
//     // func cachesQueryResults() throws {
//     //     let runnerMock = CommandRunnerFake()
//     //     let querier = BazelTargetQuerier(commandRunner: runnerMock)

//     //     let config = BaseServerConfig(
//     //         bazelWrapper: "bazel",
//     //         targets: ["//HelloWorld"],
//     //         indexFlags: [],
//     //         filesToWatch: nil,
//     //         compileTopLevel: false
//     //     )

//     //     let mockRootUri = "/path/to/project"

//     //     let initializedConfig = InitializedServerConfig(
//     //         baseConfig: config,
//     //         rootUri: mockRootUri,
//     //         outputBase: "/path/to/output/base",
//     //         outputPath: "/path/to/output/path",
//     //         devDir: "/path/to/dev/dir",
//     //         xcodeVersion: "17B100",
//     //         devToolchainPath: "/path/to/toolchain",
//     //         executionRoot: "/path/to/execution/root",
//     //         sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
//     //     )

//     //     func run(dependencyKinds: Set<String>) throws {
//     //         _ = try querier.queryTargets(
//     //             config: initializedConfig,
//     //             dependencyKinds: kinds
//     //         )
//     //     }

//     //     var kinds: Set<String> = ["swift_library"]

//     //     runnerMock.setResponse(
//     //         for:
//     //             "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output proto",
//     //         cwd: mockRootUri,
//     //         response: exampleCqueryOutput
//     //     )
//     //     runnerMock.setResponse(
//     //         for:
//     //             "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output proto",
//     //         cwd: mockRootUri,
//     //         response: exampleCqueryOutput
//     //     )

//     //     try run(dependencyKinds: kinds)
//     //     try run(dependencyKinds: kinds)

//     //     #expect(runnerMock.commands.count == 1)

//     //     // Querying something else then results in a new command
//     //     kinds = ["objc_library"]
//     //     try run(dependencyKinds: kinds)
//     //     #expect(runnerMock.commands.count == 2)
//     //     try run(dependencyKinds: kinds)
//     //     #expect(runnerMock.commands.count == 2)

//     //     // But the original call is still cached
//     //     kinds = ["swift_library"]
//     //     try run(dependencyKinds: kinds)
//     //     #expect(runnerMock.commands.count == 2)
//     // }

//     // func executeCorrectBazelCommandProto() throws {
//     //     let runner = CommandRunnerFake()
//     //     let querier = BazelTargetQuerier(commandRunner: runner)
//     //     let config = BaseServerConfig(
//     //         bazelWrapper: "bazel",
//     //         targets: ["//HelloWorld:HelloWorld"],
//     //         indexFlags: [],
//     //         filesToWatch: nil,
//     //         compileTopLevel: false
//     //     )

//     //     let rootUri = "/path/to/project"

//     //     let initializedConfig = InitializedServerConfig(
//     //         baseConfig: config,
//     //         rootUri: rootUri,
//     //         outputBase: "/path/to/output/base",
//     //         outputPath: "/path/to/output/path",
//     //         devDir: "/path/to/dev/dir",
//     //         xcodeVersion: "17B100",
//     //         devToolchainPath: "/path/to/toolchain",
//     //         executionRoot: "/path/to/execution/root",
//     //         sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
//     //     )

//     //     let command =
//     //         "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library|source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output proto"

//     //     runner.setResponse(for: command, cwd: rootUri, response: exampleCqueryOutput)

//     //     let dependencyKinds: Set<String> = ["objc_library", "source file", "swift_library"]

//     //     let result = try querier.queryTargets(
//     //         config: initializedConfig,
//     //         dependencyKinds: dependencyKinds
//     //     )

//     //     let rules = result.rules

//     //     let ranCommands = runner.commands

//     //     #expect(ranCommands.count == 1)
//     //     #expect(ranCommands[0].command == command)
//     //     #expect(ranCommands[0].cwd == rootUri)
//     //     #expect(rules.count == 5)
//     // }
// }

/// Example aquery output for the example app shipped with this repo.
/// bazelisk aquery "mnemonic('SwiftCompile|ObjcCompile|CppCompile|BundleTreeApp|SignBinary|TestRunner', deps(//HelloWorld:HelloWorldMacTests) union deps(//HelloWorld:HelloWorldTests) union deps(//HelloWorld:HelloWorld) union deps(//HelloWorld:HelloWorldWatchExtension) union deps(//HelloWorld:HelloWorldWatchTests) union deps(//HelloWorld:HelloWorldMacCLIApp) union deps(//HelloWorld:HelloWorldMacApp) union deps(//HelloWorld:HelloWorldWatchApp))" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto --config=index_build > aquery.pb
let exampleAqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "aquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("aquery.pb is not found in Resources folder") }
    return data
}()

// Example cquery output for the example app shipped with this rpeo.
/// bazelisk cquery 'let topLevelTargets = kind("rule", set(//HelloWorld:HelloWorld //HelloWorld:HelloWorldMacApp //HelloWorld:HelloWorldMacCLIApp //HelloWorld:HelloWorldMacTests //HelloWorld:HelloWorldTests //HelloWorld:HelloWorldWatchApp //HelloWorld:HelloWorldWatchExtension //HelloWorld:HelloWorldWatchTests)) in   $topLevelTargets   union   kind("swift_library|objc_library|source file|alias|_ios_internal_unit_test_bundle|_ios_internal_ui_test_bundle|_watchos_internal_unit_test_bundle|_watchos_internal_ui_test_bundle|_macos_internal_unit_test_bundle|_macos_internal_ui_test_bundle|_tvos_internal_unit_test_bundle|_tvos_internal_ui_test_bundle|_visionos_internal_unit_test_bundle|_visionos_internal_ui_test_bundle", deps($topLevelTargets))' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=index_build > cquery.pb
let exampleCqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "cquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("cquery.pb is not found in Resources folder") }
    return data
}()
