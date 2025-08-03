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

    @Test("With given ServerConfig, ensure target parser output is correct")
    func testBazelQueryParser() throws {
        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld:HelloWorld"],
            indexFlags: [],
            filesToWatch: nil
        )

        guard let url = Bundle.module.url(forResource: "streamdeps", withExtension: "pb"),
              let data = try? Data(contentsOf: url)
        else {
            Issue.record("Failed get streamdeps.pb")
            return
        }

        let runner = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runner)
        let rootUri = "/path/to/project"
        let toolchainPath = "/path/to/toolchain"
        let command = "bazel query \"kind('source file|objc_library|swift_library', deps(//HelloWorld:HelloWorld))\" --output streamed_proto"
        let kinds = Set<String>(["objc_library", "swift_library"])

        runner.setDataResponse(for: command, cwd: rootUri, response: data)

        let targets = try querier.queryTargetsWithProto(
            forConfig: config,
            rootUri: rootUri,
            kinds: kinds
        )

        let result = try BazelQueryParser.parseTargetsWithProto(
            from: targets,
            supportedRuleTypes: kinds,
            rootUri: rootUri,
            toolchainPath: toolchainPath
        )


        for (target, srcs) in result {
            print("targetID: ", target.id.uri.stringValue)
            print(srcs.map(\.stringValue).joined(separator: "\n"))
        }
        #expect(!result.isEmpty)
    }
}
