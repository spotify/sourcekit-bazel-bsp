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

@Suite
struct BazelTargetQuerierParserImplTests {

    private static let mockRootUri = "/path/to/project"
    private static let mockWorkspaceName = "_main"
    private static let mockExecutionRoot = "/tmp/execroot/_main"
    private static let mockToolchainPath = "/path/to/toolchain"

    @Test
    func canProcessExampleCquery() throws {
        let parser = BazelTargetQuerierParserImpl()

        let supportedTopLevelRuleTypes = TopLevelRuleType.allCases
        let testBundleRules = supportedTopLevelRuleTypes.compactMap { $0.testBundleRule }

        let result = try parser.processCquery(
            from: exampleCqueryOutput,
            testBundleRules: testBundleRules,
            supportedDependencyRuleTypes: DependencyRuleType.allCases,
            supportedTopLevelRuleTypes: supportedTopLevelRuleTypes,
            rootUri: Self.mockRootUri,
            workspaceName: Self.mockWorkspaceName,
            executionRoot: Self.mockExecutionRoot,
            toolchainPath: Self.mockToolchainPath
        )

        // Expected target properties (language and dependency labels)
        // Note: With multi-variant support, targets can appear multiple times with different configs.
        // URIs now include config IDs, so we verify by display name and check properties.
        struct ExpectedTargetInfo {
            let displayName: String
            let language: Language
            let dependencyLabels: Set<String>
        }

        let expectedTargets: [ExpectedTargetInfo] = [
            ExpectedTargetInfo(displayName: "//HelloWorld:ExpandedTemplate", language: .swift, dependencyLabels: []),
            ExpectedTargetInfo(displayName: "//HelloWorld:GeneratedDummy", language: .swift, dependencyLabels: []),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:HelloWorldLib",
                language: .swift,
                dependencyLabels: [
                    "//HelloWorld:TodoModels", "//HelloWorld:TodoObjCSupport",
                    "//HelloWorld:ExpandedTemplate", "//HelloWorld:GeneratedDummy",
                ]
            ),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:HelloWorldTestsLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:HelloWorldLib"]
            ),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:MacAppLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:TodoModels"]
            ),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:MacAppTestsLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:MacAppLib"]
            ),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:MacCLIAppLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:TodoModels"]
            ),
            ExpectedTargetInfo(displayName: "//HelloWorld:TodoModels", language: .swift, dependencyLabels: []),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
                dependencyLabels: ["//HelloWorld:TodoCSupport"]
            ),
            ExpectedTargetInfo(displayName: "//HelloWorld:TodoCSupport", language: .cpp, dependencyLabels: []),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:WatchAppLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:TodoModels"]
            ),
            ExpectedTargetInfo(
                displayName: "//HelloWorld:WatchAppTestsLib",
                language: .swift,
                dependencyLabels: ["//HelloWorld:WatchAppLib"]
            ),
        ]

        // Group actual targets by displayName (same target can appear with multiple configs)
        var actualTargetsByName: [String: [BuildTarget]] = [:]
        for target in result.buildTargets {
            guard let name = target.displayName else { continue }
            actualTargetsByName[name, default: []].append(target)
        }

        // Verify all expected targets exist and have correct properties
        for expected in expectedTargets {
            let targets = try #require(
                actualTargetsByName[expected.displayName],
                "Missing target: \(expected.displayName)"
            )
            #expect(!targets.isEmpty, "No targets found for \(expected.displayName)")

            // Verify each variant has the correct language
            for target in targets {
                #expect(
                    target.languageIds == [expected.language],
                    "languageIds mismatch for \(expected.displayName)"
                )
            }

            // Verify dependencies by looking up the labels from the dependency URIs
            // Each variant should have dependencies pointing to targets with the expected labels
            for target in targets {
                let actualDepLabels = Set(
                    target.dependencies.compactMap { depId -> String? in
                        result.bspURIsToBazelLabelsMap[depId.uri]
                    }
                )
                #expect(
                    actualDepLabels == expected.dependencyLabels,
                    "dependencies mismatch for \(expected.displayName): got \(actualDepLabels), expected \(expected.dependencyLabels)"
                )
            }
        }

        // Verify we have the expected unique target labels
        let expectedLabels = Set(expectedTargets.map { $0.displayName })
        let actualLabels = Set(actualTargetsByName.keys)
        #expect(actualLabels == expectedLabels, "Target label sets don't match")

        // Top level targets - verify label and rule type (config IDs are assigned during parsing)
        let expectedTopLevelTargets: [(String, TopLevelRuleType)] = [
            ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest),
            ("//HelloWorld:HelloWorld", .iosApplication),
            ("//HelloWorld:HelloWorldMacApp", .macosApplication),
            ("//HelloWorld:HelloWorldTests", .iosUnitTest),
            ("//HelloWorld:HelloWorldMacTests", .macosUnitTest),
            ("//HelloWorld:HelloWorldWatchApp", .watchosApplication),
            ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension),
            ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication),
        ]
        #expect(result.topLevelTargets.count == expectedTopLevelTargets.count)
        for (index, expected) in expectedTopLevelTargets.enumerated() {
            let actual = result.topLevelTargets[index]
            #expect(actual.0 == expected.0)
            #expect(actual.1 == expected.1)
        }

        // Verify bspURIsToBazelLabelsMap contains all expected labels
        // With multi-variant support, the same label may have multiple URIs
        let actualLabelSet = Set(result.bspURIsToBazelLabelsMap.values)
        #expect(actualLabelSet == expectedLabels, "bspURIsToBazelLabelsMap labels don't match")

        // Verify counts - with multi-variant support, targets can have multiple URIs (one per config)
        #expect(result.bspURIsToSrcsMap.keys.count == 14, "bspURIsToSrcsMap should have 14 target URIs")
        #expect(result.srcToBspURIsMap.count == 23, "srcToBspURIsMap should have 23 source files")

        // BSP URI to parent config map - verify URIs map to configs
        #expect(result.bspUriToParentConfigMap.count == 14, "bspUriToParentConfigMap should have 14 entries")

        // Helper to get parent labels for a given label through the config mapping
        // Finds all URIs for a label and returns the union of their parent labels
        func getParentLabels(forLabel label: String) -> Set<String> {
            var parentLabels = Set<String>()
            for (uri, targetLabel) in result.bspURIsToBazelLabelsMap where targetLabel == label {
                guard let configHash = result.bspUriToParentConfigMap[uri],
                    let labels = result.configurationToTopLevelLabelsMap[configHash]
                else {
                    continue
                }
                parentLabels.formUnion(labels)
            }
            return parentLabels
        }

        // iOS targets should have iOS top-level parents
        #expect(
            getParentLabels(forLabel: "//HelloWorld:ExpandedTemplate")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:GeneratedDummy")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:HelloWorldLib")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:HelloWorldTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        // macOS targets
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacAppTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacCLIAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        // TodoModels is used by multiple platforms (iOS, macOS, watchOS)
        #expect(
            getParentLabels(forLabel: "//HelloWorld:TodoModels")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                    "//HelloWorld:HelloWorldWatchApp",
                    "//HelloWorld:HelloWorldWatchTests",
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:TodoObjCSupport")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        // watchOS targets
        #expect(
            getParentLabels(forLabel: "//HelloWorld:WatchAppLib")
                == Set([
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldWatchApp",
                    "//HelloWorld:HelloWorldWatchTests",
                ])
        )
        #expect(
            getParentLabels(forLabel: "//HelloWorld:WatchAppTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldWatchApp",
                    "//HelloWorld:HelloWorldWatchTests",
                ])
        )
    }

    @Test
    func canProcessExampleAquery() throws {
        let parser = BazelTargetQuerierParserImpl()

        // These details are meant to match the provided aquery pb example.
        // Config mnemonics are the human-readable configuration names from the cquery protobuf.
        let iosMnemonic = "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300"
        let macOsMnemonic = "darwin_arm64-dbg-macos-arm64-min15.0-ST-3b9f41d61db6"
        let watchOsMnemonic = "watchos_arm64-dbg-watchos-arm64-min7.0-ST-f4f2bb7e56ed"
        let topLevelTargets: [(String, TopLevelRuleType, String)] = [
            ("//HelloWorld:HelloWorld", .iosApplication, iosMnemonic),
            ("//HelloWorld:HelloWorldMacApp", .macosApplication, macOsMnemonic),
            ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication, macOsMnemonic),
            ("//HelloWorld:HelloWorldMacTests", .macosUnitTest, macOsMnemonic),
            ("//HelloWorld:HelloWorldTests", .iosUnitTest, iosMnemonic),
            ("//HelloWorld:HelloWorldWatchApp", .watchosApplication, watchOsMnemonic),
            ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension, watchOsMnemonic),
            ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest, watchOsMnemonic),
        ]

        let result = try parser.processAquery(
            from: exampleAqueryOutput,
            topLevelTargets: topLevelTargets
        )

        // 3 unique config mnemonics (iOS, macOS, watchOS)
        #expect(result.topLevelConfigMnemonicToInfoMap.count == 3)

        // iOS config
        #expect(
            result.topLevelConfigMnemonicToInfoMap[iosMnemonic]
                == BazelTargetConfigurationInfo(
                    configurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300",
                    effectiveConfigurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
                    minimumOsVersion: "17.0",
                    platform: "ios",
                    cpuArch: "sim_arm64",
                    sdkName: "iphonesimulator"
                )
        )

        // macOS config
        #expect(
            result.topLevelConfigMnemonicToInfoMap[macOsMnemonic]
                == BazelTargetConfigurationInfo(
                    configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-ST-3b9f41d61db6",
                    effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
                    minimumOsVersion: "15.0",
                    platform: "darwin",
                    cpuArch: "arm64",
                    sdkName: "macosx"
                )
        )

        // watchOS config
        #expect(
            result.topLevelConfigMnemonicToInfoMap[watchOsMnemonic]
                == BazelTargetConfigurationInfo(
                    configurationName: "watchos_arm64-dbg-watchos-arm64-min7.0-ST-f4f2bb7e56ed",
                    effectiveConfigurationName: "watchos_arm64-dbg-watchos-arm64-min7.0",
                    minimumOsVersion: "7.0",
                    platform: "watchos",
                    cpuArch: "arm64",
                    sdkName: "watchsimulator"
                )
        )
    }

    @Test
    func canProcessExampleCqueryForAddedFiles() throws {
        let parser = BazelTargetQuerierParserImpl()

        let result = try parser.processCqueryAddedFiles(
            from: exampleCqueryAddedFilesOutput,
            srcs: ["HelloWorldLib/Sources/TodoItemRow.swift"],
            rootUri: Self.mockRootUri,
            workspaceName: Self.mockWorkspaceName,
            executionRoot: Self.mockExecutionRoot
        )

        let targetUri = try URI(
            string:
                "bazel:///path/to/project/HelloWorld/HelloWorldLib_ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300"
        )
        let srcUri = try URI(
            string:
                "file:///Users/rochab/src/sourcekit-bazel-bsp/Example/HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift"
        )

        #expect(
            result.bspURIsToNewSourceItemsMap == [
                targetUri: [
                    SourceItem(
                        uri: srcUri,
                        kind: .file,
                        generated: false,
                        dataKind: .sourceKit,
                        data: SourceKitSourceItemData(
                            language: .swift,
                            kind: .source,
                            outputPath: nil,
                            copyDestinations: nil
                        ).encodeToLSPAny()
                    )
                ]
            ]
        )

        #expect(result.newSrcToBspURIsMap == [srcUri: [targetUri]])
    }
}
