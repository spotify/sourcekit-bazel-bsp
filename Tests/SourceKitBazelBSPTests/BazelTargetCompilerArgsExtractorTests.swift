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
import LanguageServerProtocolTransport
import Testing

@testable import SourceKitBazelBSP

@Suite
struct BazelTargetCompilerArgsExtractorTests {

    let aqueryResult: ProcessedAqueryResult
    let helloWorldConfig: BazelTargetConfigurationInfo

    init() throws {
        let aqueryResult = try BazelTargetQuerierParserImpl().processAquery(
            from: exampleAqueryOutput,
            topLevelTargets: [("//HelloWorld:HelloWorld", .iosApplication)]
        )
        self.helloWorldConfig = try #require(aqueryResult.topLevelLabelToConfigMap["//HelloWorld:HelloWorld"])
        self.aqueryResult = aqueryResult
    }

    private static func makeMockExtractor(
        compileTopLevel: Bool = false
    ) -> BazelTargetCompilerArgsExtractor {
        let mockRootUri = "/Users/user/Documents/demo-ios-project"
        let mockDevDir = "/Applications/Xcode.app/Contents/Developer"
        let mockOutputPath = "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out"
        let mockExecRoot = "/private/var/tmp/_bazel_user/hash123/execroot/__main__"
        let mockOutputBase = "/private/var/tmp/_bazel_user/hash123"
        let mockDevToolchainPath = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let iosSimSdk =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        let mockSdkRootPaths = [
            "iphonesimulator": iosSimSdk
        ]
        let mockXcodeVersion = "17B100"
        let config = InitializedServerConfig(
            baseConfig: BaseServerConfig(
                bazelWrapper: "bazel",
                targets: ["//HelloWorld"],
                indexFlags: [],
                filesToWatch: nil,
                compileTopLevel: compileTopLevel
            ),
            rootUri: mockRootUri,
            workspaceName: "_main",
            outputBase: mockOutputBase,
            outputPath: mockOutputPath,
            devDir: mockDevDir,
            xcodeVersion: mockXcodeVersion,
            devToolchainPath: mockDevToolchainPath,
            executionRoot: mockExecRoot,
            sdkRootPaths: mockSdkRootPaths
        )
        let extractor = BazelTargetCompilerArgsExtractor(
            config: config
        )
        return extractor
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldSwiftExample() throws {
        let extractor = Self.makeMockExtractor()
        let result = try extractor.extractCompilerArgs(
            fromAquery: aqueryResult,
            forTarget: BazelTargetPlatformInfo(
                label: "//HelloWorld:HelloWorldLib",
                topLevelParentLabel: "//HelloWorld:HelloWorld",
                topLevelParentConfig: helloWorldConfig
            ),
            withStrategy: .swiftModule,
        )
        #expect(result == expectedSwiftResult)
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldObjCExample() throws {
        let extractor = Self.makeMockExtractor()
        let result = try extractor.extractCompilerArgs(
            fromAquery: aqueryResult,
            forTarget: BazelTargetPlatformInfo(
                label: "//HelloWorld:TodoObjCSupport",
                topLevelParentLabel: "//HelloWorld:HelloWorld",
                topLevelParentConfig: helloWorldConfig
            ),
            withStrategy: .cImpl("HelloWorld/TodoObjCSupport/Sources/SKObjCUtils.m", "objective-c"),
        )
        #expect(result == expectedObjCResult)
    }

    @Test
    func missingObjCFile() throws {
        let extractor = Self.makeMockExtractor()
        let error = #expect(throws: BazelTargetCompilerArgsExtractorError.self) {
            try extractor.extractCompilerArgs(
                fromAquery: aqueryResult,
                forTarget: BazelTargetPlatformInfo(
                    label: "//HelloWorld:TodoObjCSupport",
                    topLevelParentLabel: "//HelloWorld:HelloWorld",
                    topLevelParentConfig: helloWorldConfig
                ),
                withStrategy: .cImpl("HelloWorld/TodoObjCSupport/Sources/SomethingElse.m", "objective-c"),
            )
        }
        #expect(
            error?.localizedDescription
                == "No relevant target actions found for HelloWorld/TodoObjCSupport/Sources/SomethingElse.m (//HelloWorld:TodoObjCSupport). This is unexpected."
        )
    }

