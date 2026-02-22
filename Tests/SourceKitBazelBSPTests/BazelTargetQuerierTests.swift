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
struct BazelTargetQuerierTests {

    private static let mockRootUri = "/path/to/project"

    private static let emptyProcessedCqueryResult = ProcessedCqueryResult(
        buildTargets: [],
        topLevelTargets: [],
        bspURIsToBazelLabelsMap: [:],
        bspURIsToSrcsMap: [:],
        srcToBspURIsMap: [:],
        configurationToTopLevelLabelsMap: [:],
        bspUriToParentConfigMap: [:],
        bazelLabelToTestFilesMap: [:]
    )

    private static let emptyProcessedAqueryResult = ProcessedAqueryResult(
        targets: [:],
        actions: [:],
        configurations: [:],
        topLevelConfigMnemonicToInfoMap: [:]
    )

    private static func makeInitializedConfig(
        bazelWrapper: String = "bazelisk",
        targets: [String] = ["//HelloWorld"],
        indexFlags: [String] = ["--config=test"],
        aqueryFlags: [String] = [],
        queryFlags: [String] = [],
        topLevelTargetsToExclude: [String] = [],
        dependencyTargetsToExclude: [String] = []
    ) -> InitializedServerConfig {
        let baseConfig = BaseServerConfig(
            bazelWrapper: bazelWrapper,
            targets: targets,
            indexFlags: indexFlags,
            aqueryFlags: aqueryFlags,
            queryFlags: queryFlags,
            filesToWatch: nil,
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
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld) union deps(//Tests)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
    func cqueriesTestBundlesIfNeeded() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig()

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application|watchos_unit_test\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file|_watchos_internal_unit_test_bundle\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) except set(//HelloWorld:Excluded) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file\", deps($topLevelTargets)))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file\", deps($topLevelTargets)) except set(//Libs/ExcludedLib:ExcludedLib))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
            "bazelisk --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"ios_application\", deps(//HelloWorld)) except set(//HelloWorld:Excluded //HelloWorld:AlsoExcluded) in   $topLevelTargets   union   (kind(\"swift_library|objc_library|cc_library|alias|filegroup|source file\", deps($topLevelTargets)) except set(//Libs/ExcludedLib:ExcludedLib))\' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=test"
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
            "bazelisk --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile', deps(//HelloWorld:HelloWorld))\" --noinclude_artifacts --noinclude_aspects --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleAqueryOutput)

        _ = try querier.aquery(
            topLevelTargets: [("//HelloWorld:HelloWorld", .iosApplication, "abc123")],
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
            "bazelisk --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile|ObjcCompile', deps(//HelloWorld:HelloWorld) union deps(//Tests:Tests))\" --noinclude_artifacts --noinclude_aspects --output proto --config=test"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleAqueryOutput)

        _ = try querier.aquery(
            topLevelTargets: [
                ("//HelloWorld:HelloWorld", .iosApplication, "abc123"),
                ("//Tests:Tests", .iosUnitTest, "def456"),
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
    func aqueryFlagsAreIncludedInCommand() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(
            indexFlags: [],
            aqueryFlags: ["--features=-compiler_param_file"]
        )

        let expectedCommand =
            "bazelisk --output_base=/path/to/output/base aquery \"mnemonic('SwiftCompile', deps(//HelloWorld:HelloWorld))\" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto"
        runnerMock.setResponse(for: expectedCommand, cwd: Self.mockRootUri, response: exampleAqueryOutput)

        _ = try querier.aquery(
            topLevelTargets: [("//HelloWorld:HelloWorld", .iosApplication, "abc123")],
            config: config,
            mnemonics: ["SwiftCompile"]
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
    }
    // MARK: - Cquery Added Files Tests

    @Test
    func cqueryAddedFilesExecutesCorrectBazelCommand() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [])

        let srcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/File.swift")

        // First query: determine valid files
        let expectedQuery =
            "bazelisk --output_base=/path/to/output/base query \"'HelloWorld/Sources/File.swift'\" --keep_going"
        runnerMock.setResponse(
            for: expectedQuery,
            cwd: Self.mockRootUri,
            response: "//HelloWorld:HelloWorld/Sources/File.swift"
        )

        // Second cquery: find owning targets
        let expectedCquery =
            "bazelisk --output_base=/path/to/output/base cquery \"kind('swift_library|objc_library|cc_library|source file', rdeps(//HelloWorld:HelloWorld, '//HelloWorld:HelloWorld/Sources/File.swift'))\" --output=proto"
        runnerMock.setResponse(for: expectedCquery, cwd: Self.mockRootUri, response: exampleCqueryAddedFilesOutput)

        parserMock.mockCqueryAddedFilesResult = ProcessedCqueryAddedFilesResult(
            bspURIsToNewSourceItemsMap: [:],
            newSrcToBspURIsMap: [:]
        )

        _ = try querier.cqueryTargets(
            forAddedSrcs: [srcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 2)
        #expect(ranCommands[0].command == expectedQuery)
        #expect(ranCommands[1].command == expectedCquery)
    }

    @Test
    func cqueryAddedFilesIgnoresExternalFiles() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [])

        // One local file, one external file
        let localSrcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/File.swift")
        let externalSrcUri = try URI(string: "file:///external/repo/Sources/External.swift")

        // First query should only include the local file
        let expectedQuery =
            "bazelisk --output_base=/path/to/output/base query \"'HelloWorld/Sources/File.swift'\" --keep_going"
        runnerMock.setResponse(
            for: expectedQuery,
            cwd: Self.mockRootUri,
            response: "//HelloWorld:HelloWorld/Sources/File.swift"
        )

        let expectedCquery =
            "bazelisk --output_base=/path/to/output/base cquery \"kind('swift_library|objc_library|cc_library|source file', rdeps(//HelloWorld:HelloWorld, '//HelloWorld:HelloWorld/Sources/File.swift'))\" --output=proto"
        runnerMock.setResponse(for: expectedCquery, cwd: Self.mockRootUri, response: exampleCqueryAddedFilesOutput)

        parserMock.mockCqueryAddedFilesResult = ProcessedCqueryAddedFilesResult(
            bspURIsToNewSourceItemsMap: [:],
            newSrcToBspURIsMap: [:]
        )

        _ = try querier.cqueryTargets(
            forAddedSrcs: [localSrcUri, externalSrcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        // The query should only contain the local file, not the external one
        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 2)
        #expect(ranCommands[0].command.contains("HelloWorld/Sources/File.swift"))
        #expect(!ranCommands[0].command.contains("External.swift"))
    }

    @Test
    func cqueryAddedFilesReturnsEarlyIfOnlyExternal() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [])

        // Only external files
        let externalSrcUri = try URI(string: "file:///external/repo/Sources/External.swift")

        let result = try querier.cqueryTargets(
            forAddedSrcs: [externalSrcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        // Should return nil without running any commands
        #expect(result == nil)
        #expect(runnerMock.commands.isEmpty)
    }

    @Test
    func cqueryAddedFilesFirstQueryRespectsQueryFlags() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [], queryFlags: ["--custom_query_flag"])

        let srcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/File.swift")

        // Query should include the custom query flag after --keep_going
        let expectedQuery =
            "bazelisk --output_base=/path/to/output/base query \"'HelloWorld/Sources/File.swift'\" --keep_going --custom_query_flag"
        runnerMock.setResponse(
            for: expectedQuery,
            cwd: Self.mockRootUri,
            response: "//HelloWorld:HelloWorld/Sources/File.swift"
        )

        let expectedCquery =
            "bazelisk --output_base=/path/to/output/base cquery \"kind('swift_library|objc_library|cc_library|source file', rdeps(//HelloWorld:HelloWorld, '//HelloWorld:HelloWorld/Sources/File.swift'))\" --output=proto"
        runnerMock.setResponse(for: expectedCquery, cwd: Self.mockRootUri, response: exampleCqueryAddedFilesOutput)

        parserMock.mockCqueryAddedFilesResult = ProcessedCqueryAddedFilesResult(
            bspURIsToNewSourceItemsMap: [:],
            newSrcToBspURIsMap: [:]
        )

        _ = try querier.cqueryTargets(
            forAddedSrcs: [srcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 2)
        #expect(ranCommands[0].command.contains("--custom_query_flag"))
    }

    @Test
    func cqueryAddedFilesAcceptsError3() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [])

