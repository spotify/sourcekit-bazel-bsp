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
struct BazelTargetParserTests {
    func canParseCqueryResult() throws {
        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld:HelloWorld"],
            indexFlags: [],
            filesToWatch: nil,
            compileTopLevel: false
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

        let runner = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runner)
        let toolchainPath = "/path/to/toolchain"
        let command =
            "bazel --output_base=/path/to/output/base cquery \'let topLevelTargets = kind(\"rule\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library|source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto"

        let dependencyKinds: Set<String> = ["objc_library", "source file", "swift_library"]

        runner.setResponse(for: command, cwd: rootUri, response: exampleCqueryOutput)

        let targets = try querier.queryTargets(
            config: initializedConfig,
            dependencyKinds: dependencyKinds
        )

        let result = try BazelQueryParser.parseTargetsWithProto(
            from: targets,
            rootUri: rootUri,
            toolchainPath: toolchainPath,
        )

        let expected = [
            "file:///path/to/project/HelloWorld___ExpandedTemplate",
            "file:///path/to/project/HelloWorld___GeneratedDummy",
            "file:///path/to/project/HelloWorld___HelloWorldLib",
            "file:///path/to/project/HelloWorld___TodoModels",
            "file:///path/to/project/HelloWorld___TodoObjCSupport",
        ].sorted()

        let actual = result.map(\.0.id.uri.stringValue).sorted()

        #expect(expected == actual)
    }

    @Test
    func canParseTopLevelConfigInfo() throws {
        let aqueryResult = try AqueryResult(data: exampleAqueryOutput)
        var config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorld",
            withType: .iosApplication,
            in: aqueryResult
        )
        #expect(config.configurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f")
        #expect(config.effectiveConfigurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0")
        #expect(config.minimumOsVersion == "17.0")
        #expect(config.platform == "ios")
        #expect(config.cpuArch == "sim_arm64")
        config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorldTests",
            withType: .iosUnitTest,
            in: aqueryResult
        )
        #expect(config.configurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f")
        #expect(config.effectiveConfigurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0")
        #expect(config.minimumOsVersion == "17.0")
        #expect(config.platform == "ios")
        #expect(config.cpuArch == "sim_arm64")
        config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorldWatchApp",
            withType: .watchosApplication,
            in: aqueryResult
        )
        #expect(config.configurationName == "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d")
        #expect(config.effectiveConfigurationName == "watchos_x86_64-dbg-watchos-x86_64-min7.0")
        #expect(config.minimumOsVersion == "7.0")
        #expect(config.platform == "watchos")
        #expect(config.cpuArch == "x86_64")
        config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorldMacApp",
            withType: .macosApplication,
            in: aqueryResult
        )
        #expect(config.configurationName == "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6")
        #expect(config.effectiveConfigurationName == "darwin_arm64-dbg-macos-arm64-min15.0")
        #expect(config.minimumOsVersion == "15.0")
        #expect(config.platform == "darwin")
        #expect(config.cpuArch == "arm64")
        config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorldMacCLIApp",
            withType: .macosCommandLineApplication,
            in: aqueryResult
        )
        #expect(config.configurationName == "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6")
        #expect(config.effectiveConfigurationName == "darwin_arm64-dbg-macos-arm64-min15.0")
        #expect(config.minimumOsVersion == "15.0")
        #expect(config.platform == "darwin")
        #expect(config.cpuArch == "arm64")
        config = try BazelQueryParser.topLevelConfigInfo(
            ofTarget: "//HelloWorld:HelloWorldLib_ios_skbsp",
            withType: .iosBuildTest,
            in: aqueryResult
        )
        #expect(config.configurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f")
        #expect(config.effectiveConfigurationName == "ios_sim_arm64-dbg-ios-sim_arm64-min17.0")
        #expect(config.minimumOsVersion == "17.0")
        #expect(config.platform == "ios")
        #expect(config.cpuArch == "sim_arm64")
    }
}
