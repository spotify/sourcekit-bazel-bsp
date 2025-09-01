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
    private static func makeMockExtractor() -> (BazelTargetCompilerArgsExtractor, CommandRunnerFake, String) {
        let mockRunner = CommandRunnerFake()
        let mockRootUri = "/Users/user/Documents/demo-ios-project"
        let mockDevDir = "/Applications/Xcode.app/Contents/Developer"
        let mockOutputPath = "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out"
        let mockOutputBase = "/private/var/tmp/_bazel_user/hash123"
        let mockDevToolchainPath = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let config = InitializedServerConfig(
            baseConfig: BaseServerConfig(
                bazelWrapper: "bazel",
                targets: ["//HelloWorld"],
                indexFlags: [],
                buildTestSuffix: "_skbsp",
                filesToWatch: nil
            ),
            rootUri: mockRootUri,
            outputBase: mockOutputBase,
            outputPath: mockOutputPath,
            devDir: mockDevDir,
            devToolchainPath: mockDevToolchainPath
        )
        let extractor = BazelTargetCompilerArgsExtractor(
            commandRunner: mockRunner,
            aquerier: BazelTargetAquerier(commandRunner: mockRunner),
            config: config
        )
        return (extractor, mockRunner, mockRootUri)
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldSwiftExample() throws {
        let (extractor, mockRunner, mockRootUri) = Self.makeMockExtractor()
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', filter(//HelloWorld:HelloWorldLib, deps(//HelloWorld:HelloWorldLib_ios_skbsp)))\" --noinclude_artifacts --noinclude_aspects --output proto"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryOutput)
        let expectedSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        mockRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path",
            cwd: mockRootUri,
            response: expectedSdkRoot
        )

        let result = try #require(
            try extractor.compilerArgs(
                forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
                inTarget: "//HelloWorld:HelloWorldLib_ios_skbsp",
                underlyingLibrary: "//HelloWorld:HelloWorldLib",
                language: .swift,
                platform: .iosApplication,
            )
        )
        #expect(result == expectedSwiftResult)
    }

    @Test
    func extractsAndProcessesCompilerArguments_complexRealWorldObjCExample() throws {
        let (extractor, mockRunner, mockRootUri) = Self.makeMockExtractor()
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', filter(//HelloWorld:TodoObjCSupport, deps(//HelloWorld:TodoObjCSupport_ios_skbsp)))\" --noinclude_artifacts --noinclude_aspects --output proto"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryObjcOutput)
        let expectedSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        mockRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path",
            cwd: mockRootUri,
            response: expectedSdkRoot
        )

        let result = try #require(
            try extractor.compilerArgs(
                forDoc: URI(
                    filePath:
                        "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m",
                    isDirectory: false
                ),
                inTarget: "//HelloWorld:TodoObjCSupport_ios_skbsp",
                underlyingLibrary: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
                platform: .iosApplication,
            )
        )
        #expect(result == expectedObjCResult)
    }

    @Test
    func ignoresObjCHeaders() throws {
        let (extractor, _, _) = Self.makeMockExtractor()

        let result = try extractor.compilerArgs(
            forDoc: URI(
                filePath:
                    "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.h",
                isDirectory: false
            ),
            inTarget: "//HelloWorld:TodoObjCSupport_ios_skbsp",
            underlyingLibrary: "//HelloWorld:TodoObjCSupport",
            language: .objective_c,
            platform: .iosApplication,
        )
        #expect(result == nil)
    }

    @Test
    func missingObjCFileReturnsNil() throws {
        let (extractor, mockRunner, mockRootUri) = Self.makeMockExtractor()
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', filter(//HelloWorld:TodoObjCSupport, deps(//HelloWorld:TodoObjCSupport_ios_skbsp)))\" --noinclude_artifacts --noinclude_aspects --output proto"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryOutput)
        let expectedSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        mockRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path",
            cwd: mockRootUri,
            response: expectedSdkRoot
        )

        let result = try extractor.compilerArgs(
            forDoc: URI(
                filePath: "/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m",
                isDirectory: false
            ),
            inTarget: "//HelloWorld:TodoObjCSupport_ios_skbsp",
            underlyingLibrary: "//HelloWorld:TodoObjCSupport",
            language: .objective_c,
            platform: .iosApplication,
        )
        #expect(result == nil)
    }

    @Test
    func objCFilesRequireFullPath() throws {
        let (extractor, _, _) = Self.makeMockExtractor()

        let error = #expect(throws: BazelTargetCompilerArgsExtractorError.self) {
            try extractor.compilerArgs(
                forDoc: URI(
                    filePath: "/random/wrong/prefix/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m",
                    isDirectory: false
                ),
                inTarget: "//HelloWorld:TodoObjCSupport_ios_skbsp",
                underlyingLibrary: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
                platform: .iosApplication,
            )
        }
        #expect(
            error?.localizedDescription
                == "Unexpected non-Swift URI missing root URI prefix: file:///random/wrong/prefix/HelloWorld/TodoObjCSupport/Sources/SomethingElse.m"
        )
    }

    @Test
    func missingSwiftModuleReturnsNil() throws {
        let (extractor, mockRunner, mockRootUri) = Self.makeMockExtractor()
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', filter(//HelloWorld:SomethingElseLib, deps(//HelloWorld:SomethingElseLib_ios_skbsp)))\" --noinclude_artifacts --noinclude_aspects --output proto"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryOutput)
        let expectedSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        mockRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path",
            cwd: mockRootUri,
            response: expectedSdkRoot
        )

        let result = try extractor.compilerArgs(
            forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
            inTarget: "//HelloWorld:SomethingElseLib_ios_skbsp",
            underlyingLibrary: "//HelloWorld:SomethingElseLib",
            language: .swift,
            platform: .iosApplication,
        )
        #expect(result == nil)
    }

    @Test
    func cachesCompilerArgs() throws {
        let (extractor, mockRunner, mockRootUri) = Self.makeMockExtractor()
        let expectedAQuery =
            "bazel --output_base=/private/var/tmp/_bazel_user/hash123 aquery \"mnemonic('ObjcCompile|SwiftCompile', filter(//HelloWorld:HelloWorldLib, deps(//HelloWorld:HelloWorldLib_ios_skbsp)))\" --noinclude_artifacts --noinclude_aspects --output proto"
        mockRunner.setResponse(for: expectedAQuery, cwd: mockRootUri, response: exampleAqueryOutput)
        let expectedSdkRoot =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        mockRunner.setResponse(
            for: "xcrun --sdk iphonesimulator --show-sdk-path",
            cwd: mockRootUri,
            response: expectedSdkRoot
        )

        func run(_ lib: String, _ underlyingLibrary: String) -> [String]? {
            return try? extractor.compilerArgs(
                forDoc: URI(filePath: "not relevant for Swift", isDirectory: false),
                inTarget: lib,
                underlyingLibrary: underlyingLibrary,
                language: .swift,
                platform: .iosApplication,
            )
        }

        let result1 = try #require(run("//HelloWorld:HelloWorldLib_ios_skbsp", "//HelloWorld:HelloWorldLib"))

        // Remove the mock aquery responses to indicate that we skipped that section of the logic entirely
        mockRunner.reset()

        let result2 = try #require(run("//HelloWorld:HelloWorldLib_ios_skbsp", "//HelloWorld:HelloWorldLib"))
        #expect(result1 == result2)
    }
}