        // Two files: one valid, one invalid (not in Bazel graph)
        let validSrcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/Valid.swift")
        let invalidSrcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/Invalid.swift")

        // First query returns exit code 3 (partial failure) but still outputs the valid file
        let expectedQuery =
            "bazelisk --output_base=/path/to/output/base query \"'HelloWorld/Sources/Valid.swift' + 'HelloWorld/Sources/Invalid.swift'\" --keep_going"
        runnerMock.setResponse(
            for: expectedQuery,
            cwd: Self.mockRootUri,
            response: "//HelloWorld:HelloWorld/Sources/Valid.swift",
            exitCode: 3
        )

        // Second cquery only includes the valid file
        let expectedCquery =
            "bazelisk --output_base=/path/to/output/base cquery \"kind('swift_library|objc_library|cc_library|source file', rdeps(//HelloWorld:HelloWorld, '//HelloWorld:HelloWorld/Sources/Valid.swift'))\" --output=proto"
        runnerMock.setResponse(for: expectedCquery, cwd: Self.mockRootUri, response: exampleCqueryAddedFilesOutput)

        parserMock.mockCqueryAddedFilesResult = ProcessedCqueryAddedFilesResult(
            bspURIsToNewSourceItemsMap: [:],
            newSrcToBspURIsMap: [:]
        )

