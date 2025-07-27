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
import LanguageServerProtocolJSONRPC
import Testing

@testable import SourceKitBazelBSP

@Suite
struct BazelTargetCompilerArgsExtractorTests {
    private static func makeMockExtractor() -> (BazelTargetCompilerArgsExtractor, CommandRunnerFake) {
        let mockRunner = CommandRunnerFake()
        let mockRootUri = "/Users/user/Documents/demo-ios-project"
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', deps(//HelloWorld))\" --noinclude_artifacts"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryOutput)
        let mockSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        let mockDevDir = "/Applications/Xcode.app/Contents/Developer"
        let mockOutputPath = "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out"
        let mockOutputBase = "/private/var/tmp/_bazel_user/hash123"
        let mockDevToolchainPath = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let config = InitializedServerConfig(
            baseConfig: BaseServerConfig(
                bazelWrapper: "bazel",
                targets: ["//HelloWorld"],
                indexFlags: [],
                filesToWatch: nil
            ),
            rootUri: mockRootUri,
            outputBase: mockOutputBase,
            outputPath: mockOutputPath,
            devDir: mockDevDir,
            sdkRoot: mockSdkRoot,
            devToolchainPath: mockDevToolchainPath
        )
        let extractor = BazelTargetCompilerArgsExtractor(
            aquerier: BazelTargetAquerier(commandRunner: mockRunner),
            config: config
        )
        return (extractor, mockRunner)
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldSwiftExample() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let result = try #require(
            try extractor.compilerArgs(
                forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
                inTarget: "//HelloWorld:HelloWorldLib",
                language: .swift,
            )
        )
        #expect(result == expectedSwiftResult)
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldObjCExample() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let result = try #require(
            try extractor.compilerArgs(
                forDoc: URI(
                    filePath:
                        "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m",
                    isDirectory: false
                ),
                inTarget: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
            )
        )
        #expect(result == expectedObjCResult)
    }

    @Test
    func ignoresObjCHeaders() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let result = try extractor.compilerArgs(
            forDoc: URI(
                filePath:
                    "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.h",
                isDirectory: false
            ),
            inTarget: "//HelloWorld:TodoObjCSupport",
            language: .objective_c,
        )
        #expect(result == nil)
    }

    @Test
    func missingObjCFileReturnsNil() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let result = try extractor.compilerArgs(
            forDoc: URI(
                filePath: "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m",
                isDirectory: false
            ),
            inTarget: "//HelloWorld:TodoObjCSupport",
            language: .objective_c,
        )
        #expect(result == nil)
    }

    @Test
    func objCFilesRequireFullPath() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let error = #expect(throws: BazelTargetCompilerArgsExtractorError.self) {
            try extractor.compilerArgs(
                forDoc: URI(
                    filePath: "/random/wrong/prefix/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m",
                    isDirectory: false
                ),
                inTarget: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
            )
        }
        #expect(
            error?.localizedDescription
                == "Unexpected non-Swift URI missing root URI prefix: file:///random/wrong/prefix/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m"
        )
    }

    @Test
    func missingSwiftModuleReturnsNil() throws {
        let (extractor, _) = Self.makeMockExtractor()

        let result = try extractor.compilerArgs(
            forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
            inTarget: "//HelloWorld:SomethingElseLib",
            language: .swift,
        )
        #expect(result == nil)
    }

    @Test
    func cachesAqueryOutput() throws {
        let (extractor, runner) = Self.makeMockExtractor()

        func run(_ lib: String) {
            _ = try? extractor.compilerArgs(
                forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
                inTarget: lib,
                language: .swift,
            )
        }

        #expect(runner.commands.count == 0)
        run("//HelloWorld:HelloWorldLib")
        #expect(runner.commands.count == 1)
        run("//HelloWorld:SomethingElseLib")
        #expect(runner.commands.count == 1)
    }

    @Test
    func cachesCompilerArgs() throws {
        let (extractor, runner) = Self.makeMockExtractor()

        func run(_ lib: String) -> [String]? {
            return try? extractor.compilerArgs(
                forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
                inTarget: lib,
                language: .swift,
            )
        }

        let result1 = try #require(run("//HelloWorld:HelloWorldLib"))

        // Remove the mock aquery responses to indicate that we skipped that section of the logic entirely
        runner.reset()

        let result2 = try #require(run("//HelloWorld:HelloWorldLib"))
        #expect(result1 == result2)
    }
}

