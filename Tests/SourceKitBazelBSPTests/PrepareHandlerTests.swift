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

import BazelProtobufBindings
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Testing

@testable import SourceKitBazelBSP

@Suite
struct PrepareHandlerTests {

    static func makeHandler() -> (PrepareHandler, CommandRunnerFake, BaseServerConfig, String) {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()

        let baseConfig = BaseServerConfig(
            bazelWrapper: "bazel",
            targets: ["//HelloWorld", "//HelloWorld2"],
            indexFlags: ["--config=index"],
            filesToWatch: nil,
            compileTopLevel: false
        )

        let initializedConfig = InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: "/path/to/project",
            workspaceName: "_main",
            outputBase: "/tmp/output_base",
            outputPath: "/tmp/output_path",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100",
            devToolchainPath: "/a/b/XcodeDefault.xctoolchain/",
            executionRoot: "/tmp/output_path/execroot/_main",
            sdkRootPaths: ["iphonesimulator": "bar"]
        )

        return (
            PrepareHandler(
                initializedConfig: initializedConfig,
                targetStore: BazelTargetStoreImpl(initializedConfig: initializedConfig),
                commandRunner: commandRunner,
                connection: connection
            ), commandRunner, baseConfig, initializedConfig.rootUri
        )
    }

    @Test
    func buildExecutesCorrectBazelCommand() throws {
        let (handler, commandRunner, _, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld --foo --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, cwd: rootUri, response: "")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: [["//HelloWorld:HelloWorld"]], extraArgs: [["--foo"]], id: RequestID.number(1)) {
            error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    func buildWithMultipleTargets() throws {
        let (handler, commandRunner, baseConfig, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld //HelloWorld2:HelloWorld2 --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, response: "Build completed")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(bazelLabels: [baseConfig.targets], extraArgs: [[]], id: RequestID.number(1)) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    func buildWithMutipleInvocations() throws {
        let (handler, commandRunner, _, rootUri) = Self.makeHandler()

        let expectedCommand =
            "bazel --output_base=/tmp/output_base --preemptible build //HelloWorld:HelloWorld --foo --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index && bazel --output_base=/tmp/output_base --preemptible build //HelloWorld2:HelloWorld2 --bar --remote_download_regex=\'.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$\' --config=index"
        commandRunner.setResponse(for: expectedCommand, response: "Build completed")

        let semaphore = DispatchSemaphore(value: 0)
        try handler.build(
            bazelLabels: [["//HelloWorld:HelloWorld"], ["//HelloWorld2:HelloWorld2"]],
            extraArgs: [["--foo"], ["--bar"]],
            id: RequestID.number(1)
        ) { error in
            #expect(error == nil)
            semaphore.signal()
        }

        #expect(semaphore.wait(timeout: .now() + 1) == .success)

        let ranCommands = commandRunner.commands
        #expect(ranCommands.count == 1)
        #expect(ranCommands[0].command == expectedCommand)
        #expect(ranCommands[0].cwd == rootUri)
    }

    func providesCorrectFlagsForiOSTargets() {
        let actualFlags = PrepareHandler.buildArgs(
            minimumOsVersion: "15.0",
            platform: "ios",
            cpuArch: "arm64",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100"
        )
        #expect(
            actualFlags == [
                "--platforms=@build_bazel_apple_support//platforms:ios_arm64",
                "--ios_multi_cpus=arm64",
                "--apple_platform_type=ios",
                "--apple_split_cpu=arm64",
                "--ios_minimum_os=15.0",
                "--cpu=ios_arm64",
                "--minimum_os_version=15.0",
                "--xcode_version=17B100",
                "--repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
                "--repo_env=USE_CLANG_CL=17B100",
                "--repo_env=XCODE_VERSION=17B100",
            ]
        )
    }

    func providesCorrectFlagsForWatchOSTargets() {
        let actualFlags = PrepareHandler.buildArgs(
            minimumOsVersion: "15.0",
            platform: "watchos",
            cpuArch: "x86_64",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100"
        )
        #expect(
            actualFlags == [
                "--platforms=@build_bazel_apple_support//platforms:watchos_x86_64",
                "--watchos_cpus=x86_64",
                "--apple_platform_type=watchos",
                "--apple_split_cpu=x86_64",
                "--watchos_minimum_os=15.0",
                "--cpu=watchos_x86_64",
                "--minimum_os_version=15.0",
                "--xcode_version=17B100",
                "--repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
                "--repo_env=USE_CLANG_CL=17B100",
                "--repo_env=XCODE_VERSION=17B100",
            ]
        )
    }

    func providesCorrectFlagsForMacOSTargets() {
        let actualFlags = PrepareHandler.buildArgs(
            minimumOsVersion: "15.0",
            platform: "darwin",
            cpuArch: "arm64",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100"
        )
        #expect(
            actualFlags == [
                "--platforms=@build_bazel_apple_support//platforms:macos_arm64",
                "--macos_cpus=arm64",
                "--apple_platform_type=macos",
                "--apple_split_cpu=arm64",
                "--macos_minimum_os=15.0",
                "--cpu=darwin_arm64",
                "--minimum_os_version=15.0",
                "--xcode_version=17B100",
                "--repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
                "--repo_env=USE_CLANG_CL=17B100",
                "--repo_env=XCODE_VERSION=17B100",
            ]
        )
    }

    func providesCorrectFlagsForTVOSTargets() {
        let actualFlags = PrepareHandler.buildArgs(
            minimumOsVersion: "15.0",
            platform: "tvos",
            cpuArch: "sim_arm64",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100"
        )
        #expect(
            actualFlags == [
                "--platforms=@build_bazel_apple_support//platforms:tvos_sim_arm64",
                "--tvos_cpus=sim_arm64",
                "--apple_platform_type=tvos",
                "--apple_split_cpu=sim_arm64",
                "--tvos_minimum_os=15.0",
                "--cpu=tvos_sim_arm64",
                "--minimum_os_version=15.0",
                "--xcode_version=17B100",
                "--repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
                "--repo_env=USE_CLANG_CL=17B100",
                "--repo_env=XCODE_VERSION=17B100",
            ]
        )
    }

    func providesCorrectFlagsForVisionOSTargets() {
        let actualFlags = PrepareHandler.buildArgs(
            minimumOsVersion: "15.0",
            platform: "visionos",
            cpuArch: "sim_arm64",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "17B100"
        )
        #expect(
            actualFlags == [
                "--platforms=@build_bazel_apple_support//platforms:visionos_sim_arm64",
                "--visionos_cpus=sim_arm64",
                "--apple_platform_type=visionos",
                "--apple_split_cpu=sim_arm64",
                "--visionos_minimum_os=15.0",
                "--cpu=visionos_sim_arm64",
                "--minimum_os_version=15.0",
                "--xcode_version=17B100",
                "--repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
                "--repo_env=USE_CLANG_CL=17B100",
                "--repo_env=XCODE_VERSION=17B100",
            ]
        )
    }
}
