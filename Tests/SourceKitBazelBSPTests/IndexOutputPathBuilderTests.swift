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
import LanguageServerProtocol
import Testing

@testable import SourceKitBazelBSP

@Suite
struct IndexOutputPathBuilderParseRuleNameTests {
    // MARK: - Basic Rule Name Parsing

    @Test
    func parsesSimpleRuleName() {
        let result = IndexOutputPathBuilder.parseRuleName("//Sources/MyLib:MyLib")

        #expect(result.packagePath == "Sources/MyLib")
        #expect(result.targetName == "MyLib")
        #expect(result.externalRepoName == nil)
    }

    @Test
    func parsesRuleNameWithDifferentTargetName() {
        let result = IndexOutputPathBuilder.parseRuleName("//Sources/MyLib:MyLibTarget")

        #expect(result.packagePath == "Sources/MyLib")
        #expect(result.targetName == "MyLibTarget")
        #expect(result.externalRepoName == nil)
    }

    @Test
    func parsesRootPackageRuleName() {
        let result = IndexOutputPathBuilder.parseRuleName("//:RootTarget")

        #expect(result.packagePath == nil)
        #expect(result.targetName == "RootTarget")
        #expect(result.externalRepoName == nil)
    }

    @Test
    func parsesNestedPackagePath() {
        let result = IndexOutputPathBuilder.parseRuleName("//a/b/c/d:target")

        #expect(result.packagePath == "a/b/c/d")
        #expect(result.targetName == "target")
        #expect(result.externalRepoName == nil)
    }

    // MARK: - External Repository Parsing

    @Test
    func parsesExternalRepoRuleName() {
        let result = IndexOutputPathBuilder.parseRuleName("@abseil-cpp//absl/base:base")

        #expect(result.packagePath == "absl/base")
        #expect(result.targetName == "base")
        #expect(result.externalRepoName == "abseil-cpp")
    }

    @Test
    func parsesExternalRepoWithRootPackage() {
        let result = IndexOutputPathBuilder.parseRuleName("@some_repo//:target")

        #expect(result.packagePath == nil)
        #expect(result.targetName == "target")
        #expect(result.externalRepoName == "some_repo")
    }

    @Test
    func parsesExternalRepoWithUnderscores() {
        let result = IndexOutputPathBuilder.parseRuleName("@my_external_repo//path/to/pkg:lib")

        #expect(result.packagePath == "path/to/pkg")
        #expect(result.targetName == "lib")
        #expect(result.externalRepoName == "my_external_repo")
    }

    // MARK: - Edge Cases

    @Test
    func parsesRuleNameWithoutColon() {
        let result = IndexOutputPathBuilder.parseRuleName("//Sources/MyLib")

        #expect(result.packagePath == nil)
        #expect(result.targetName == nil)
        #expect(result.externalRepoName == nil)
    }

    @Test
    func parsesEmptyString() {
        let result = IndexOutputPathBuilder.parseRuleName("")

        #expect(result.packagePath == nil)
        #expect(result.targetName == nil)
        #expect(result.externalRepoName == nil)
    }

    @Test
    func parsesRuleNameWithMultipleColons() {
        // Takes the last colon as the separator
        let result = IndexOutputPathBuilder.parseRuleName("//path:to:target")

        #expect(result.packagePath == "path:to")
        #expect(result.targetName == "target")
        #expect(result.externalRepoName == nil)
    }
}

@Suite
struct IndexOutputPathBuilderBuildTests {
    let rootUri = "/Users/user/workspace"
    let executionRoot = "/private/var/tmp/_bazel_user/abc123/execroot/myworkspace"
    let configMnemonic = "ios-arm64-min15.0-applebin_ios-ios_arm64-dbg"

    // MARK: - Swift Tests

