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

import ArgumentParser

// The list of **top-level rules** we know how to process in the BSP.
public enum TopLevelRuleType: String, CaseIterable, ExpressibleByArgument, Sendable {
    case iosApplication = "ios_application"
    case iosUnitTest = "ios_unit_test"
    case iosUiTest = "ios_ui_test"
    case watchosApplication = "watchos_application"
    case watchosUnitTest = "watchos_unit_test"
    case watchosUiTest = "watchos_ui_test"
    case macosApplication = "macos_application"
    case macosCommandLineApplication = "macos_command_line_application"
    case macosUnitTest = "macos_unit_test"
    case macosUiTest = "macos_ui_test"
    case tvosApplication = "tvos_application"
    case tvosUnitTest = "tvos_unit_test"
    case tvosUiTest = "tvos_ui_test"
    case visionosApplication = "visionos_application"
    case visionosUnitTest = "visionos_unit_test"
    case visionosUiTest = "visionos_ui_test"

    var platform: String {
        switch self {
        case .iosApplication: return "ios"
        case .iosUnitTest: return "ios"
        case .iosUiTest: return "ios"
        case .watchosApplication: return "watchos"
        case .watchosUnitTest: return "watchos"
        case .watchosUiTest: return "watchos"
        case .macosApplication: return "macos"
        case .macosCommandLineApplication: return "macos"
        case .macosUnitTest: return "macos"
        case .macosUiTest: return "macos"
        case .tvosApplication: return "tvos"
        case .tvosUnitTest: return "tvos"
        case .tvosUiTest: return "tvos"
        case .visionosApplication: return "visionos"
        case .visionosUnitTest: return "visionos"
        case .visionosUiTest: return "visionos"
        }
    }

    var isTestRule: Bool {
        switch self {
        case .iosUnitTest, .iosUiTest, .watchosUnitTest, .watchosUiTest, .macosUnitTest, .macosUiTest, .tvosUnitTest,
            .tvosUiTest, .visionosUnitTest, .visionosUiTest:
            return true
        default: return false
        }
    }

    // FIXME: Not the best way to handle this as we need to eventually
    // handle device builds as well
    var sdkName: String {
        switch self {
        case .iosApplication: return "iphonesimulator"
        case .iosUnitTest: return "iphonesimulator"
        case .iosUiTest: return "iphonesimulator"
        case .watchosApplication: return "watchsimulator"
        case .watchosUnitTest: return "watchsimulator"
        case .watchosUiTest: return "watchsimulator"
        case .macosApplication: return "macosx"
        case .macosCommandLineApplication: return "macosx"
        case .macosUnitTest: return "macosx"
        case .macosUiTest: return "macosx"
        case .tvosApplication: return "appletvsimulator"
        case .tvosUnitTest: return "appletvsimulator"
        case .tvosUiTest: return "appletvsimulator"
        case .visionosApplication: return "xrsimulator"
        case .visionosUnitTest: return "xrsimulator"
        case .visionosUiTest: return "xrsimulator"
        }
    }

    // FIXME: Not the best way to handle this as we need to eventually
    // handle device builds as well
    var cpu: String {
        switch self {
        case .iosApplication: return "sim_arm64"
        case .iosUnitTest: return "sim_arm64"
        case .iosUiTest: return "sim_arm64"
        case .watchosApplication: return "x86_64"
        case .watchosUnitTest: return "x86_64"
        case .watchosUiTest: return "x86_64"
        case .macosApplication: return "arm64"
        case .macosCommandLineApplication: return "arm64"
        case .macosUnitTest: return "arm64"
        case .macosUiTest: return "arm64"
        case .tvosApplication: return "sim_arm64"
        case .tvosUnitTest: return "sim_arm64"
        case .tvosUiTest: return "sim_arm64"
        case .visionosApplication: return "sim_arm64"
        case .visionosUnitTest: return "sim_arm64"
        case .visionosUiTest: return "sim_arm64"
        }
    }

    // Not the same as the platform (see macOS cases)
    var cpuPrefix: String {
        switch self {
        case .iosApplication: return "ios"
        case .iosUnitTest: return "ios"
        case .iosUiTest: return "ios"
        case .watchosApplication: return "watchos"
        case .watchosUnitTest: return "watchos"
        case .watchosUiTest: return "watchos"
        case .macosApplication: return "darwin"
        case .macosCommandLineApplication: return "darwin"
        case .macosUnitTest: return "darwin"
        case .macosUiTest: return "darwin"
        case .tvosApplication: return "tvos"
        case .tvosUnitTest: return "tvos"
        case .tvosUiTest: return "tvos"
        case .visionosApplication: return "visionos"
        case .visionosUnitTest: return "visionos"
        case .visionosUiTest: return "visionos"
        }
    }

    var cpuFlagName: String {
        switch self {
        case .iosApplication: return "multi_cpus"
        case .iosUnitTest: return "multi_cpus"
        case .iosUiTest: return "multi_cpus"
        case .watchosApplication: return "cpus"
        case .watchosUnitTest: return "cpus"
        case .watchosUiTest: return "cpus"
        case .macosApplication: return "cpus"
        case .macosCommandLineApplication: return "cpus"
        case .macosUnitTest: return "cpus"
        case .macosUiTest: return "cpus"
        case .tvosApplication: return "cpus"
        case .tvosUnitTest: return "cpus"
        case .tvosUiTest: return "cpus"
        case .visionosApplication: return "cpus"
        case .visionosUnitTest: return "cpus"
        case .visionosUiTest: return "cpus"
        }
    }
}
