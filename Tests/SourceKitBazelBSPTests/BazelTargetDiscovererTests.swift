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

struct BazelTargetDiscovererTests {
    @Test
    func discoverSingleRuleTypeWithMultipleTargets() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "fakeBazel cquery 'kind(\"ios_application\", ...)' --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/AnotherApp:AnotherApp (abc)\n"
        )

        let targets = try BazelTargetDiscoverer.discoverTargets(
            for: [.iosApplication],
            bazelWrapper: "fakeBazel",
            locations: ["..."],
            commandRunner: commandRunner,
        )

        #expect(targets == ["//Example/AnotherApp:AnotherApp", "//Example/HelloWorld:HelloWorld"])
        #expect(commandRunner.commands.count == 1)
        #expect(commandRunner.commands[0].command == "fakeBazel cquery 'kind(\"ios_application\", ...)' --output label")
    }

    @Test
    func discoverMultipleRuleTypes() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "fakeBazel cquery 'kind(\"ios_application|ios_unit_test\", ...)' --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/HelloWorldTests:HelloWorldTests (abc)\n"
        )

        let targets = try BazelTargetDiscoverer.discoverTargets(
            for: [.iosApplication, .iosUnitTest],
            bazelWrapper: "fakeBazel",
            locations: ["..."],
            commandRunner: commandRunner,
        )

        #expect(targets == ["//Example/HelloWorld:HelloWorld", "//Example/HelloWorldTests:HelloWorldTests"])
        #expect(commandRunner.commands.count == 1)
        #expect(
            commandRunner.commands[0].command
                == "fakeBazel cquery 'kind(\"ios_application|ios_unit_test\", ...)' --output label"
        )
    }

    @Test
    func discoverAtMultipleLocations() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "fakeBazel cquery 'kind(\"ios_application\", //A/... union //B/...)' --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/AnotherApp:AnotherApp (abc)\n"
        )

        let targets = try BazelTargetDiscoverer.discoverTargets(
            for: [.iosApplication],
            bazelWrapper: "fakeBazel",
            locations: ["//A/...", "//B/..."],
            commandRunner: commandRunner,
        )

        #expect(targets == ["//Example/AnotherApp:AnotherApp", "//Example/HelloWorld:HelloWorld"])
        #expect(commandRunner.commands.count == 1)
        #expect(
            commandRunner.commands[0].command
                == "fakeBazel cquery 'kind(\"ios_application\", //A/... union //B/...)' --output label"
        )
    }

    @Test
    func handlesAdditionalFlags() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "fakeBazel cquery 'kind(\"ios_application\", //A/... union //B/...)' --config=test --output label",
            response: "//Example/HelloWorld:HelloWorld\n//Example/AnotherApp:AnotherApp (abc)\n"
        )

        let targets = try BazelTargetDiscoverer.discoverTargets(
            for: [.iosApplication],
            bazelWrapper: "fakeBazel",
            locations: ["//A/...", "//B/..."],
            additionalFlags: ["--config=test"],
            commandRunner: commandRunner,
        )

        #expect(targets == ["//Example/AnotherApp:AnotherApp", "//Example/HelloWorld:HelloWorld"])
        #expect(commandRunner.commands.count == 1)
        #expect(
            commandRunner.commands[0].command
                == "fakeBazel cquery 'kind(\"ios_application\", //A/... union //B/...)' --config=test --output label"
        )
    }

    @Test
    func throwsErrorWhenNoTargetsFound() throws {
        let commandRunner = CommandRunnerFake()
        commandRunner.setResponse(
            for: "fakeBazel cquery 'kind(\"ios_application\", ...)' --output label",
            response: "\n  \n"
        )

        #expect(throws: BazelTargetDiscovererError.noTargetsDiscovered) {
            try BazelTargetDiscoverer.discoverTargets(
                for: [.iosApplication],
                bazelWrapper: "fakeBazel",
                locations: ["..."],
                commandRunner: commandRunner,
            )
        }
    }

    @Test
    func failsIfNoRulesProvided() throws {
        #expect(throws: BazelTargetDiscovererError.noRulesProvided) {
            try BazelTargetDiscoverer.discoverTargets(
                for: [],
                bazelWrapper: "fakeBazel",
                locations: ["..."],
            )
        }
    }

    @Test
    func failsIfNoLocationsProvided() throws {
        #expect(throws: BazelTargetDiscovererError.noLocationsProvided) {
            try BazelTargetDiscoverer.discoverTargets(
                for: [.iosApplication],
                bazelWrapper: "fakeBazel",
                locations: [],
            )
        }
    }
}
