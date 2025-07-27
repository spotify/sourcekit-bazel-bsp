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
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"
        let expectedCommand = "bazelisk query \"kind('swift_library', deps(//HelloWorld))\" --output xml"
        runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: mockXml)

        let kinds: Set<String> = ["swift_library"]
        let result = try querier.queryTargets(forConfig: config, rootUri: mockRootUri, kinds: kinds)

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == mockRootUri)
        #expect(result.children?.count == 2)
    }

    @Test
    func queryingMultipleKindsAndTargets() throws {
        let runnerMock = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runnerMock)

        let config = BaseServerConfig(
            bazelWrapper: "bazelisk",
            targets: ["//HelloWorld", "//Tests"],
            indexFlags: ["--config=test"],
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"
        let expectedCommand =
            "bazelisk query \"kind('objc_library|swift_library', deps(//HelloWorld) union deps(//Tests))\" --output xml"
        runnerMock.setResponse(for: expectedCommand, cwd: mockRootUri, response: mockXml)

        let kinds: Set<String> = ["swift_library", "objc_library"]
        let result = try querier.queryTargets(forConfig: config, rootUri: mockRootUri, kinds: kinds)

        let ranCommands = runnerMock.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == mockRootUri)
        #expect(result.children?.count == 2)
    }

    @Test
    func cachesQueryResults() throws {
        let runnerMock = CommandRunnerFake()
        let querier = BazelTargetQuerier(commandRunner: runnerMock)

        let config = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld"],
            indexFlags: [],
            filesToWatch: nil
        )

        let mockRootUri = "/path/to/project"

        func run(_ kinds: Set<String>) throws {
            _ = try querier.queryTargets(forConfig: config, rootUri: mockRootUri, kinds: kinds)
        }

        var kinds: Set<String> = ["swift_library"]

        runnerMock.setResponse(
            for: "bazel query \"kind('swift_library', deps(//HelloWorld))\" --output xml",
            cwd: mockRootUri,
            response: mockXml
        )
        runnerMock.setResponse(
            for: "bazel query \"kind('objc_library', deps(//HelloWorld))\" --output xml",
            cwd: mockRootUri,
            response: mockXml
        )

        try run(kinds)
        try run(kinds)

        #expect(runnerMock.commands.count == 1)

        // Querying something else then results in a new command
        kinds = ["objc_library"]
        try run(kinds)
        #expect(runnerMock.commands.count == 2)
        try run(kinds)
        #expect(runnerMock.commands.count == 2)

        // But the original call is still cached
        kinds = ["swift_library"]
        try run(kinds)
        #expect(runnerMock.commands.count == 2)
    }
}

private let mockXml = """
    <?xml version="1.1" encoding="UTF-8" standalone="no"?>
    <query version="2">
        <rule class="swift_library" name="//HelloWorld:lib1" />
        <rule class="swift_library" name="//HelloWorld:lib2" />
    </query>

    """
