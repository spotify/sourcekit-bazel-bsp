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

        // Pre-create URIs
        let baseDir = try URI(string: "file:///path/to/project/HelloWorld/")
        let expandedTemplateUri = try URI(string: "file:///path/to/project/HelloWorld/ExpandedTemplate")
        let generatedDummyUri = try URI(string: "file:///path/to/project/HelloWorld/GeneratedDummy")
        let helloWorldLibUri = try URI(string: "file:///path/to/project/HelloWorld/HelloWorldLib")
        let helloWorldTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld/HelloWorldTestsLib")
        let macAppLibUri = try URI(string: "file:///path/to/project/HelloWorld/MacAppLib")
        let macAppTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld/MacAppTestsLib")
        let macCLIAppLibUri = try URI(string: "file:///path/to/project/HelloWorld/MacCLIAppLib")
        let todoModelsUri = try URI(string: "file:///path/to/project/HelloWorld/TodoModels")
        let todoObjCSupportUri = try URI(string: "file:///path/to/project/HelloWorld/TodoObjCSupport")
        let todoCSupport = try URI(string: "file:///path/to/project/HelloWorld/TodoCSupport")
        let watchAppLibUri = try URI(string: "file:///path/to/project/HelloWorld/WatchAppLib")
        let watchAppTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld/WatchAppTestsLib")

        let expectedCapabilities = BuildTargetCapabilities(
            canCompile: true,
            canTest: false,
            canRun: false,
            canDebug: false
        )

        let toolchainUri = try URI(string: "file://" + Self.mockToolchainPath)
        let expectedData = SourceKitBuildTarget(toolchain: toolchainUri).encodeToLSPAny()

        func makeExpectedTarget(
            uri: URI,
            displayName: String,
            language: Language = .swift,
            dependencies: [URI] = []
        ) -> BuildTarget {
            BuildTarget(
                id: BuildTargetIdentifier(uri: uri),
                displayName: displayName,
                baseDirectory: baseDir,
                tags: [.library],
                capabilities: expectedCapabilities,
                languageIds: [language],
                dependencies: dependencies.map { BuildTargetIdentifier(uri: $0) },
                dataKind: .sourceKit,
                data: expectedData
            )
        }

        let expectedBuildTargets = [
            makeExpectedTarget(uri: expandedTemplateUri, displayName: "//HelloWorld:ExpandedTemplate"),
            makeExpectedTarget(uri: generatedDummyUri, displayName: "//HelloWorld:GeneratedDummy"),
            makeExpectedTarget(
                uri: helloWorldLibUri,
                displayName: "//HelloWorld:HelloWorldLib",
                dependencies: [todoModelsUri, todoObjCSupportUri, expandedTemplateUri, generatedDummyUri]
            ),
            makeExpectedTarget(
                uri: helloWorldTestsLibUri,
                displayName: "//HelloWorld:HelloWorldTestsLib",
                dependencies: [helloWorldLibUri]
            ),
            makeExpectedTarget(
                uri: macAppLibUri,
                displayName: "//HelloWorld:MacAppLib",
                dependencies: [todoModelsUri]
            ),
            makeExpectedTarget(
                uri: macAppTestsLibUri,
                displayName: "//HelloWorld:MacAppTestsLib",
                dependencies: [macAppLibUri]
            ),
            makeExpectedTarget(
                uri: macCLIAppLibUri,
                displayName: "//HelloWorld:MacCLIAppLib",
                dependencies: [todoModelsUri]
            ),
            makeExpectedTarget(uri: todoModelsUri, displayName: "//HelloWorld:TodoModels"),
            makeExpectedTarget(
                uri: todoObjCSupportUri,
                displayName: "//HelloWorld:TodoObjCSupport",
                language: .objective_c,
                dependencies: [todoCSupport]
            ),
            makeExpectedTarget(
                uri: todoCSupport,
                displayName: "//HelloWorld:TodoCSupport",
                language: .cpp
            ),
            makeExpectedTarget(
                uri: watchAppLibUri,
                displayName: "//HelloWorld:WatchAppLib",
                dependencies: [todoModelsUri]
            ),
            makeExpectedTarget(
                uri: watchAppTestsLibUri,
                displayName: "//HelloWorld:WatchAppTestsLib",
                dependencies: [watchAppLibUri]
            ),
        ]
        #expect(result.buildTargets.count == expectedBuildTargets.count)

        // Build a lookup map for actual targets by displayName
        let actualTargetsByName = Dictionary(
            uniqueKeysWithValues: result.buildTargets.compactMap { target -> (String, BuildTarget)? in
                guard let name = target.displayName else { return nil }
                return (name, target)
            }
        )

        // Verify each expected target matches the actual target
        for expected in expectedBuildTargets {
            let displayName = try #require(expected.displayName)
            let actual = try #require(actualTargetsByName[displayName], "Missing target: \(displayName)")

            #expect(actual.id == expected.id, "ID mismatch for \(displayName)")
            #expect(actual.displayName == expected.displayName, "displayName mismatch for \(displayName)")
            #expect(actual.languageIds == expected.languageIds, "languageIds mismatch for \(displayName)")

            let actualDeps = Set(actual.dependencies.map { $0.uri })
            let expectedDeps = Set(expected.dependencies.map { $0.uri })
            #expect(actualDeps == expectedDeps, "dependencies mismatch for \(displayName)")
        }

        // Top level targets
        let expectedTopLevelTargets: [(String, TopLevelRuleType)] = [
            ("//HelloWorld:HelloWorldMacTests", .macosUnitTest),
            ("//HelloWorld:HelloWorldTests", .iosUnitTest),
            ("//HelloWorld:HelloWorld", .iosApplication),
            ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension),
            ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest),
            ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication),
            ("//HelloWorld:HelloWorldMacApp", .macosApplication),
            ("//HelloWorld:HelloWorldWatchApp", .watchosApplication),
        ]
        #expect(result.topLevelTargets.count == expectedTopLevelTargets.count)
        for (index, expected) in expectedTopLevelTargets.enumerated() {
            #expect(result.topLevelTargets[index] == expected)
        }

        // Top level label to rule map
        let expectedTopLevelLabelToRuleMap: [String: TopLevelRuleType] = [
            "//HelloWorld:HelloWorld": .iosApplication,
            "//HelloWorld:HelloWorldMacApp": .macosApplication,
            "//HelloWorld:HelloWorldMacCLIApp": .macosCommandLineApplication,
            "//HelloWorld:HelloWorldMacTests": .macosUnitTest,
            "//HelloWorld:HelloWorldTests": .iosUnitTest,
            "//HelloWorld:HelloWorldWatchApp": .watchosApplication,
            "//HelloWorld:HelloWorldWatchExtension": .watchosExtension,
            "//HelloWorld:HelloWorldWatchTests": .watchosUnitTest,
        ]
        #expect(result.topLevelLabelToRuleMap == expectedTopLevelLabelToRuleMap)

        // BSP URIs to Bazel Labels map
        #expect(
            result.bspURIsToBazelLabelsMap == [
                expandedTemplateUri: "//HelloWorld:ExpandedTemplate",
                generatedDummyUri: "//HelloWorld:GeneratedDummy",
                helloWorldLibUri: "//HelloWorld:HelloWorldLib",
                helloWorldTestsLibUri: "//HelloWorld:HelloWorldTestsLib",
                macAppLibUri: "//HelloWorld:MacAppLib",
                macAppTestsLibUri: "//HelloWorld:MacAppTestsLib",
                macCLIAppLibUri: "//HelloWorld:MacCLIAppLib",
                todoModelsUri: "//HelloWorld:TodoModels",
                todoObjCSupportUri: "//HelloWorld:TodoObjCSupport",
                todoCSupport: "//HelloWorld:TodoCSupport",
                watchAppLibUri: "//HelloWorld:WatchAppLib",
                watchAppTestsLibUri: "//HelloWorld:WatchAppTestsLib",
            ]
        )

        #expect(result.bspURIsToSrcsMap.keys.count == 12)
        #expect(result.srcToBspURIsMap.count == 23)

        // Bazel label to parent config map - verify labels map to configs
        #expect(result.bazelLabelToParentConfigMap.count == 20)

        // Helper to get parent labels for a given label through the config mapping
        func getParentLabels(for label: String) -> Set<String> {
            guard let configHash = result.bazelLabelToParentConfigMap[label],
                let parentLabels = result.configurationToTopLevelLabelsMap[configHash]
            else {
                return []
            }
            return Set(parentLabels)
        }

        #expect(
            getParentLabels(for: "//HelloWorld:ExpandedTemplate")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:GeneratedDummy")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:HelloWorldLib")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:HelloWorldTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:MacAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:MacAppTestsLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:MacCLIAppLib")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:TodoModels")
                == Set([
                    "//HelloWorld:HelloWorldMacTests",
                    "//HelloWorld:HelloWorldMacCLIApp",
                    "//HelloWorld:HelloWorldMacApp",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:TodoObjCSupport")
                == Set([
                    "//HelloWorld:HelloWorldTests",
                    "//HelloWorld:HelloWorld",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:WatchAppLib")
                == Set([
                    "//HelloWorld:HelloWorldWatchExtension",
                    "//HelloWorld:HelloWorldWatchApp",
                    "//HelloWorld:HelloWorldWatchTests",
                ])
        )
        #expect(
            getParentLabels(for: "//HelloWorld:WatchAppTestsLib")
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
        let topLevelTargets: [(String, TopLevelRuleType)] = [
            ("//HelloWorld:HelloWorld", .iosApplication),
            ("//HelloWorld:HelloWorldMacApp", .macosApplication),
            ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication),
            ("//HelloWorld:HelloWorldMacTests", .macosUnitTest),
            ("//HelloWorld:HelloWorldTests", .iosUnitTest),
            ("//HelloWorld:HelloWorldWatchApp", .watchosApplication),
            ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension),
            ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest),
        ]

        let result = try parser.processAquery(
            from: exampleAqueryOutput,
            topLevelTargets: topLevelTargets
        )

        #expect(result.topLevelLabelToConfigMap.count == 8)

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorld"]
                == BazelTargetConfigurationInfo(
                    configurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f",
                    effectiveConfigurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
                    minimumOsVersion: "17.0",
                    platform: "ios",
                    cpuArch: "sim_arm64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacApp"]
                == BazelTargetConfigurationInfo(
                    configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
                    effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
                    minimumOsVersion: "15.0",
                    platform: "darwin",
                    cpuArch: "arm64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacCLIApp"]
                == BazelTargetConfigurationInfo(
                    configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
                    effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
                    minimumOsVersion: "15.0",
                    platform: "darwin",
                    cpuArch: "arm64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacTests"]
                == BazelTargetConfigurationInfo(
                    configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
                    effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
                    minimumOsVersion: "15.0",
                    platform: "darwin",
                    cpuArch: "arm64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldTests"]
                == BazelTargetConfigurationInfo(
                    configurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f",
                    effectiveConfigurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
                    minimumOsVersion: "17.0",
                    platform: "ios",
                    cpuArch: "sim_arm64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchApp"]
                == BazelTargetConfigurationInfo(
                    configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
                    effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
                    minimumOsVersion: "7.0",
                    platform: "watchos",
                    cpuArch: "x86_64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchExtension"]
                == BazelTargetConfigurationInfo(
                    configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
                    effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
                    minimumOsVersion: "7.0",
                    platform: "watchos",
                    cpuArch: "x86_64"
                )
        )

        #expect(
            result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchTests"]
                == BazelTargetConfigurationInfo(
                    configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
                    effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
                    minimumOsVersion: "7.0",
                    platform: "watchos",
                    cpuArch: "x86_64"
                )
        )
    }
}
