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

import BazelProtobufBindings
import Foundation

// Provides the full information about a target's build info and platform,
// including the top-level parent that the target is built against.
struct BazelTargetPlatformInfo {
    let label: String
    let topLevelParentLabel: String
    let topLevelParentConfig: BazelTargetConfigurationInfo
}

// Information about a target's Bazel configuration, used to determine
// how a particular library should be compiled.
struct BazelTargetConfigurationInfo: Hashable {
    /// The configuration name as stated in the aquery,
    /// e.g. darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6
    let configurationName: String

    /// The configuration name that should actually apply when compiling a library.
    /// Only relevant when not passing --compile-top-level.
    /// e.g. darwin_arm64-dbg-macos-arm64-min15.0
    let effectiveConfigurationName: String

    let minimumOsVersion: String
    let platform: String
    let cpuArch: String
    let sdkName: String
}