    @Test
    func ignoresObjCHeaders() throws {
        let extractor = Self.makeMockExtractor()
        let result = try extractor.extractCompilerArgs(
            fromAquery: aqueryResult,
            forTarget: BazelTargetPlatformInfo(
                label: "//HelloWorld:TodoObjCSupport",
                topLevelParentLabel: "//HelloWorld:HelloWorld",
                topLevelParentConfig: helloWorldConfig
            ),
            withStrategy: .cHeader,
        )
        #expect(result == [])
    }

    @Test
    func objCFilesRelativizeLocalPaths() throws {
        let extractor = Self.makeMockExtractor()

        // Local files (inside rootUri) should have the local prefix stripped
        let strategy = try extractor.getParsingStrategy(
            for: URI(
                filePath: "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/File.m",
                isDirectory: false
            ),
            language: .objective_c,
            targetUri: URI(
                filePath: "/target",
                isDirectory: false
            )
        )

        guard case .cImpl(let path, let language) = strategy else {
            Issue.record("Expected cImpl strategy but got \(strategy)")
            return
        }
        #expect(path == "HelloWorld/TodoObjCSupport/Sources/File.m")
        #expect(language == "objective-c")
    }

    @Test
    func objCFilesRelativizeExternalPaths() throws {
        let extractor = Self.makeMockExtractor()

        // External files (inside outputBase) should have the external prefix stripped
        let strategy = try extractor.getParsingStrategy(
            for: URI(
                filePath: "/private/var/tmp/_bazel_user/hash123/external/some_lib/Sources/File.m",
                isDirectory: false
            ),
            language: .objective_c,
            targetUri: URI(
                filePath: "/target",
                isDirectory: false
            )
        )

        guard case .cImpl(let path, let language) = strategy else {
            Issue.record("Expected cImpl strategy but got \(strategy)")
            return
        }
        #expect(path == "external/some_lib/Sources/File.m")
        #expect(language == "objective-c")
    }

    @Test
    func objCFilesHandleUnknownPaths() throws {
        let extractor = Self.makeMockExtractor()

        // Files outside both prefixes should just have file:// stripped
        let strategy = try extractor.getParsingStrategy(
            for: URI(
                filePath: "/random/unknown/path/File.m",
                isDirectory: false
            ),
            language: .objective_c,
            targetUri: URI(
                filePath: "/target",
                isDirectory: false
            )
        )

        guard case .cImpl(let path, let language) = strategy else {
            Issue.record("Expected cImpl strategy but got \(strategy)")
            return
        }
        #expect(path == "/random/unknown/path/File.m")
        #expect(language == "objective-c")
    }

    @Test
    func missingSwiftModule() throws {
        let extractor = Self.makeMockExtractor()
        let error = #expect(throws: BazelTargetCompilerArgsExtractorError.self) {
            try extractor.extractCompilerArgs(
                fromAquery: aqueryResult,
                forTarget: BazelTargetPlatformInfo(
                    label: "//HelloWorld:SomethingElseLib",
                    topLevelParentLabel: "//HelloWorld:HelloWorld",
                    topLevelParentConfig: helloWorldConfig
                ),
                withStrategy: .swiftModule,
            )
        }
        #expect(error?.localizedDescription == "Target //HelloWorld:SomethingElseLib not found in the aquery output.")
    }

    @Test
    func compilingTopLevelKeepsFullConfigName() throws {
        // If the base config has compileTopLevel to true, then the output is the same
        // with the difference that we don't need to sanitize the config name.
        let extractor = Self.makeMockExtractor(
            compileTopLevel: true
        )
        let result = try extractor.extractCompilerArgs(
            fromAquery: aqueryResult,
            forTarget: BazelTargetPlatformInfo(
                label: "//HelloWorld:HelloWorldLib",
                topLevelParentLabel: "//HelloWorld:HelloWorld",
                topLevelParentConfig: helloWorldConfig
            ),
            withStrategy: .swiftModule,
        )
        #expect(
            result
                == expectedSwiftResult.map {
                    $0.replacingOccurrences(
                        of: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
                        with: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f"
                    )
                }
        )
    }
}

