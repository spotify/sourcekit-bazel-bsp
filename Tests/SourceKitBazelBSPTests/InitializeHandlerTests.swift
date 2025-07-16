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

@Suite struct InitializeHandlerTests {

    @Test
    func makeConfigGathersCorrectInformation() throws {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()
        let baseConfig = BaseServerConfig(
            bazelWrapper: "mybazel",
            targets: ["//HelloWorld"],
            indexFlags: ["--config=index"],
            filesToWatch: nil
        )

        let outputBase = "/_bazel_user/abc123"
        let outputPath = "/_bazel_user/abc123-sourcekit-bazel-bsp/exec"
        let devDir = "/Applications/Xcode.app/Contents/Developer"
        let sdkRoot = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimu.sdk"

        commandRunner.setResponse(for: "mybazel info output_base", response: outputBase)
        commandRunner.setResponse(
            for:
                "mybazel --output_base=/_bazel_user/abc123-sourcekit-bazel-bsp info output_path --config=index",
            response: outputPath
        )
        commandRunner.setResponse(for: "xcode-select --print-path", response: devDir)
        commandRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path", response: sdkRoot)

        let handler = InitializeHandler(
            baseConfig: baseConfig,
            commandRunner: commandRunner,
            connection: connection
        )

        let rootUri = "file:///path/to/project"
        let request = try mockRequest(rootUri)

        let config = try handler.makeInitializedConfig(
            fromRequest: request,
            baseConfig: baseConfig
        )

        #expect(
            config
                == InitializedServerConfig(
                    baseConfig: baseConfig,
                    rootUri: "/path/to/project",
                    outputBase: outputBase + "-sourcekit-bazel-bsp",
                    outputPath: outputPath,
                    devDir: devDir,
                    sdkRoot: sdkRoot
                ))
    }

    @Test
    func makeConfigWithNoIndexFlags() throws {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()
        let baseConfig = BaseServerConfig(
            bazelWrapper: "mybazel",
            targets: ["//HelloWorld"],
            indexFlags: [],
            filesToWatch: nil
        )

        let outputBase = "/_bazel_user/abc123"
        let outputPath = "/_bazel_user/abc123-sourcekit-bazel-bsp/exec"

        commandRunner.setResponse(for: "mybazel info output_base", response: outputBase)
        commandRunner.setResponse(
            for:
                "mybazel --output_base=/_bazel_user/abc123-sourcekit-bazel-bsp info output_path",
            response: outputPath
        )

        let handler = InitializeHandler(
            baseConfig: baseConfig,
            commandRunner: commandRunner,
            connection: connection
        )

        let rootUri = "file:///path/to/project"
        let request = try mockRequest(rootUri)
        let config = try handler.makeInitializedConfig(
            fromRequest: request,
            baseConfig: baseConfig
        )

        // Makes sure the output_path request didn't get any additional flags.
        #expect(config.outputPath == outputPath)
    }

    @Test
    func makeConfigWithMultipleIndexFlags() throws {
        let commandRunner = CommandRunnerFake()
        let connection = LSPConnectionFake()
        let baseConfig = BaseServerConfig(
            bazelWrapper: "mybazel",
            targets: ["//HelloWorld"],
            indexFlags: ["--config=index1", "--config=index2"],
            filesToWatch: nil
        )

        let outputBase = "/_bazel_user/abc123"
        let outputPath = "/_bazel_user/abc123-sourcekit-bazel-bsp/exec"

        commandRunner.setResponse(for: "mybazel info output_base", response: outputBase)
        commandRunner.setResponse(
            for:
                "mybazel --output_base=/_bazel_user/abc123-sourcekit-bazel-bsp info output_path --config=index1 --config=index2",
            response: outputPath
        )

        let handler = InitializeHandler(
            baseConfig: baseConfig,
            commandRunner: commandRunner,
            connection: connection
        )

        let rootUri = "file:///path/to/project"
        let request = try mockRequest(rootUri)
        let config = try handler.makeInitializedConfig(
            fromRequest: request,
            baseConfig: baseConfig
        )

        // Makes sure the output_path request received the additional index flags as expected.
        #expect(config.outputPath == outputPath)
    }

    private func mockRequest(_ rootUri: String) throws -> InitializeBuildRequest {
        InitializeBuildRequest(
            displayName: "test-client",
            version: "1.0.0",
            bspVersion: "2.2.0",
            rootUri: try URI(string: rootUri),
            capabilities: BuildClientCapabilities(languageIds: [.swift])
        )
    }
}
