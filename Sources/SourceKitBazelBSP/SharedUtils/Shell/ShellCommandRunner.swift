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

enum ShellCommandRunnerError: LocalizedError {
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let stderr): return "Command `\(command)` failed: \(stderr)"
        }
    }
}

struct ShellCommandRunner: CommandRunner {
    func run(_ cmd: String, cwd: String?, stdout: Pipe, stderr: Pipe) throws -> RunningProcess {
        let process = Process()

        process.standardOutput = stdout
        process.standardError = stderr

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        process.arguments = ["-c", cmd]
        process.standardInput = nil

        logger.info("Running shell: \(cmd)")
        try process.run()

        let runningProcess = RunningProcess(
            cmd: cmd,
            stdout: stdout,
            stderr: stderr,
            wrappedProcess: process
        )

        return runningProcess
    }
}
