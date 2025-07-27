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

protocol CommandRunner {
    func run(_ cmd: String, cwd: String?) throws -> String
}

extension CommandRunner {
    func run(_ cmd: String) throws -> String { try run(cmd, cwd: nil) }
}

// MARK: Bazel-related helpers

extension CommandRunner {
    func bazel(baseConfig: BaseServerConfig, rootUri: String, cmd: String) throws -> String {
        try run(baseConfig.bazelWrapper + " " + cmd, cwd: rootUri)
    }

    /// A regular bazel command, but at this BSP's special output base and taking into account the special index flags.
    func bazelIndexAction(initializedConfig: InitializedServerConfig, cmd: String) throws -> String {
        return try bazelIndexAction(
            baseConfig: initializedConfig.baseConfig,
            outputBase: initializedConfig.outputBase,
            cmd: cmd,
            rootUri: initializedConfig.rootUri
        )
    }

    /// A regular bazel command, but at this BSP's special output base and taking into account the special index flags.
    func bazelIndexAction(
        baseConfig: BaseServerConfig,
        outputBase: String,
        cmd: String,
        rootUri: String,
    ) throws -> String {
        let indexFlags = baseConfig.indexFlags
        let additionalFlags: String
        if indexFlags.isEmpty {
            additionalFlags = ""
        } else {
            additionalFlags = indexFlags.map { " \($0)" }.joined(separator: "")
        }
        let cmd = "--output_base=\(outputBase) \(cmd)\(additionalFlags)"
        return try bazel(baseConfig: baseConfig, rootUri: rootUri, cmd: cmd)
    }
}
