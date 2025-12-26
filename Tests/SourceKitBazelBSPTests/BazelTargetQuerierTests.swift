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

    private static let mockRootUri = "/path/to/project"

    private static let emptyProcessedCqueryResult = ProcessedCqueryResult(
        buildTargets: [],
        topLevelTargets: [],
        bspURIsToBazelLabelsMap: [:],
        bspURIsToSrcsMap: [:],
        srcToBspURIsMap: [:],
        topLevelLabelToRuleMap: [:],
        configurationToTopLevelLabelsMap: [:],
        bazelLabelToParentConfigMap: [:]
    )

    private static let emptyProcessedAqueryResult = ProcessedAqueryResult(
        targets: [:],
        actions: [:],
        configurations: [:],
        topLevelLabelToConfigMap: [:]
    )

    private static func makeInitializedConfig(
        bazelWrapper: String = "bazelisk",
        targets: [String] = ["//HelloWorld"],
        indexFlags: [String] = ["--config=test"],
        topLevelTargetsToExclude: [String] = [],
        dependencyTargetsToExclude: [String] = []
    ) -> InitializedServerConfig {
        let baseConfig = BaseServerConfig(
            bazelWrapper: bazelWrapper,
            targets: targets,
            indexFlags: indexFlags,
            filesToWatch: nil,
            compileTopLevel: false,
            topLevelTargetsToExclude: topLevelTargetsToExclude,
            dependencyTargetsToExclude: dependencyTargetsToExclude
        )
        return InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: mockRootUri,
            workspaceName: "_main",
            outputBase: "/path/to/output/base",
            outputPath: "/path/to/output/path",
            devDir: "/path/to/dev/dir",
            xcodeVersion: "17B100",
            devToolchainPath: "/path/to/toolchain",
            executionRoot: "/path/to/execution/root",
            sdkRootPaths: ["iphonesimulator": "/path/to/sdk/root"]
        )
    }

    private static func makeQuerier(
        runner: CommandRunnerFake,
        parser: BazelTargetQuerierParserFake
    ) -> BazelTargetQuerier {
        parser.mockCqueryResult = emptyProcessedCqueryResult
        parser.mockAqueryResult = emptyProcessedAqueryResult
        return BazelTargetQuerier(commandRunner: runner, parser: parser)
    }

    // MARK: Cquery Tests

    @Test
    func executesCorrectBazelCommandOnCquery() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig()

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cqueryingMultipleKindsAndTargets() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(targets: ["//HelloWorld", "//Tests"])

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld) union deps(//Tests)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cachesCqueryResults() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(bazelWrapper: "bazel", indexFlags: [])

        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|alias|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto",
            cwd: Self.mockRootUri,
            response: exampleCqueryOutput
        )
        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"objc_library|alias|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto",
            cwd: Self.mockRootUri,
            response: exampleCqueryOutput
        )

        func run(supportedDependencyRuleTypes: [DependencyRuleType]) throws {
            _ = try querier.cqueryTargets(
                config: config,
                supportedDependencyRuleTypes: supportedDependencyRuleTypes,
                supportedTopLevelRuleTypes: [.iosApplication]
            )
        }

        try run(supportedDependencyRuleTypes: [.swiftLibrary])
        try run(supportedDependencyRuleTypes: [.swiftLibrary])
        #expect(runnerMock.commands.count == 1)

        // Querying something else then results in a new command
        try run(supportedDependencyRuleTypes: [.objcLibrary])
        #expect(runnerMock.commands.count == 2)
        try run(supportedDependencyRuleTypes: [.objcLibrary])
        #expect(runnerMock.commands.count == 2)

        // But the original call is still cached
        try run(supportedDependencyRuleTypes: [.swiftLibrary])
        #expect(runnerMock.commands.count == 2)
    }

    @Test
    func cqueriesTestBundlesIfNeeded() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig()

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application|watchos_unit_test\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file|_watchos_internal_unit_test_bundle\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication, .watchosUnitTest]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cqueryExcludesTopLevelTargets() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(
            topLevelTargetsToExclude: ["//HelloWorld:Excluded"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) except set(//HelloWorld:Excluded) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cqueryExcludesDependencyTargets() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(
            dependencyTargetsToExclude: ["//Libs/ExcludedLib:ExcludedLib"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file\", deps($topLevelTargets)) except set(//Libs/ExcludedLib:ExcludedLib))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cqueryExcludesBothTopLevelAndDependencyTargets() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(
            topLevelTargetsToExclude: ["//HelloWorld:Excluded", "//HelloWorld:AlsoExcluded"],
            dependencyTargetsToExclude: ["//Libs/ExcludedLib:ExcludedLib"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) except set(//HelloWorld:Excluded //HelloWorld:AlsoExcluded) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|source file\", deps($topLevelTargets)) except set(//Libs/ExcludedLib:ExcludedLib))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleCqueryOutput)

        _ = try querier.cqueryTargets(
            config: config,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: [.iosApplication]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    // MARK: - Aquery Tests

    @Test
    func executesCorrectBazelCommandOnAquery() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig()

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile', deps(//HelloWorld:HelloWorld))\" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleAqueryOutput)

        _ = try querier.aquery(
            topLevelTargets: [("//HelloWorld:HelloWorld", .iosApplication)],
            config: config,
            mnemonics: ["SwiftCompile"]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func aqueryingMultipleMnemonicsAndTargets() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(targets: ["//HelloWorld", "//Tests"])

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile|ObjcCompile', deps(//HelloWorld:HelloWorld) union deps(//Tests:Tests))\" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleAqueryOutput)

        _ = try querier.aquery(
            topLevelTargets: [
                ("//HelloWorld:HelloWorld", .iosApplication),
                ("//Tests:Tests", .iosUnitTest),
            ],
            config: config,
            mnemonics: ["SwiftCompile", "ObjcCompile"]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == Self.mockRootUri)
    }

    @Test
    func cachesAqueryResults() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(bazelWrapper: "bazel", indexFlags: [])

        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile', deps(//HelloWorld:HelloWorld))\" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto",
            cwd: Self.mockRootUri,
            response: exampleAqueryOutput
        )
        runnerMock.setResponse(
            for:
                "bazel --output_base=/path/to/output/base aquery \"mnemonic('ObjcCompile', deps(//HelloWorld:HelloWorld))\" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto",
            cwd: Self.mockRootUri,
            response: exampleAqueryOutput
        )

        func run(mnemonics: [String]) throws {
            _ = try querier.aquery(
                topLevelTargets: [("//HelloWorld:HelloWorld", .iosApplication)],
                config: config,
                mnemonics: mnemonics
            )
        }

        try run(mnemonics: ["SwiftCompile"])
        try run(mnemonics: ["SwiftCompile"])
        #expect(runnerMock.commands.count == 1)

        // Querying something else then results in a new command
        try run(mnemonics: ["ObjcCompile"])
        #expect(runnerMock.commands.count == 2)
        try run(mnemonics: ["ObjcCompile"])
        #expect(runnerMock.commands.count == 2)

        // But the original call is still cached
        try run(mnemonics: ["SwiftCompile"])
        #expect(runnerMock.commands.count == 2)
    }
}

/// Example aquery output for the example app shipped with this repo.
/// bazelisk aquery "mnemonic('CppCompile|ObjcCompile|SwiftCompile|BundleTreeApp|SignBinary|TestRunner', deps(//HelloWorld:HelloWorldMacTests) union deps(//HelloWorld:HelloWorldTests) union deps(//HelloWorld:HelloWorld) union deps(//HelloWorld:HelloWorldWatchExtension) union deps(//HelloWorld:HelloWorldWatchTests) union deps(//HelloWorld:HelloWorldMacCLIApp) union deps(//HelloWorld:HelloWorldMacApp) union deps(//HelloWorld:HelloWorldWatchApp))" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto --config=index_build > aquery.pb
let exampleAqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "aquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("aquery.pb is not found in Resources folder") }
    return data
}()

// Example cquery output for the example app shipped with this repo.
/// bazelisk cquery 'let topLevelTargets = kind("ios_application|ios_unit_test|macos_application|macos_command_line_application|macos_unit_test|watchos_application|watchos_extension|watchos_unit_test", deps(//HelloWorld:HelloWorld) union deps(//HelloWorld:HelloWorldMacApp) union deps(//HelloWorld:HelloWorldMacCLIApp) union deps(//HelloWorld:HelloWorldMacTests) union deps(//HelloWorld:HelloWorldTests) union deps(//HelloWorld:HelloWorldWatchApp) union deps(//HelloWorld:HelloWorldWatchExtension) union deps(//HelloWorld:HelloWorldWatchTests)) in   $topLevelTargets   union   (kind("swift_library|objc_library|cc_library|alias|source file|_ios_internal_unit_test_bundle|_ios_internal_ui_test_bundle|_watchos_internal_unit_test_bundle|_watchos_internal_ui_test_bundle|_macos_internal_unit_test_bundle|_macos_internal_ui_test_bundle|_tvos_internal_unit_test_bundle|_tvos_internal_ui_test_bundle|_visionos_internal_unit_test_bundle|_visionos_internal_ui_test_bundle", deps($topLevelTargets)))' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=index_build > cquery.pb
let exampleCqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "cquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("cquery.pb is not found in Resources folder") }
    return data
}()
