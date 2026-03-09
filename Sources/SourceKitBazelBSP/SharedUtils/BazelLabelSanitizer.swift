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

/// Sanitizes Bazel labels into safe identifiers for use as output group names or target names.
enum BazelLabelSanitizer {
    /// Sanitizes a Bazel label with the given prefix.
    /// Strips leading `//`, replaces `/`, `:`, `-`, `.` with `_`.
    static func sanitize(_ label: String, prefix: String) -> String {
        var sanitized = label
        if sanitized.hasPrefix("//") {
            sanitized = String(sanitized.dropFirst(2))
        }
        return prefix
            + sanitized
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    /// Converts a Bazel label to a wrapper target name.
    /// Example: //path/to/app:MyApp -> wrapper_path_to_app_MyApp
    static func wrapperTargetName(forLabel label: String) -> String {
        return sanitize(label, prefix: "wrapper_")
    }
}