    @Test
    func swiftSourceInPackage() {
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "//Sources/MyLib:MyLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyLib/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "./bazel-out/\(configMnemonic)/bin/Sources/MyLib/MyLib_objs/File.swift.o"
        )
    }

    @Test
    func swiftSourceInNestedDirectory() {
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "//Sources/MyLib:MyLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyLib/Subdirectory/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "./bazel-out/\(configMnemonic)/bin/Sources/MyLib/MyLib_objs/Subdirectory/File.swift.o"
        )
    }

    @Test
    func swiftSourceInExternalRepo() {
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "@some_external_repo//Sources/ExternalLib:ExternalLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/ExternalLib/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "./bazel-out/\(configMnemonic)/bin/external/some_external_repo/Sources/ExternalLib/ExternalLib_objs/File.swift.o"
        )
    }

    @Test
    func swiftSourceNotInPackagePrefix() {
        // When filePath doesn't start with packagePrefix, falls back to filename
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "//Sources/MyLib:MyLib",
            configMnemonic: configMnemonic,
            filePath: "/other/path/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "./bazel-out/\(configMnemonic)/bin/Sources/MyLib/MyLib_objs/File.swift.o"
        )
    }

    // MARK: - C Tests

    @Test
    func cSourceInCcLibrary() {
        let result = IndexOutputPathBuilder.build(
            language: .c,
            ruleType: .ccLibrary,
            ruleName: "//Sources/MyCLib:MyCLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyCLib/file.c",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyCLib/_objs/MyCLib/file.o"
        )
    }

    @Test
    func cSourceInObjcLibrary() {
        // objc_library uses /arc subdirectory
        let result = IndexOutputPathBuilder.build(
            language: .c,
            ruleType: .objcLibrary,
            ruleName: "//Sources/MyObjCLib:MyObjCLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyObjCLib/file.c",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyObjCLib/_objs/MyObjCLib/arc/file.o"
        )
    }

    // MARK: - C++ Tests

    @Test
    func cppSourceInCcLibrary() {
        let result = IndexOutputPathBuilder.build(
            language: .cpp,
            ruleType: .ccLibrary,
            ruleName: "//Sources/MyCppLib:MyCppLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyCppLib/file.cpp",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyCppLib/_objs/MyCppLib/file.o"
        )
    }

    @Test
    func cppSourceInExternalRepo() {
        let result = IndexOutputPathBuilder.build(
            language: .cpp,
            ruleType: .ccLibrary,
            ruleName: "@external_cpp_dep//Sources/ExternalCppLib:ExternalCppLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/ExternalCppLib/file.cpp",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/external/external_cpp_dep/Sources/ExternalCppLib/_objs/ExternalCppLib/file.o"
        )
    }

    // MARK: - Objective-C Tests

    @Test
    func objectiveCSourceInObjcLibrary() {
        let result = IndexOutputPathBuilder.build(
            language: .objective_c,
            ruleType: .objcLibrary,
            ruleName: "//Sources/MyObjCLib:MyObjCLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyObjCLib/file.m",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyObjCLib/_objs/MyObjCLib/arc/file.o"
        )
    }

    // MARK: - Objective-C++ Tests

    @Test
    func objectiveCppSourceInObjcLibrary() {
        let result = IndexOutputPathBuilder.build(
            language: .objective_cpp,
            ruleType: .objcLibrary,
            ruleName: "//Sources/MyObjCppLib:MyObjCppLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyObjCppLib/file.mm",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyObjCppLib/_objs/MyObjCppLib/arc/file.o"
        )
    }

    // MARK: - Unsupported Language Tests

    @Test
    func unsupportedLanguageReturnsNil() {
        let result = IndexOutputPathBuilder.build(
            language: .java,
            ruleType: .swiftLibrary,
            ruleName: "//Sources/MyLib:MyLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyLib/File.java",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(result == nil)
    }

    // MARK: - Edge Cases

    @Test
    func fileWithMultipleExtensions() {
        let result = IndexOutputPathBuilder.build(
            language: .cpp,
            ruleType: .ccLibrary,
            ruleName: "//Sources/MyLib:MyLib",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/Sources/MyLib/file.test.cpp",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(
            result
                == "\(executionRoot)/bazel-out/\(configMnemonic)/bin/Sources/MyLib/_objs/MyLib/file.test.o"
        )
    }

    @Test
    func rootPackageRuleName() {
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "//:RootTarget",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        // Returns nil because packagePath is nil for root package rules
        #expect(result == nil)
    }

    @Test
    func invalidRuleNameReturnsNil() {
        let result = IndexOutputPathBuilder.build(
            language: .swift,
            ruleType: .swiftLibrary,
            ruleName: "invalid-rule-name",
            configMnemonic: configMnemonic,
            filePath: "/Users/user/workspace/File.swift",
            rootUri: rootUri,
            executionRoot: executionRoot
        )

        #expect(result == nil)
    }
}
