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
struct TargetSourcesHandlerTests {
    static func makeHandler() -> TargetSourcesHandler {
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
            outputBase: "/tmp/output_base",
            outputPath: "/tmp/output_path",
            devDir: "/Applications/Xcode.app/Contents/Developer",
            devToolchainPath: "/a/b/XcodeDefault.xctoolchain/",
            executionRoot: "/tmp/output_path/execroot/_main",
            sdkRootPaths: ["iphonesimulator": "bar"]
        )

        return TargetSourcesHandler(initializedConfig: initializedConfig, targetStore: BazelTargetStoreFake())
    }

    @Test
    func canComputeCopyDestinations() throws {
        let handler = Self.makeHandler()

        let src = try URI(string: "file:///path/to/project/src/main.swift")
        #expect(
            handler.computeCopyDestinations(for: src) == [
                DocumentURI(filePath: "/tmp/output_path/execroot/_main/src/main.swift", isDirectory: false)
            ]
        )

        let externalSrc = try URI(string: "file:///other_path/to/project/src/main.swift")
        #expect(handler.computeCopyDestinations(for: externalSrc) == nil)
    }
}
