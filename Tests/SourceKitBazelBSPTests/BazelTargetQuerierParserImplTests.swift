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
    private static let mockToolchainPath = "/path/to/toolchain"

    @Test
    func canProcessExampleCquery() throws {
        let parser = BazelTargetQuerierParserImpl()

        // These details are meant to match the provided cquery pb example.
        let userProvidedTargets = [
            "//HelloWorld:HelloWorld",
            "//HelloWorld:HelloWorldMacApp",
            "//HelloWorld:HelloWorldMacCLIApp",
            "//HelloWorld:HelloWorldMacTests",
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorldWatchApp",
            "//HelloWorld:HelloWorldWatchExtension",
            "//HelloWorld:HelloWorldWatchTests",
        ]

        let supportedTopLevelRuleTypes = TopLevelRuleType.allCases
        let testBundleRules = supportedTopLevelRuleTypes.compactMap { $0.testBundleRule }

        let result = try parser.processCquery(
            from: exampleCqueryOutput,
            testBundleRules: testBundleRules,
            userProvidedTargets: userProvidedTargets,
            supportedTopLevelRuleTypes: supportedTopLevelRuleTypes,
            rootUri: Self.mockRootUri,
            toolchainPath: Self.mockToolchainPath
        )

        // Pre-create URIs
        let baseDir = try URI(string: "file:///path/to/project/HelloWorld")
        let expandedTemplateUri = try URI(string: "file:///path/to/project/HelloWorld___ExpandedTemplate")
        let generatedDummyUri = try URI(string: "file:///path/to/project/HelloWorld___GeneratedDummy")
        let helloWorldLibUri = try URI(string: "file:///path/to/project/HelloWorld___HelloWorldLib")
        let helloWorldTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld___HelloWorldTestsLib")
        let macAppLibUri = try URI(string: "file:///path/to/project/HelloWorld___MacAppLib")
        let macAppTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld___MacAppTestsLib")
        let macCLIAppLibUri = try URI(string: "file:///path/to/project/HelloWorld___MacCLIAppLib")
        let todoModelsUri = try URI(string: "file:///path/to/project/HelloWorld___TodoModels")
        let todoObjCSupportUri = try URI(string: "file:///path/to/project/HelloWorld___TodoObjCSupport")
        let watchAppLibUri = try URI(string: "file:///path/to/project/HelloWorld___WatchAppLib")
        let watchAppTestsLibUri = try URI(string: "file:///path/to/project/HelloWorld___WatchAppTestsLib")

        let expectedCapabilities = BuildTargetCapabilities(canCompile: true, canTest: false, canRun: false, canDebug: false)

        #expect(result.buildTargets.count == 11)

        // Target 0: ExpandedTemplate
        #expect(result.buildTargets[0].id == BuildTargetIdentifier(uri: expandedTemplateUri))
        #expect(result.buildTargets[0].displayName == "//HelloWorld:ExpandedTemplate")
        #expect(result.buildTargets[0].baseDirectory == baseDir)
        #expect(result.buildTargets[0].tags == [.library])
        #expect(result.buildTargets[0].languageIds == [.swift])
        #expect(result.buildTargets[0].dependencies == [])
        #expect(result.buildTargets[0].capabilities == expectedCapabilities)
        #expect(result.buildTargets[0].dataKind == .sourceKit)

        // Target 1: GeneratedDummy
        #expect(result.buildTargets[1].id == BuildTargetIdentifier(uri: generatedDummyUri))
        #expect(result.buildTargets[1].displayName == "//HelloWorld:GeneratedDummy")
        #expect(result.buildTargets[1].baseDirectory == baseDir)
        #expect(result.buildTargets[1].tags == [.library])
        #expect(result.buildTargets[1].languageIds == [.swift])
        #expect(result.buildTargets[1].dependencies == [])
        #expect(result.buildTargets[1].capabilities == expectedCapabilities)
        #expect(result.buildTargets[1].dataKind == .sourceKit)

        // Target 2: HelloWorldLib
        #expect(result.buildTargets[2].id == BuildTargetIdentifier(uri: helloWorldLibUri))
        #expect(result.buildTargets[2].displayName == "//HelloWorld:HelloWorldLib")
        #expect(result.buildTargets[2].baseDirectory == baseDir)
        #expect(result.buildTargets[2].tags == [.library])
        #expect(result.buildTargets[2].languageIds == [.swift])
        #expect(result.buildTargets[2].dependencies == [
            BuildTargetIdentifier(uri: expandedTemplateUri),
            BuildTargetIdentifier(uri: generatedDummyUri),
            BuildTargetIdentifier(uri: todoModelsUri),
            BuildTargetIdentifier(uri: todoObjCSupportUri),
        ])
        #expect(result.buildTargets[2].capabilities == expectedCapabilities)
        #expect(result.buildTargets[2].dataKind == .sourceKit)

        // Target 3: HelloWorldTestsLib
        #expect(result.buildTargets[3].id == BuildTargetIdentifier(uri: helloWorldTestsLibUri))
        #expect(result.buildTargets[3].displayName == "//HelloWorld:HelloWorldTestsLib")
        #expect(result.buildTargets[3].baseDirectory == baseDir)
        #expect(result.buildTargets[3].tags == [.library])
        #expect(result.buildTargets[3].languageIds == [.swift])
        #expect(result.buildTargets[3].dependencies == [
            BuildTargetIdentifier(uri: helloWorldLibUri),
        ])
        #expect(result.buildTargets[3].capabilities == expectedCapabilities)
        #expect(result.buildTargets[3].dataKind == .sourceKit)

        // Target 4: MacAppLib
        #expect(result.buildTargets[4].id == BuildTargetIdentifier(uri: macAppLibUri))
        #expect(result.buildTargets[4].displayName == "//HelloWorld:MacAppLib")
        #expect(result.buildTargets[4].baseDirectory == baseDir)
        #expect(result.buildTargets[4].tags == [.library])
        #expect(result.buildTargets[4].languageIds == [.swift])
        #expect(result.buildTargets[4].dependencies == [
            BuildTargetIdentifier(uri: todoModelsUri),
        ])
        #expect(result.buildTargets[4].capabilities == expectedCapabilities)
        #expect(result.buildTargets[4].dataKind == .sourceKit)

        // Target 5: MacAppTestsLib
        #expect(result.buildTargets[5].id == BuildTargetIdentifier(uri: macAppTestsLibUri))
        #expect(result.buildTargets[5].displayName == "//HelloWorld:MacAppTestsLib")
        #expect(result.buildTargets[5].baseDirectory == baseDir)
        #expect(result.buildTargets[5].tags == [.library])
        #expect(result.buildTargets[5].languageIds == [.swift])
        #expect(result.buildTargets[5].dependencies == [
            BuildTargetIdentifier(uri: macAppLibUri),
        ])
        #expect(result.buildTargets[5].capabilities == expectedCapabilities)
        #expect(result.buildTargets[5].dataKind == .sourceKit)

        // Target 6: MacCLIAppLib
        #expect(result.buildTargets[6].id == BuildTargetIdentifier(uri: macCLIAppLibUri))
        #expect(result.buildTargets[6].displayName == "//HelloWorld:MacCLIAppLib")
        #expect(result.buildTargets[6].baseDirectory == baseDir)
        #expect(result.buildTargets[6].tags == [.library])
        #expect(result.buildTargets[6].languageIds == [.swift])
        #expect(result.buildTargets[6].dependencies == [
            BuildTargetIdentifier(uri: todoModelsUri),
        ])
        #expect(result.buildTargets[6].capabilities == expectedCapabilities)
        #expect(result.buildTargets[6].dataKind == .sourceKit)

        // Target 7: TodoModels
        #expect(result.buildTargets[7].id == BuildTargetIdentifier(uri: todoModelsUri))
        #expect(result.buildTargets[7].displayName == "//HelloWorld:TodoModels")
        #expect(result.buildTargets[7].baseDirectory == baseDir)
        #expect(result.buildTargets[7].tags == [.library])
        #expect(result.buildTargets[7].languageIds == [.swift])
        #expect(result.buildTargets[7].dependencies == [])
        #expect(result.buildTargets[7].capabilities == expectedCapabilities)
        #expect(result.buildTargets[7].dataKind == .sourceKit)

        // Target 8: TodoObjCSupport
        #expect(result.buildTargets[8].id == BuildTargetIdentifier(uri: todoObjCSupportUri))
        #expect(result.buildTargets[8].displayName == "//HelloWorld:TodoObjCSupport")
        #expect(result.buildTargets[8].baseDirectory == baseDir)
        #expect(result.buildTargets[8].tags == [.library])
        #expect(result.buildTargets[8].languageIds == [.objective_c])
        #expect(result.buildTargets[8].dependencies == [])
        #expect(result.buildTargets[8].capabilities == expectedCapabilities)
        #expect(result.buildTargets[8].dataKind == .sourceKit)

        // Target 9: WatchAppLib
        #expect(result.buildTargets[9].id == BuildTargetIdentifier(uri: watchAppLibUri))
        #expect(result.buildTargets[9].displayName == "//HelloWorld:WatchAppLib")
        #expect(result.buildTargets[9].baseDirectory == baseDir)
        #expect(result.buildTargets[9].tags == [.library])
        #expect(result.buildTargets[9].languageIds == [.swift])
        #expect(result.buildTargets[9].dependencies == [
            BuildTargetIdentifier(uri: todoModelsUri),
        ])
        #expect(result.buildTargets[9].capabilities == expectedCapabilities)
        #expect(result.buildTargets[9].dataKind == .sourceKit)

        // Target 10: WatchAppTestsLib
        #expect(result.buildTargets[10].id == BuildTargetIdentifier(uri: watchAppTestsLibUri))
        #expect(result.buildTargets[10].displayName == "//HelloWorld:WatchAppTestsLib")
        #expect(result.buildTargets[10].baseDirectory == baseDir)
        #expect(result.buildTargets[10].tags == [.library])
        #expect(result.buildTargets[10].languageIds == [.swift])
        #expect(result.buildTargets[10].dependencies == [
            BuildTargetIdentifier(uri: watchAppLibUri),
        ])
        #expect(result.buildTargets[10].capabilities == expectedCapabilities)
        #expect(result.buildTargets[10].dataKind == .sourceKit)

        // Top level targets
        #expect(result.topLevelTargets.count == 8)
        #expect(result.topLevelTargets[0] == ("//HelloWorld:HelloWorldMacTests", .macosUnitTest))
        #expect(result.topLevelTargets[1] == ("//HelloWorld:HelloWorldTests", .iosUnitTest))
        #expect(result.topLevelTargets[2] == ("//HelloWorld:HelloWorld", .iosApplication))
        #expect(result.topLevelTargets[3] == ("//HelloWorld:HelloWorldWatchExtension", .watchosExtension))
        #expect(result.topLevelTargets[4] == ("//HelloWorld:HelloWorldWatchTests", .watchosUnitTest))
        #expect(result.topLevelTargets[5] == ("//HelloWorld:HelloWorldMacCLIApp", .macosCommandLineApplication))
        #expect(result.topLevelTargets[6] == ("//HelloWorld:HelloWorldMacApp", .macosApplication))
        #expect(result.topLevelTargets[7] == ("//HelloWorld:HelloWorldWatchApp", .watchosApplication))

        // Available Bazel labels
        #expect(result.availableBazelLabels == Set([
            "//HelloWorld:ExpandedTemplate",
            "//HelloWorld:GeneratedDummy",
            "//HelloWorld:HelloWorldLib",
            "//HelloWorld:HelloWorldTestsLib",
            "//HelloWorld:MacAppLib",
            "//HelloWorld:MacAppTestsLib",
            "//HelloWorld:MacCLIAppLib",
            "//HelloWorld:TodoModels",
            "//HelloWorld:TodoObjCSupport",
            "//HelloWorld:WatchAppLib",
            "//HelloWorld:WatchAppTestsLib",
        ]))

        // Top level label to rule map
        #expect(result.topLevelLabelToRuleMap == [
            "//HelloWorld:HelloWorld": .iosApplication,
            "//HelloWorld:HelloWorldMacApp": .macosApplication,
            "//HelloWorld:HelloWorldMacCLIApp": .macosCommandLineApplication,
            "//HelloWorld:HelloWorldMacTests": .macosUnitTest,
            "//HelloWorld:HelloWorldTests": .iosUnitTest,
            "//HelloWorld:HelloWorldWatchApp": .watchosApplication,
            "//HelloWorld:HelloWorldWatchExtension": .watchosExtension,
            "//HelloWorld:HelloWorldWatchTests": .watchosUnitTest,
        ])

        // BSP URIs to Bazel Labels map
        #expect(result.bspURIsToBazelLabelsMap == [
            expandedTemplateUri: "//HelloWorld:ExpandedTemplate",
            generatedDummyUri: "//HelloWorld:GeneratedDummy",
            helloWorldLibUri: "//HelloWorld:HelloWorldLib",
            helloWorldTestsLibUri: "//HelloWorld:HelloWorldTestsLib",
            macAppLibUri: "//HelloWorld:MacAppLib",
            macAppTestsLibUri: "//HelloWorld:MacAppTestsLib",
            macCLIAppLibUri: "//HelloWorld:MacCLIAppLib",
            todoModelsUri: "//HelloWorld:TodoModels",
            todoObjCSupportUri: "//HelloWorld:TodoObjCSupport",
            watchAppLibUri: "//HelloWorld:WatchAppLib",
            watchAppTestsLibUri: "//HelloWorld:WatchAppTestsLib",
        ])

        #expect(result.bspURIsToSrcsMap.keys.count == 11)
        #expect(result.srcToBspURIsMap.count == 17)

        // Bazel label to parents map - compare as sets since order may vary
        #expect(result.bazelLabelToParentsMap.count == 11)
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:ExpandedTemplate"] ?? []) == Set([
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorld",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:GeneratedDummy"] ?? []) == Set([
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorld",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:HelloWorldLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorld",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:HelloWorldTestsLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldTests",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:MacAppLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldMacTests",
            "//HelloWorld:HelloWorldMacApp",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:MacAppTestsLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldMacTests",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:MacCLIAppLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldMacCLIApp",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:TodoModels"] ?? []) == Set([
            "//HelloWorld:HelloWorldMacTests",
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorld",
            "//HelloWorld:HelloWorldWatchExtension",
            "//HelloWorld:HelloWorldWatchTests",
            "//HelloWorld:HelloWorldMacCLIApp",
            "//HelloWorld:HelloWorldMacApp",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:TodoObjCSupport"] ?? []) == Set([
            "//HelloWorld:HelloWorldTests",
            "//HelloWorld:HelloWorld",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:WatchAppLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldWatchExtension",
            "//HelloWorld:HelloWorldWatchTests",
        ]))
        #expect(Set(result.bazelLabelToParentsMap["//HelloWorld:WatchAppTestsLib"] ?? []) == Set([
            "//HelloWorld:HelloWorldWatchTests",
        ]))
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

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorld"] == BazelTargetConfigurationInfo(
            configurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f",
            effectiveConfigurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
            minimumOsVersion: "17.0",
            platform: "ios",
            cpuArch: "sim_arm64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacApp"] == BazelTargetConfigurationInfo(
            configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
            effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
            minimumOsVersion: "15.0",
            platform: "darwin",
            cpuArch: "arm64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacCLIApp"] == BazelTargetConfigurationInfo(
            configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
            effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
            minimumOsVersion: "15.0",
            platform: "darwin",
            cpuArch: "arm64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldMacTests"] == BazelTargetConfigurationInfo(
            configurationName: "darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6",
            effectiveConfigurationName: "darwin_arm64-dbg-macos-arm64-min15.0",
            minimumOsVersion: "15.0",
            platform: "darwin",
            cpuArch: "arm64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldTests"] == BazelTargetConfigurationInfo(
            configurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0-applebin_ios-ST-faa571ec622f",
            effectiveConfigurationName: "ios_sim_arm64-dbg-ios-sim_arm64-min17.0",
            minimumOsVersion: "17.0",
            platform: "ios",
            cpuArch: "sim_arm64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchApp"] == BazelTargetConfigurationInfo(
            configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
            effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
            minimumOsVersion: "7.0",
            platform: "watchos",
            cpuArch: "x86_64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchExtension"] == BazelTargetConfigurationInfo(
            configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
            effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
            minimumOsVersion: "7.0",
            platform: "watchos",
            cpuArch: "x86_64"
        ))

        #expect(result.topLevelLabelToConfigMap["//HelloWorld:HelloWorldWatchTests"] == BazelTargetConfigurationInfo(
            configurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0-applebin_watchos-ST-74f4ed91ef5d",
            effectiveConfigurationName: "watchos_x86_64-dbg-watchos-x86_64-min7.0",
            minimumOsVersion: "7.0",
            platform: "watchos",
            cpuArch: "x86_64"
        ))
    }
}
