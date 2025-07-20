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

@testable import BazelProtobufBindings

@Suite
struct BazelProtobufBindingsTests {
    @Test("parses action graph from aquery protobuf output")
    func testBazelProtobuf_readBinaryData() throws {
        guard let url = Bundle.module.url(forResource: "actions", withExtension: "pb") else {
            Issue.record("actions.pb is not found in Resouces.")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            Issue.record("Fail to read actions.pb at url: \(url.path())")
            return
        }

        guard let actionParser = try? BazelProtobufBindings.new(data: data) else {
            Issue.record("Fail to parse actions.pb")
            return
        }

        let actionGraph = actionParser.actionGraph

        let expected = ["//HelloWorld:HelloWorldLib", "//HelloWorld:TodoObjCSupport", "//HelloWorld:TodoModels"]
            .sorted()

        let actual = actionGraph.targets.map(\.label).sorted()

        #expect(expected == actual)
        #expect(!actionGraph.actions.isEmpty)
    }

    @Test("testing compiler flags from action graph")
    func testBazelProtobuf_compilerArguments() throws {
        guard let url = Bundle.module.url(forResource: "actions", withExtension: "pb") else {
            Issue.record("actions.pb is not found in Resouces.")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            Issue.record("Fail to read actions.pb at url: \(url.path())")
            return
        }

        guard let actionParser = try? BazelProtobufBindings.new(data: data) else {
            Issue.record("Fail to parse actions.pb")
            return
        }

        let actionGraph = actionParser.actionGraph

        // //HelloWorld:TodoModels -> targetID: 1
        guard let action = actionGraph.actions.first(where: { $0.targetID == 1 }) else { return }

        let actual = action.arguments
        let expected = [
            "bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/external/rules_swift+/tools/worker/worker", "swiftc",
            "-target", "arm64-apple-ios17.0-simulator", "-sdk", "__BAZEL_XCODE_SDKROOT__", "-debug-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR", "-file-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
            "-Xwrapped-swift=-bazel-target-label=@@//HelloWorld:TodoModels", "-emit-object", "-output-file-map",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.output_file_map.json",
            "-Xfrontend", "-no-clang-module-breadcrumbs", "-emit-module-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.swiftmodule",
            "-enforce-exclusivity=checked", "-emit-const-values-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels_objs/TodoModels/Sources/TodoItem.swift.swiftconstvalues",
            "-Xfrontend", "-const-gather-protocols-file", "-Xfrontend",
            "external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json", "-DDEBUG", "-Onone",
            "-Xfrontend", "-internalize-at-link", "-Xfrontend", "-no-serialize-debugging-options", "-enable-testing",
            "-disable-sandbox", "-g", "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-Xwrapped-swift=-emit-swiftsourceinfo", "-module-cache-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/_swift_module_cache",
            "-Xwrapped-swift=-macro-expansion-dir=bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.macro-expansions",
            "-Xcc", "-iquote.", "-Xcc",
            "-iquotebazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin", "-Xfrontend",
            "-color-diagnostics", "-enable-batch-mode", "-module-name", "TodoModels", "-file-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR", "-index-store-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.indexstore",
            "-index-ignore-system-modules",
            "-Xwrapped-swift=-global-index-store-import-path=bazel-out/_global_index_store", "-enable-bare-slash-regex",
            "-Xfrontend", "-disable-clang-spi", "-enable-experimental-feature", "AccessLevelOnImport",
            "-parse-as-library", "-static", "-Xcc", "-O0", "-Xcc", "-DDEBUG=1", "-Xcc", "-fstack-protector", "-Xcc",
            "-fstack-protector-all", "HelloWorld/TodoModels/Sources/TodoItem.swift",
            "HelloWorld/TodoModels/Sources/TodoListManager.swift",
        ]

        #expect(actual == expected)
    }
}
