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
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import Testing

@testable import SourceKitBazelBSP

@Suite("ParseAqueryTests") struct ParseAqueryTests {
    @Test("parses the aquery output")
    func testProcessCompilerArguments_complexRealWorldExample() throws {
        // Given

        let mockSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        let mockDevDir = "/Applications/Xcode.app/Contents/Developer"
        let mockOutputPath = "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out"
        let mockRootUri = "/Users/user/Documents/demo-ios-project"
        let mockOutputBase = "/private/var/tmp/_bazel_user/hash123"

        // Then

        let result = try CompilerArgumentsProcessor.processCompilerArguments(
            rawArguments: exampleInput,
            sdkRoot: mockSdkRoot,
            devDir: mockDevDir,
            outputPath: mockOutputPath,
            rootUri: mockRootUri,
            outputBase: mockOutputBase
        )

        #expect(result == expectedResult)
    }
}

// MARK: - Example input

/// A comprehensive example input that covers all key transformation cases and argument prefixes.
private let exampleInput: [String] = [
    "exec", "bazel-out/darwin_arm64-opt-exec/bin/external/rules_swift~/tools/worker/worker",
    "swiftc",
    "-Xwrapped-swift=-bazel-target-label=//foo:bar",
    "-enable-batch-mode",
    "-index-store-path", "bazel-out/ios_sim_arm64-fastbuild/bin/Example.indexstore",
    "-Xfrontend", "-const-gather-protocols-file",
    "-sdk", "__BAZEL_XCODE_SDKROOT__",
    "-debug-prefix-map", "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
    "-file-prefix-map", "__BAZEL_EXECUTION_ROOT__=/PLACEHOLDER_EXECUTION_ROOT",
    "-emit-module-path", "bazel-out/ios_sim_arm64-fastbuild/bin/Example.swiftmodule",
    "-module-cache-path", "bazel-out/ios_sim_arm64-fastbuild/bin/_swift_module_cache",
    "-Ibazel-out/ios_sim_arm64-fastbuild/bin/external/swift_protobuf",
    "-Ibazel-out/ios_sim_arm64-fastbuild/bin/external/ExampleSDK/Headers",
    "-Xcc",
    "-fmodule-map-file=bazel-out/ios_sim_arm64-fastbuild/bin/external/ExampleSDK/module.modulemap",
    "-Fexternal/ExampleSDK/Example.xcframework/ios-simulator",
    "-Xcc", "-Fexternal/ExampleSDK/Another.xcframework/ios-simulator",
    "-Xcc", "-Iexternal/ExampleSDK/include",
    "-Xcc", "-iquoteexternal/ExampleSDK/Headers",
    "-Xcc", "-isystemexternal/ExampleSDK/SystemHeaders",
    "-Xcc", "-fmodule-map-file=external/ExampleSDK/module.modulemap",
    "-fmodule-map-file=bazel-out/ios_sim_arm64-fastbuild/bin/Generated.modulemap",
    "Source/Example/ExampleFile.swift",
    "bazel-out/ios_sim_arm64-fastbuild/bin/Generated.swift",
    "-target", "arm64-apple-ios16.0-simulator",
    "-DDEBUG", "-Onone",
]

/// Expected result of processing the example input.
private let expectedResult: [String] = [
    "exec",
    "-sdk",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-debug-prefix-map", "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-file-prefix-map", "/Users/user/Documents/demo-ios-project=/PLACEHOLDER_EXECUTION_ROOT",
    "-emit-module-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/Example.swiftmodule",
    "-module-cache-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/_swift_module_cache",
    "-I/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/external/swift_protobuf",
    "-I/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/external/ExampleSDK/Headers",
    "-Xcc",
    "-fmodule-map-file=/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/external/ExampleSDK/module.modulemap",
    "-F/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/Example.xcframework/ios-simulator",
    "-Xcc",
    "-F/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/Another.xcframework/ios-simulator",
    "-Xcc", "-I/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/include",
    "-Xcc", "-iquote/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/Headers",
    "-Xcc", "-isystem/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/SystemHeaders",
    "-Xcc",
    "-fmodule-map-file=/private/var/tmp/_bazel_user/hash123/external/ExampleSDK/module.modulemap",
    "-fmodule-map-file=/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/Generated.modulemap",
    "/Users/user/Documents/demo-ios-project/Source/Example/ExampleFile.swift",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-fastbuild/bin/Generated.swift",
    "-target", "arm64-apple-ios16.0-simulator",
    "-DDEBUG", "-Onone",
]
