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

struct DiscoverTargetsTests {
    @Test("Discovers single rule type with multiple targets")
    func discoverSingleRuleTypeWithMultipleTargets() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "bazel query 'kind(ios_application, ...)' --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/AnotherApp:AnotherApp\n"
        )

        let targets = try discoverTargetsInternal(
            for: [.iosApplication],
            bazelWrapper: "bazel",
            commandRunner: commandRunner
        )

        #expect(targets == ["//Example/HelloWorld:HelloWorld", "//Example/AnotherApp:AnotherApp"])
        #expect(commandRunner.commands.count == 1)
        #expect(commandRunner.commands[0].command == "bazel query 'kind(ios_application, ...)' --output label")
    }

    @Test("Discovers multiple rule types")
    func discoverMultipleRuleTypes() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "bazel query 'kind(ios_application, ...) + kind(ios_unit_test, ...)' --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/HelloWorldTests:HelloWorldTests\n"
        )

        let targets = try discoverTargetsInternal(
            for: [.iosApplication, .iosUnitTest],
            bazelWrapper: "bazel",
            commandRunner: commandRunner
        )

        #expect(targets == ["//Example/HelloWorld:HelloWorld", "//Example/HelloWorldTests:HelloWorldTests"])
        #expect(commandRunner.commands.count == 1)
        #expect(
            commandRunner.commands[0].command
                == "bazel query 'kind(ios_application, ...) + kind(ios_unit_test, ...)' --output label"
        )
    }

    @Test("Throws error when no targets found")
    func throwsErrorWhenNoTargetsFound() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "bazel query 'kind(ios_application, ...)' --output label",
            response: "\n  \n"
        )

        #expect(throws: DiscoverTargetsError.noTargetsDiscovered) {
            try discoverTargetsInternal(
                for: [.iosApplication],
                bazelWrapper: "bazel",
                commandRunner: commandRunner
            )
        }
    }
}
