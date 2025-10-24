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
    /// Tests that BazelQueryParser correctly processes protobuf query results.
    /// The test uses real protobuf data from streamdeps.pb to ensure the parser handles
    @Test("With given ServerConfig, ensure target parser output is correct")
    func testBazelQueryParser() throws {
        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld:HelloWorld"],
            indexFlags: [],
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

        let runner = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runner)
        let toolchainPath = "/path/to/toolchain"
        let command =
            "bazel --output_base=/path/to/output/base query \'let topLevelTargets = kind(\"ios_application|ios_unit_test\", set(//HelloWorld:HelloWorld)) in   $topLevelTargets   union   kind(\"objc_library|source file|swift_library\", deps($topLevelTargets))\' --notool_deps --noimplicit_deps --output streamed_proto"

        let topLevelRuleKinds: Set<String> = ["ios_application", "ios_unit_test"]
        let dependencyKinds: Set<String> = ["objc_library", "source file", "swift_library"]

        runner.setResponse(for: command, cwd: rootUri, response: mockProtobuf)

        let targets = try querier.queryTargets(
            config: initializedConfig,
            topLevelRuleKinds: topLevelRuleKinds,
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
}