// MARK: - Example inputs and expected results

/// Expected result of processing the example input for the Swift target.
let expectedSwiftResult: [String] = [
    "-target",
    "arm64-apple-ios17.0-simulator",
    "-sdk",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-emit-object",
    "-output-file-map",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/HelloWorld/HelloWorldLib.output_file_map.json",
    "-Xfrontend",
    "-no-clang-module-breadcrumbs",
    "-emit-module-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/HelloWorld/HelloWorldLib.swiftmodule",
    "-enforce-exclusivity=checked",
    "-Xfrontend",
    "-const-gather-protocols-file",
    "-Xfrontend",
    "/private/var/tmp/_bazel_user/hash123/external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json",
    "-DDEBUG",
    "-Onone",
    "-whole-module-optimization",
    "-Xfrontend",
    "-internalize-at-link",
    "-Xfrontend",
    "-no-serialize-debugging-options",
    "-enable-testing",
    "-disable-sandbox",
    "-g",
    "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-file-compilation-dir",
    ".",
    "-module-cache-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/_swift_module_cache",
    "-I/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/HelloWorld",
    "-Xcc",
    "-iquote.",
    "-Xcc",
    "-iquote/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin",
    "-Xcc",
    "-fmodule-map-file=/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/module.modulemap",
    "-Xfrontend",
    "-color-diagnostics",
    "-num-threads",
    "12",
    "-module-name",
    "HelloWorldLib",
    "-index-store-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/_global_index_store",
    "-index-ignore-system-modules",
    "-enable-bare-slash-regex",
    "-Xfrontend",
    "-disable-clang-spi",
    "-enable-experimental-feature",
    "AccessLevelOnImport",
    "-parse-as-library",
    "-static",
    "-Xcc",
    "-O0",
    "-Xcc",
    "-DDEBUG=1",
    "-Xcc",
    "-fstack-protector",
    "-Xcc",
    "-fstack-protector-all",
    "-whole-module-optimization",
    "-Xfrontend",
    "-checked-async-objc-bridging=on",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/AddTodoView.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/HelloWorldApp.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoListView.swift",
]

/// Expected result of processing the example input for the Obj-C file.
let expectedObjCResult: [String] = [
    "-x",
    "objective-c",
    "-D_FORTIFY_SOURCE=1",
    "-fstack-protector",
    "-fcolor-diagnostics",
    "-Wall",
    "-Wthread-safety",
    "-Wself-assign",
    "-fno-omit-frame-pointer",
    "-g",
    "-fdebug-prefix-map=/Users/user/Documents/demo-ios-project=.",
    "-fdebug-prefix-map=/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-Werror=incompatible-sysroot",
    "-Wshorten-64-to-32",
    "-Wbool-conversion",
    "-Wconstant-conversion",
    "-Wduplicate-method-match",
    "-Wempty-body",
    "-Wenum-conversion",
    "-Wint-conversion",
    "-Wunreachable-code",
    "-Wmismatched-return-types",
    "-Wundeclared-selector",
    "-Wuninitialized",
    "-Wunused-function",
    "-Wunused-variable",
    "-iquote",
    ".",
    "-iquote",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin",
    "-MD",
    "-MF",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKObjCUtils.d",
    "-DOS_IOS",
    "-fno-autolink",
    "-isysroot",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks",
    "-fobjc-arc",
    "-no-canonical-prefixes",
    "-target",
    "arm64-apple-ios17.0-simulator",
    "-fexceptions",
    "-fasm-blocks",
    "-fobjc-abi-version=2",
    "-fobjc-legacy-dispatch",
    "-O0",
    "-DDEBUG=1",
    "-fstack-protector",
    "-fstack-protector-all",
    "-g",
    "-Wno-builtin-macro-redefined",
    "-D__DATE__=\"redacted\"",
    "-D__TIMESTAMP__=\"redacted\"",
    "-D__TIME__=\"redacted\"",
    "HelloWorld/TodoObjCSupport/Sources/SKObjCUtils.m",
    "-o",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKObjCUtils.o",
    "-index-store-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/_global_index_store",
    "-working-directory",
    "/Users/user/Documents/demo-ios-project",
]
