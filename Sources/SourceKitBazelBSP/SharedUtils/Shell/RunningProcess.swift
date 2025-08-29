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

public struct RunningProcess: Sendable {
    let cmd: String
    let stdout: Pipe
    let stderr: Pipe
    let wrappedProcess: Process

    public init(cmd: String, stdout: Pipe, stderr: Pipe, wrappedProcess: Process) {
        self.cmd = cmd
        self.stdout = stdout
        self.stderr = stderr
        self.wrappedProcess = wrappedProcess
    }

    public func output<T: DataConvertible>() throws -> T {
        // Drain stdout/err first to avoid deadlocking when the output is buffered.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        wrappedProcess.waitUntilExit()

        guard wrappedProcess.terminationStatus == 0 else {
            logger.debug("Command failed: \(cmd)")
            let stderrString: String = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            throw ShellCommandRunnerError.failed(cmd, stderrString)
        }

        return T.convert(from: data)
    }

    public func terminate() {
        wrappedProcess.terminate()
    }
}