// MARK: - Example inputs and expected results

/// Example aquery output for the example app shipped with this repo.
/// Important: The \s from the output have to be escaped, so careful when updating it.
private let exampleAqueryOutput: String = """
    action 'Compiling Swift module //HelloWorld:HelloWorldLib'
      Mnemonic: SwiftCompile
      Target: //HelloWorld:HelloWorldLib
      Configuration: ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f
      Execution platform: @@platforms//host:host
      ActionKey: d6d42aa52bdb00af8090457cfff08895b3d8db7c903b535bd853423ff09579cd
      Environment: [APPLE_SDK_PLATFORM=iPhoneSimulator, APPLE_SDK_VERSION_OVERRIDE=18.4, XCODE_VERSION_OVERRIDE=16.3.0.16E140]
      Command Line: (exec bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/external/rules_swift+/tools/worker/worker \\
        swiftc \\
        -target \\
        arm64-apple-ios17.0-simulator \\
        -sdk \\
        __BAZEL_XCODE_SDKROOT__ \\
        -debug-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR' \\
        -file-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR' \\
        '-Xwrapped-swift=-bazel-target-label=@@//HelloWorld:HelloWorldLib' \\
        -emit-object \\
        -output-file-map \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.output_file_map.json \\
        -Xfrontend \\
        -no-clang-module-breadcrumbs \\
        -emit-module-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.swiftmodule \\
        '-enforce-exclusivity=checked' \\
        -emit-const-values-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib_objs/HelloWorldLib/Sources/AddTodoView.swift.swiftconstvalues \\
        -Xfrontend \\
        -const-gather-protocols-file \\
        -Xfrontend \\
        external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json \\
        -DDEBUG \\
        -Onone \\
        -Xfrontend \\
        -internalize-at-link \\
        -Xfrontend \\
        -no-serialize-debugging-options \\
        -enable-testing \\
        -disable-sandbox \\
        -g \\
        '-Xwrapped-swift=-file-prefix-pwd-is-dot' \\
        '-Xwrapped-swift=-emit-swiftsourceinfo' \\
        -module-cache-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/_swift_module_cache \\
        -Ibazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld \\
        '-Xwrapped-swift=-macro-expansion-dir=bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.macro-expansions' \\
        -Xcc \\
        -iquote. \\
        -Xcc \\
        -iquotebazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin \\
        -Xcc \\
        '-fmodule-map-file=HelloWorld/TodoObjCSupport/Sources/module.modulemap' \\
        -Xfrontend \\
        -color-diagnostics \\
        -enable-batch-mode \\
        -module-name \\
        HelloWorldLib \\
        -file-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR' \\
        -index-store-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.indexstore \\
        -index-ignore-system-modules \\
        '-Xwrapped-swift=-global-index-store-import-path=bazel-out/_global_index_store' \\
        -enable-bare-slash-regex \\
        -Xfrontend \\
        -disable-clang-spi \\
        -enable-experimental-feature \\
        AccessLevelOnImport \\
        -parse-as-library \\
        -static \\
        -Xcc \\
        -O0 \\
        -Xcc \\
        '-DDEBUG=1' \\
        -Xcc \\
        -fstack-protector \\
        -Xcc \\
        -fstack-protector-all \\
        HelloWorld/HelloWorldLib/Sources/AddTodoView.swift \\
        HelloWorld/HelloWorldLib/Sources/HelloWorldApp.swift \\
        HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift \\
        HelloWorld/HelloWorldLib/Sources/TodoListView.swift)
    # Configuration: 604845167dc010f09949b2428d826ae6495e5a888d2bc1b075d74c5b5f033cbb
    # Execution platform: @@platforms//host:host
      ExecutionInfo: {requires-darwin: '', requires-worker-protocol: json, supports-workers: 1, supports-xcode-requirements-set: ''}

    action 'Compiling Swift module //HelloWorld:TodoModels'
      Mnemonic: SwiftCompile
      Target: //HelloWorld:TodoModels
      Configuration: ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f
      Execution platform: @@platforms//host:host
      ActionKey: 8fed64bc508d4b5f64a13be5214cddb545c9780e6692d096897b1447da04065f
      Environment: [APPLE_SDK_PLATFORM=iPhoneSimulator, APPLE_SDK_VERSION_OVERRIDE=18.4, XCODE_VERSION_OVERRIDE=16.3.0.16E140]
      Command Line: (exec bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/external/rules_swift+/tools/worker/worker \\
        swiftc \\
        -target \\
        arm64-apple-ios17.0-simulator \\
        -sdk \\
        __BAZEL_XCODE_SDKROOT__ \\
        -debug-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR' \\
        -file-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR' \\
        '-Xwrapped-swift=-bazel-target-label=@@//HelloWorld:TodoModels' \\
        -emit-object \\
        -output-file-map \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.output_file_map.json \\
        -Xfrontend \\
        -no-clang-module-breadcrumbs \\
        -emit-module-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.swiftmodule \\
        '-enforce-exclusivity=checked' \\
        -emit-const-values-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels_objs/TodoModels/Sources/TodoItem.swift.swiftconstvalues \\
        -Xfrontend \\
        -const-gather-protocols-file \\
        -Xfrontend \\
        external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json \\
        -DDEBUG \\
        -Onone \\
        -Xfrontend \\
        -internalize-at-link \\
        -Xfrontend \\
        -no-serialize-debugging-options \\
        -enable-testing \\
        -disable-sandbox \\
        -g \\
        '-Xwrapped-swift=-file-prefix-pwd-is-dot' \\
        '-Xwrapped-swift=-emit-swiftsourceinfo' \\
        -module-cache-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/_swift_module_cache \\
        '-Xwrapped-swift=-macro-expansion-dir=bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.macro-expansions' \\
        -Xcc \\
        -iquote. \\
        -Xcc \\
        -iquotebazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin \\
        -Xfrontend \\
        -color-diagnostics \\
        -enable-batch-mode \\
        -module-name \\
        TodoModels \\
        -file-prefix-map \\
        '__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR' \\
        -index-store-path \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/TodoModels.indexstore \\
        -index-ignore-system-modules \\
        '-Xwrapped-swift=-global-index-store-import-path=bazel-out/_global_index_store' \\
        -enable-bare-slash-regex \\
        -Xfrontend \\
        -disable-clang-spi \\
        -enable-experimental-feature \\
        AccessLevelOnImport \\
        -parse-as-library \\
        -static \\
        -Xcc \\
        -O0 \\
        -Xcc \\
        '-DDEBUG=1' \\
        -Xcc \\
        -fstack-protector \\
        -Xcc \\
        -fstack-protector-all \\
        HelloWorld/TodoModels/Sources/TodoItem.swift \\
        HelloWorld/TodoModels/Sources/TodoListManager.swift)
    # Configuration: 604845167dc010f09949b2428d826ae6495e5a888d2bc1b075d74c5b5f033cbb
    # Execution platform: @@platforms//host:host
      ExecutionInfo: {requires-darwin: '', requires-worker-protocol: json, supports-workers: 1, supports-xcode-requirements-set: ''}

    action 'Compiling HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m'
      Mnemonic: ObjcCompile
      Target: //HelloWorld:TodoObjCSupport
      Configuration: ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f
      Execution platform: @@platforms//host:host
      ActionKey: cbc1b4b2a1d1f1430bacf863eae80b3238dfc83b860f0b05d2e270350d3cd953
      Command Line: (exec bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/external/apple_support+/crosstool/wrapped_clang \\
        -target \\
        arm64-apple-ios17.0-simulator \\
        '-D_FORTIFY_SOURCE=1' \\
        -fstack-protector \\
        -fcolor-diagnostics \\
        -Wall \\
        -Wthread-safety \\
        -Wself-assign \\
        -fno-omit-frame-pointer \\
        -g \\
        '-fdebug-prefix-map=__BAZEL_EXECUTION_ROOT__=.' \\
        '-fdebug-prefix-map=__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR' \\
        '-Werror=incompatible-sysroot' \\
        -Wshorten-64-to-32 \\
        -Wbool-conversion \\
        -Wconstant-conversion \\
        -Wduplicate-method-match \\
        -Wempty-body \\
        -Wenum-conversion \\
        -Wint-conversion \\
        -Wunreachable-code \\
        -Wmismatched-return-types \\
        -Wundeclared-selector \\
        -Wuninitialized \\
        -Wunused-function \\
        -Wunused-variable \\
        -iquote \\
        . \\
        -iquote \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin \\
        -MD \\
        -MF \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.d \\
        -DOS_IOS \\
        -fno-autolink \\
        -isysroot \\
        __BAZEL_XCODE_SDKROOT__ \\
        -F__BAZEL_XCODE_SDKROOT__/System/Library/Frameworks \\
        -F__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks \\
        -fobjc-arc \\
        -fexceptions \\
        -fasm-blocks \\
        '-fobjc-abi-version=2' \\
        -fobjc-legacy-dispatch \\
        -O0 \\
        '-DDEBUG=1' \\
        -fstack-protector \\
        -fstack-protector-all \\
        -g \\
        -c \\
        HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m \\
        -o \\
        bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.o)
    # Configuration: 604845167dc010f09949b2428d826ae6495e5a888d2bc1b075d74c5b5f033cbb
    # Execution platform: @@platforms//host:host
      ExecutionInfo: {requires-darwin: '', supports-xcode-requirements-set: ''}

    """

