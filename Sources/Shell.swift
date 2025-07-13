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

enum ShellError: LocalizedError {
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let stderr):
            return "Command `\(command)` failed: \(stderr)"
        }
    }
}

func shell(
    _ cmd: String,
    cwd: String? = nil,
) throws -> String {
    let task = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    task.standardOutput = stdout
    task.standardError = stderr
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    if let cwd {
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }

    task.arguments = ["-c", cmd]
    task.standardInput = nil
    logger.info("Running shell: \(cmd, privacy: .public)")

    try task.run()

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    // we have to do this AFTER reading the output, otherwise this never returns
    // for some reason on some commands
    task.waitUntilExit()

    guard task.terminationStatus == 0 else {
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrString: String = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
        throw ShellError.failed(cmd, stderrString)
    }

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}
