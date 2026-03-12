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
        let url = try #require(
            Bundle.module.url(forResource: "actions", withExtension: "pb"),
            "actions.pb is not found in Resources."
        )
        let data = try Data(contentsOf: url)
        let actionGraph = try BazelProtobufBindings.parseActionGraph(data: data)

        let expected = [
            "//HelloWorld:ExpandedTemplate",
            "//HelloWorld:GeneratedDummy",
            "//HelloWorld:HelloWorldLib",
            "//HelloWorld:TodoModels",
            "//HelloWorld:TodoObjCSupport",
            "//HelloWorld:WatchAppLib",
        ].sorted()

        let actual = actionGraph.targets.map(\.label).sorted()

        #expect(expected == actual)
        #expect(!actionGraph.actions.isEmpty)
    }

    @Test("testing compiler flags from action graph")
    func testBazelProtobuf_compilerArguments() throws {
        let url = try #require(
            Bundle.module.url(forResource: "actions", withExtension: "pb"),
            "actions.pb is not found in Resources."
        )
        let data = try Data(contentsOf: url)
        let actionGraph = try BazelProtobufBindings.parseActionGraph(data: data)

        // Find the target ID for HelloWorldLib
        let helloWorldLibTarget = try #require(
            actionGraph.targets.first(where: { $0.label == "//HelloWorld:HelloWorldLib" })
        )
        let action = try #require(actionGraph.actions.first(where: { $0.targetID == helloWorldLibTarget.id }))

        let actual = action.arguments
        let expected = [
            "bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/external/rules_swift+/tools/worker/worker", "swiftc",
            "-target", "arm64-apple-ios17.0-simulator", "-sdk", "__BAZEL_XCODE_SDKROOT__", "-file-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
            "-Xwrapped-swift=-bazel-target-label=@@//HelloWorld:HelloWorldLib", "-emit-object", "-output-file-map",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld/HelloWorldLib.output_file_map.json",
            "-Xfrontend", "-no-clang-module-breadcrumbs", "-emit-module-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld/HelloWorldLib.swiftmodule",
            "-enforce-exclusivity=checked", "-emit-const-values-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld/HelloWorldLib_objs/HelloWorldLib/Sources/AddTodoView.swift.swiftconstvalues",
            "-Xfrontend", "-const-gather-protocols-file", "-Xfrontend",
            "external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json", "-DDEBUG", "-Onone",
            "-Xfrontend", "-internalize-at-link", "-Xfrontend", "-no-serialize-debugging-options", "-enable-testing",
            "-disable-sandbox", "-g", "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-Xwrapped-swift=-emit-swiftsourceinfo", "-file-compilation-dir", ".",
            "-module-cache-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/_swift_module_cache",
            "-Ibazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld",
            "-Xwrapped-swift=-macro-expansion-dir=bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld/HelloWorldLib.macro-expansions",
            "-Xcc", "-iquote.", "-Xcc",
            "-iquotebazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin", "-Xcc",
            "-fmodule-map-file=HelloWorld/TodoObjCSupport/Sources/module.modulemap", "-Xfrontend",
            "-color-diagnostics", "-enable-batch-mode", "-module-name", "HelloWorldLib", "-index-store-path",
            "bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300/bin/HelloWorld/HelloWorldLib.indexstore",
            "-index-ignore-system-modules", "-enable-bare-slash-regex",
            "-Xfrontend", "-disable-clang-spi", "-enable-experimental-feature", "AccessLevelOnImport",
            "-parse-as-library", "-static", "-Xcc", "-O0", "-Xcc", "-DDEBUG=1", "-Xcc", "-fstack-protector", "-Xcc",
            "-fstack-protector-all", "-Xfrontend", "-checked-async-objc-bridging=on",
            "HelloWorld/HelloWorldLib/Sources/AddTodoView.swift",
            "HelloWorld/HelloWorldLib/Sources/HelloWorldApp.swift",
            "HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift",
            "HelloWorld/HelloWorldLib/Sources/TodoListView.swift",
        ]

        #expect(actual == expected)
    }
}