/// Expected result of processing the example input for the Swift target.
let expectedSwiftResult: [String] = [
    "-target", "arm64-apple-ios17.0-simulator", "-sdk",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-debug-prefix-map", "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR", "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR", "-emit-object", "-output-file-map",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.output_file_map.json",
    "-Xfrontend", "-no-clang-module-breadcrumbs", "-emit-module-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.swiftmodule",
    "-enforce-exclusivity=checked", "-emit-const-values-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib_objs/HelloWorldLib/Sources/AddTodoView.swift.swiftconstvalues",
    "-Xfrontend", "-const-gather-protocols-file", "-Xfrontend",
    "/private/var/tmp/_bazel_user/hash123/external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json",
    "-DDEBUG", "-Onone", "-Xfrontend", "-internalize-at-link", "-Xfrontend", "-no-serialize-debugging-options",
    "-enable-testing", "-disable-sandbox", "-g", "-module-cache-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/_swift_module_cache",
    "-I/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld",
    "-Xcc", "-iquote.", "-Xcc",
    "-iquote/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin",
    "-Xcc",
    "-fmodule-map-file=/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/module.modulemap",
    "-Xfrontend", "-color-diagnostics", "-module-name", "HelloWorldLib", "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=DEVELOPER_DIR", "-index-store-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/_global_index_store",
    "-index-ignore-system-modules", "-enable-bare-slash-regex", "-Xfrontend", "-disable-clang-spi",
    "-enable-experimental-feature", "AccessLevelOnImport", "-parse-as-library", "-static", "-Xcc", "-O0", "-Xcc",
    "-DDEBUG=1", "-Xcc", "-fstack-protector", "-Xcc", "-fstack-protector-all",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/AddTodoView.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/HelloWorldApp.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoListView.swift",
]

