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
    case iosAppClip = "ios_app_clip"
    case iosExtension = "ios_extension"
    case iosUnitTest = "ios_unit_test"
    case iosUiTest = "ios_ui_test"
    case iosBuildTest = "ios_build_test"
    case watchosApplication = "watchos_application"
    case watchosExtension = "watchos_extension"
    case watchosUnitTest = "watchos_unit_test"
    case watchosUiTest = "watchos_ui_test"
    case watchosBuildTest = "watchos_build_test"
    case macosApplication = "macos_application"
    case macosExtension = "macos_extension"
    case macosCommandLineApplication = "macos_command_line_application"
    case macosUnitTest = "macos_unit_test"
    case macosUiTest = "macos_ui_test"
    case macosBuildTest = "macos_build_test"
    case tvosApplication = "tvos_application"
    case tvosExtension = "tvos_extension"
    case tvosUnitTest = "tvos_unit_test"
    case tvosUiTest = "tvos_ui_test"
    case tvosBuildTest = "tvos_build_test"
    case visionosApplication = "visionos_application"
    case visionosExtension = "visionos_extension"
    case visionosUnitTest = "visionos_unit_test"
    case visionosUiTest = "visionos_ui_test"
    case visionosBuildTest = "visionos_build_test"

    static var testBundleRuleSuffix: String {
        return ".__internal__.__test_bundle"
    }

    // Some test rule types inject a bundle target between the rule and its dependencies.
    // We need to keep track of them to be able to parse those rules properly.
    // If the rule does not generate a bundle target, returns nil.
    var testBundleRule: String? {
        switch self {
        case .iosUnitTest: return "_ios_internal_unit_test_bundle"
        case .iosUiTest: return "_ios_internal_ui_test_bundle"
        case .watchosUnitTest: return "_watchos_internal_unit_test_bundle"
        case .watchosUiTest: return "_watchos_internal_ui_test_bundle"
        case .macosUnitTest: return "_macos_internal_unit_test_bundle"
        case .macosUiTest: return "_macos_internal_ui_test_bundle"
        case .tvosUnitTest: return "_tvos_internal_unit_test_bundle"
        case .tvosUiTest: return "_tvos_internal_ui_test_bundle"
        case .visionosUnitTest: return "_visionos_internal_unit_test_bundle"
        case .visionosUiTest: return "_visionos_internal_ui_test_bundle"
        default: return nil
        }
    }

    var isBuildTestRule: Bool {
        switch self {
        case .iosBuildTest: return true
        case .watchosBuildTest: return true
        case .macosBuildTest: return true
        case .tvosBuildTest: return true
        case .visionosBuildTest: return true
        default: return false
        }
    }

    // FIXME: Not the best way to handle this as we need to eventually
    // handle device builds as well
    var sdkName: String {
        switch self {
        case .iosApplication: return "iphonesimulator"
        case .iosAppClip: return "iphonesimulator"
        case .iosExtension: return "iphonesimulator"
        case .iosUnitTest: return "iphonesimulator"
        case .iosUiTest: return "iphonesimulator"
        case .iosBuildTest: return "iphonesimulator"
        case .watchosApplication: return "watchsimulator"
        case .watchosExtension: return "watchsimulator"
        case .watchosUnitTest: return "watchsimulator"
        case .watchosUiTest: return "watchsimulator"
        case .watchosBuildTest: return "watchsimulator"
        case .macosApplication: return "macosx"
        case .macosExtension: return "macosx"
        case .macosCommandLineApplication: return "macosx"
        case .macosUnitTest: return "macosx"
        case .macosUiTest: return "macosx"
        case .macosBuildTest: return "macosx"
        case .tvosApplication: return "appletvsimulator"
        case .tvosExtension: return "appletvsimulator"
        case .tvosUnitTest: return "appletvsimulator"
        case .tvosUiTest: return "appletvsimulator"
        case .tvosBuildTest: return "appletvsimulator"
        case .visionosApplication: return "xrsimulator"
        case .visionosExtension: return "xrsimulator"
        case .visionosUnitTest: return "xrsimulator"
        case .visionosUiTest: return "xrsimulator"
        case .visionosBuildTest: return "xrsimulator"
        }
    }
}
