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
    private static let mockOutputPath = "/tmp/execroot/_main/bazel-out"

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
            toolchainPath: Self.mockToolchainPath,
            outputPath: Self.mockOutputPath
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
                displayName: "//HelloWorld:HelloWorldE2ETestsLib",
                language: .swift,
                dependencyLabels: []
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
            ("//HelloWorld:HelloWorldWatchApp", .watchosApplication),
            ("//HelloWorld:HelloWorldE2ETests", .iosUiTest),
            ("//HelloWorld:HelloWorldTests", .iosUnitTest),
            ("//HelloWorld:HelloWorldMacApp", .macosApplication),
            ("//HelloWorld:HelloWorld", .iosApplication),
            ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest),
            ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication),
            ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension),
            ("//HelloWorld:HelloWorldMacTests", .macosUnitTest),
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
        #expect(result.bspURIsToSrcsMap.keys.count == 15, "bspURIsToSrcsMap should have 15 target URIs")
        #expect(result.srcToBspURIsMap.count == 30, "srcToBspURIsMap should have 30 source files")

        // Verify filegroup sources are included in the correct targets' source lists.
        // HelloWorldTestsLib should contain filegroup sources from HelloWorldTestsAdditionalSources,
        // including sources from a nested filegroup and an aliased source file.
        let testsLibSrcs = result.bspURIsToSrcsMap.first {
            result.bspURIsToBazelLabelsMap[$0.key] == "//HelloWorld:HelloWorldTestsLib"
        }?.value
        #expect(testsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupForUnitTest.swift") } == true)
        #expect(testsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupForUnitTest2.swift") } == true)
        // Nested filegroup source
        #expect(testsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupNested.swift") } == true)
        // Aliased source file within the filegroup
        #expect(testsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupAliased.swift") } == true)

        // HelloWorldE2ETestsLib should contain filegroup sources from HelloWorldE2ETestsAdditionalSources.
        let e2eTestsLibSrcs = result.bspURIsToSrcsMap.first {
            result.bspURIsToBazelLabelsMap[$0.key] == "//HelloWorld:HelloWorldE2ETestsLib"
        }?.value
        #expect(
            e2eTestsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupForE2ETest.swift") } == true
        )
        #expect(
            e2eTestsLibSrcs?.sources.contains { $0.uri.stringValue.contains("FilegroupForE2ETest2.swift") } == true
        )

        // BSP URI to parent config map - verify URIs map to configs
        #expect(result.bspUriToParentConfigMap.count == 15, "bspUriToParentConfigMap should have 15 entries")

        // Verify bspUriToTopLevelLabelsMap - this maps each target to its actual top-level parents
        // based on the dependency graph, not just config mnemonic matching
        #expect(result.bspUriToTopLevelLabelsMap.count == 15, "bspUriToTopLevelLabelsMap should have 15 entries")

        // Helper to get parent labels for a given label using the new dependency-graph-based mapping
        // This is more precise than the old config-based mapping
        func getParentLabels(forLabel label: String) -> Set<String> {
            var parentLabels = Set<String>()
            for (uri, targetLabel) in result.bspURIsToBazelLabelsMap where targetLabel == label {
                guard let labels = result.bspUriToTopLevelLabelsMap[uri] else {
                    continue
                }
                parentLabels.formUnion(labels)
            }
            return parentLabels
        }

        // iOS targets - verify based on actual dependency relationships, not just config matching
        // ExpandedTemplate and GeneratedDummy are deps of HelloWorldLib, which is dep of HelloWorld.
        // HelloWorldTests deps on HelloWorldTestsLib which deps on HelloWorldLib.
        // HelloWorldE2ETests has test_host=HelloWorld, but test_host is NOT included in deps,
        // so E2E tests only include their own deps (HelloWorldE2ETestsLib), not the test host's deps.
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
        // HelloWorldTestsLib is ONLY a dep of HelloWorldTests, not of HelloWorld or HelloWorldE2ETests
        #expect(
            getParentLabels(forLabel: "//HelloWorld:HelloWorldTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldTests"
                ])
        )
        // macOS targets - MacAppLib is dep of HelloWorldMacApp and HelloWorldMacTests (via MacAppTestsLib)
        // but NOT of HelloWorldMacCLIApp (which only deps on MacCLIAppLib)
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        // MacAppTestsLib is ONLY a dep of HelloWorldMacTests
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacAppTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests"
                ])
        )
        // MacCLIAppLib is ONLY a dep of HelloWorldMacCLIApp
        #expect(
            getParentLabels(forLabel: "//HelloWorld:MacCLIAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacCLIApp"
                ])
        )
        // TodoModels is used by multiple targets across platforms
        // iOS: HelloWorld -> HelloWorldLib -> TodoModelsAlias -> TodoModels
        //      HelloWorldTests -> HelloWorldTestsLib -> HelloWorldLib -> ...
        //      Note: HelloWorldE2ETests is NOT included because test_host is not a dep
        // macOS: HelloWorldMacApp -> MacAppLib -> TodoModels
        //        HelloWorldMacTests -> MacAppTestsLib -> MacAppLib -> ...
        //        HelloWorldMacCLIApp -> MacCLIAppLib -> TodoModels
        // watchOS: HelloWorldWatchExtension -> WatchAppLib -> TodoModels
        //          HelloWorldWatchTests -> WatchAppTestsLib -> WatchAppLib -> ...
        //          Note: HelloWorldWatchApp is NOT included because extension is not a dep
        #expect(
            getParentLabels(forLabel: "//HelloWorld:TodoModels")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                    "//HelloWorld:HelloWorldWatchTests",
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        // TodoObjCSupport is a dep of HelloWorldLib (iOS only)
        // Note: HelloWorldE2ETests is NOT included because test_host is not a dep
        #expect(
            getParentLabels(forLabel: "//HelloWorld:TodoObjCSupport")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        // HelloWorldE2ETestsLib is ONLY a dep of HelloWorldE2ETests
        #expect(
            getParentLabels(forLabel: "//HelloWorld:HelloWorldE2ETestsLib")
                == Set([
                    "//HelloWorld:HelloWorldE2ETests"
                ])
        )
        // watchOS targets - WatchAppLib is dep of HelloWorldWatchExtension
        // HelloWorldWatchTests deps on WatchAppTestsLib which deps on WatchAppLib
        // Note: HelloWorldWatchApp is NOT included because it uses extension attribute, not deps
        #expect(
            getParentLabels(forLabel: "//HelloWorld:WatchAppLib")
                == Set([
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldWatchTests",
                ])
        )
        // WatchAppTestsLib is ONLY a dep of HelloWorldWatchTests
        #expect(
            getParentLabels(forLabel: "//HelloWorld:WatchAppTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldWatchTests"
                ])
        )

        // Verify testTargetToBundleTargetMap - maps test targets to their bundle target URIs
        // These are the test bundle targets that should have their bundle URIs mapped
        let expectedTestTargets = Set([
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorldE2ETests",
            "//HelloWorld:HelloWorldMacTests",
            "//HelloWorld:HelloWorldWatchTests",
        ])
        let actualTestTargets = Set(result.testTargetToBundleTargetMap.keys)
        #expect(
            actualTestTargets == expectedTestTargets,
            "testTargetToBundleTargetMap keys don't match expected test targets"
        )

        // Verify each test target maps to a valid bundle target URI
        for testTarget in expectedTestTargets {
            let bundleTargetUri = try #require(
                result.testTargetToBundleTargetMap[testTarget],
                "Missing bundle target URI for test target: \(testTarget)"
            )
            // The bundle target URI should exist in bspURIsToSrcsMap
            #expect(
                result.bspURIsToSrcsMap[bundleTargetUri] != nil,
                "Bundle target URI should be a valid target with sources: \(testTarget)"
            )
        }

        // Verify specific bundle target mappings
        // HelloWorldTests should map to a bundle target containing test sources
        let unitTestBundleUri = try #require(result.testTargetToBundleTargetMap["//HelloWorld:HelloWorldTests"])
        let unitTestSources = try #require(result.bspURIsToSrcsMap[unitTestBundleUri])
        #expect(unitTestSources.sources.contains { $0.uri.stringValue.contains("HelloWorldTests/") })

        // HelloWorldE2ETests should map to a bundle target containing E2E test sources
        let e2eTestBundleUri = try #require(result.testTargetToBundleTargetMap["//HelloWorld:HelloWorldE2ETests"])
        let e2eTestSources = try #require(result.bspURIsToSrcsMap[e2eTestBundleUri])
        #expect(e2eTestSources.sources.contains { $0.uri.stringValue.contains("HelloWorldE2ETests/") })
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
            executionRoot: Self.mockExecutionRoot,
            outputPath: Self.mockOutputPath
        )

        let targetUri = try URI(
            string:
                "bazel:///path/to/project/HelloWorld/HelloWorldLib_ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300"
        )
        let srcUri = try URI(
            string:
                "file:///Users/rochab/src/sourcekit-bazel-bsp/Example/HelloWorld/HelloWorldLib/Sources/TodoItemRow.swift"
        )

        let configMnemonic = "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-ST-2842469f5300"
        let expectedOutputPath =
            "./bazel-out/\(configMnemonic)/bin/HelloWorld/HelloWorldLib_objs/TodoItemRow.swift.o"
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
                            outputPath: expectedOutputPath,
                            copyDestinations: nil
                        ).encodeToLSPAny()
                    )
                ]
            ]
        )

        #expect(result.newSrcToBspURIsMap == [srcUri: [targetUri]])
    }
}