/// Expected result of processing the example input for the Obj-C file.
let expectedObjCResult: [String] = [
    "-x", "objective-c", "-target", "arm64-apple-ios17.0-simulator", "-D_FORTIFY_SOURCE=1", "-fstack-protector",
    "-fcolor-diagnostics", "-Wall", "-Wthread-safety", "-Wself-assign", "-fno-omit-frame-pointer", "-g",
    "-fdebug-prefix-map=/Users/user/Documents/demo-ios-project=.",
    "-fdebug-prefix-map=/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-Werror=incompatible-sysroot", "-Wshorten-64-to-32", "-Wbool-conversion", "-Wconstant-conversion",
    "-Wduplicate-method-match", "-Wempty-body", "-Wenum-conversion", "-Wint-conversion", "-Wunreachable-code",
    "-Wmismatched-return-types", "-Wundeclared-selector", "-Wuninitialized", "-Wunused-function", "-Wunused-variable",
    "-iquote", ".", "-iquote",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin",
    "-MD", "-MF",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.d",
    "-DOS_IOS", "-fno-autolink", "-isysroot",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks",
    "-fobjc-arc", "-fexceptions", "-fasm-blocks", "-fobjc-abi-version=2", "-fobjc-legacy-dispatch", "-O0", "-DDEBUG=1",
    "-fstack-protector", "-fstack-protector-all", "-g", "HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m",
    "-o",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.o",
    "-index-store-path", "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/_global_index_store",
    "-working-directory", "/Users/user/Documents/demo-ios-project",
]
