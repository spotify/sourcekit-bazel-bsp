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

private let logger = makeFileLevelBSPLogger()

public protocol CommandRunner: Sendable {
    func run(_ cmd: String, cwd: String?, stdout: Pipe, stderr: Pipe) throws -> RunningProcess
}

extension CommandRunner {
    func run(
        _ cmd: String,
        cwd: String? = nil,
        stdout: Pipe = Pipe(),
        stderr: Pipe = Pipe(),
    ) throws -> RunningProcess {
        return try run(cmd, cwd: cwd, stdout: stdout, stderr: stderr)
    }

    func run<T: DataConvertible>(
        _ cmd: String,
        cwd: String? = nil,
        stdout: Pipe = Pipe(),
        stderr: Pipe = Pipe(),
    ) throws -> T {
        let process = try run(cmd, cwd: cwd, stdout: stdout, stderr: stderr)
        return try process.result()
    }
}

// MARK: Bazel-related helpers

extension CommandRunner {
    func bazel(baseConfig: BaseServerConfig, rootUri: String, cmd: String) throws -> RunningProcess {
        try run(baseConfig.bazelWrapper + " " + cmd, cwd: rootUri)
    }

    func bazel<T: DataConvertible>(baseConfig: BaseServerConfig, rootUri: String, cmd: String) throws -> T {
        let process = try bazel(baseConfig: baseConfig, rootUri: rootUri, cmd: cmd)
        return try process.result()
    }

    /// A regular bazel command, but at this BSP's special output base and taking into account the special index flags.
    func bazelIndexAction(
        baseConfig: BaseServerConfig,
        outputBase: String,
        cmd: String,
        rootUri: String,
        additionalFlags: [String] = [],
        additionalStartupFlags: [String] = []
    ) throws -> RunningProcess {
        let indexFlags = baseConfig.indexFlags
        let additionalFlags = additionalFlags.map { " \($0)" }
        let flagsString: String
        if indexFlags.isEmpty {
            flagsString = additionalFlags.joined(separator: "")
        } else {
            flagsString = (additionalFlags + indexFlags.map { " \($0)" }).joined(separator: "")
        }
        let startupFlagsString: String
        if additionalStartupFlags.isEmpty {
            startupFlagsString = ""
        } else {
            startupFlagsString = " " + additionalStartupFlags.joined(separator: " ")
        }
        let cmd = "--output_base=\(outputBase)\(startupFlagsString) \(cmd)\(flagsString)"
        return try bazel(baseConfig: baseConfig, rootUri: rootUri, cmd: cmd)
    }

    /// A regular bazel command, but at this BSP's special output base and taking into account the special index flags.
    func bazelIndexAction<T: DataConvertible>(
        baseConfig: BaseServerConfig,
        outputBase: String,
        cmd: String,
        rootUri: String,
        additionalFlags: [String] = [],
        additionalStartupFlags: [String] = []
    ) throws -> T {
        let process = try bazelIndexAction(
            baseConfig: baseConfig,
            outputBase: outputBase,
            cmd: cmd,
            rootUri: rootUri,
            additionalFlags: additionalFlags,
            additionalStartupFlags: additionalStartupFlags
        )
        return try process.result()
    }
}

public protocol DataConvertible {
    static func convert(from data: Data) -> Self
}

extension String: DataConvertible {
    public static func convert(from data: Data) -> Self {
        let str = String(data: data, encoding: .utf8) ?? ""
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Data: DataConvertible {
    public static func convert(from data: Data) -> Self {
        return data
    }
}