        let result = try querier.cqueryTargets(
            forAddedSrcs: [validSrcUri, invalidSrcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        // Should succeed despite exit code 3
        #expect(result != nil)
        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 2)
    }

    @Test
    func cqueryAddedFilesReturnsEarlyIfEmptyQueryResult() throws {
        let runnerMock = CommandRunnerFake()
        let parserMock = BazelTargetQuerierParserFake()
        let querier = Self.makeQuerier(runner: runnerMock, parser: parserMock)
        let config = Self.makeInitializedConfig(indexFlags: [])

        let srcUri = try URI(string: "file:///path/to/project/HelloWorld/Sources/NonExistent.swift")

        // First query returns empty (file not in Bazel graph) with exit code 3
        let expectedQuery =
            "bazelisk --output_base=/path/to/output/base query \"'HelloWorld/Sources/NonExistent.swift'\" --keep_going"
        runnerMock.setResponse(
            for: expectedQuery,
            cwd: Self.mockRootUri,
            response: "",
            exitCode: 3
        )

        let result = try querier.cqueryTargets(
            forAddedSrcs: [srcUri],
            inTopLevelTargets: ["//HelloWorld:HelloWorld"],
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            config: config
        )

        // Should return nil without running the second cquery
        #expect(result == nil)
        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
    }
}

/// Example aquery output for the example app shipped with this repo.
/// bazelisk aquery "mnemonic('CppCompile|ObjcCompile|SwiftCompile|BundleTreeApp|SignBinary|TestRunner', deps(//HelloWorld:HelloWorldMacTests) union deps(//HelloWorld:HelloWorldTests) union deps(//HelloWorld:HelloWorldLibBuildTest) union deps(//HelloWorld:HelloWorld) union deps(//HelloWorld:HelloWorldWatchExtension) union deps(//HelloWorld:HelloWorldWatchTests) union deps(//HelloWorld:HelloWorldMacCLIApp) union deps(//HelloWorld:HelloWorldMacApp) union deps(//HelloWorld:HelloWorldE2ETests) union deps(//HelloWorld:HelloWorldWatchApp))" --noinclude_artifacts --noinclude_aspects --features=-compiler_param_file --output proto --config=index_build > ../Tests/SourceKitBazelBSPTests/Resources/aquery.pb
let exampleAqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "aquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("aquery.pb is not found in Resources folder") }
    return data
}()

/// Example cquery output for the example app shipped with this repo.
/// bazelisk cquery 'let topLevelTargets = kind("ios_application|ios_unit_test|macos_application|ios_ui_test|macos_command_line_application|macos_unit_test|watchos_application|watchos_extension|watchos_unit_test", deps(//HelloWorld/...)) in   $topLevelTargets   union   (kind("swift_library|objc_library|cc_library|alias|filegroup|source file|_ios_internal_unit_test_bundle|_ios_internal_ui_test_bundle|_watchos_internal_unit_test_bundle|_watchos_internal_ui_test_bundle|_macos_internal_unit_test_bundle|_macos_internal_ui_test_bundle|_tvos_internal_unit_test_bundle|_tvos_internal_ui_test_bundle|_visionos_internal_unit_test_bundle|_visionos_internal_ui_test_bundle", deps($topLevelTargets)))' --noinclude_aspects --notool_deps --noimplicit_deps --output proto --config=index_build > ../Tests/SourceKitBazelBSPTests/Resources/cquery.pb
let exampleCqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "cquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("cquery.pb is not found in Resources folder") }
    return data
}()

/// Example cquery output for an added file event, for the example app shipped with this repo.
/// bazelisk cquery "kind('swift_library|objc_library|cc_library|source file', rdeps(//HelloWorld:HelloWorldLibBuildTest, '//HelloWorld:HelloWorldLib/Sources/TodoItemRow.swift'))" --output=proto --config=index_build > cquery_added_files.pb
let exampleCqueryAddedFilesOutput: Data = {
    guard let url = Bundle.module.url(forResource: "cquery_added_files", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("cquery_added_files.pb is not found in Resources folder") }
    return data
}()