// MARK: - Example inputs and expected results

/// Example aquery output for the example app shipped with this repo.
/// Important: The \s from the output have to be escaped, so careful when updating it.
private let exampleAqueryOutput: Data = {
    guard let url = Bundle.module.url(forResource: "aquery", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("aquery.pb is not found in Resources folder") }
    return data
}()

private let exampleAqueryObjcOutput: Data = {
    guard let url = Bundle.module.url(forResource: "aquery_objc", withExtension: "pb"),
        let data = try? Data.init(contentsOf: url)
    else { fatalError("aquery_objc.pb is not found in Resources folder") }
    return data
}()

/// Expected result of processing the example input for the Swift target.
let expectedSwiftResult: [String] = [
    "-target",
    "arm64-apple-ios17.0-simulator",
    "-sdk",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-debug-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=/PLACEHOLDER_DEVELOPER_DIR",
    "-emit-object",
    "-output-file-map",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.output_file_map.json",
    "-Xfrontend",
    "-no-clang-module-breadcrumbs",
    "-emit-module-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/HelloWorldLib.swiftmodule",
    "-enforce-exclusivity=checked",
    "-Xfrontend",
    "-const-gather-protocols-file",
    "-Xfrontend",
    "/private/var/tmp/_bazel_user/hash123/external/rules_swift+/swift/toolchains/config/const_protocols_to_gather.json",
    "-DDEBUG",
    "-Onone",
    "-Xfrontend",
    "-internalize-at-link",
    "-Xfrontend",
    "-no-serialize-debugging-options",
    "-enable-testing",
    "-disable-sandbox",
    "-g",
    "-module-cache-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/_swift_module_cache",
    "-I/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld",
    "-Xcc",
    "-iquote.",
    "-Xcc",
    "-iquote/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin",
    "-Xcc",
    "-fmodule-map-file=/Users/user/Documents/demo-ios-project/HelloWorld/TodoObjCSupport/Sources/module.modulemap",
    "-Xfrontend",
    "-color-diagnostics",
    "-module-name",
    "HelloWorldLib",
    "-file-prefix-map",
    "/Applications/Xcode.app/Contents/Developer=DEVELOPER_DIR",
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
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/AddTodoView.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/HelloWorldApp.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift",
    "/Users/user/Documents/demo-ios-project/HelloWorld/HelloWorldLib/Sources/TodoListView.swift",
]

/// Expected result of processing the example input for the Obj-C file.
let expectedObjCResult: [String] = [
    "-x",
    "objective-c",
    "-target",
    "arm64-apple-ios17.0-simulator",
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
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin",
    "-MD",
    "-MF",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.d",
    "-DOS_IOS",
    "-fno-autolink",
    "-isysroot",
    "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks",
    "-F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks",
    "-fobjc-arc",
    "-fexceptions",
    "-fasm-blocks",
    "-fobjc-abi-version=2",
    "-fobjc-legacy-dispatch",
    "-O0",
    "-DDEBUG=1",
    "-fstack-protector",
    "-fstack-protector-all",
    "-g",
    "HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.m",
    "-o",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f/bin/HelloWorld/_objs/TodoObjCSupport/arc/SKDateDistanceCalculator.o",
    "-index-store-path",
    "/private/var/tmp/_bazel_user/hash123/execroot/__main__/bazel-out/_global_index_store",
    "-working-directory",
    "/Users/user/Documents/demo-ios-project",
]
