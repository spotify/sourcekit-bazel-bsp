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

public protocol CommandLineProcess: Sendable {
    var terminationStatus: Int32 { get }
    func waitUntilExit()
    func terminate()
    func setTerminationHandler(_ handler: @escaping @Sendable (Int32) -> Void)
}

extension Process: CommandLineProcess {
    public func setTerminationHandler(_ handler: @escaping @Sendable (Int32) -> Void) {
        self.terminationHandler = { process in
            handler(process.terminationStatus)
        }
    }
}

public struct RunningProcess: Sendable {
    let cmd: String
    let stdout: Pipe
    let stderr: Pipe
    let wrappedProcess: CommandLineProcess

    public init(cmd: String, stdout: Pipe, stderr: Pipe, wrappedProcess: CommandLineProcess) {
        self.cmd = cmd
        self.stdout = stdout
        self.stderr = stderr
        self.wrappedProcess = wrappedProcess
    }

    public func output<T: DataConvertible>() throws -> T {
        let dataQueue = DispatchQueue(label: cmd)
        var stdoutData: Data = Data()
        var stderrData = Data()

        stdout.fileHandleForReading.readabilityHandler = { stdoutFileHandle in
            let outData = stdoutFileHandle.availableData
            if outData.count > 0 {
                dataQueue.async {
                    stdoutData.append(outData)
                }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { stderrFileHandle in
            let outData = stderrFileHandle.availableData
            if outData.count > 0 {
                dataQueue.async {
                    stderrData.append(outData)
                }
            }
        }

        wrappedProcess.waitUntilExit()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        dataQueue.async {
            stdout.fileHandleForReading.closeFile()
            stderr.fileHandleForReading.closeFile()
        }

        guard wrappedProcess.terminationStatus == 0 else {
            logger.debug("Command failed: \(cmd)")
            let stderrString: String = dataQueue.sync {
                String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            }
            throw ShellCommandRunnerError.failed(cmd, stderrString)
        }

        return dataQueue.sync { T.convert(from: stdoutData) }
    }

    public func terminate() {
        wrappedProcess.terminate()
    }

    public func setTerminationHandler(_ handler: @escaping @Sendable (Int32) -> Void) {
        wrappedProcess.setTerminationHandler(handler)
    }
}
