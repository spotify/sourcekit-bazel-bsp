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

@testable import SourceKitBazelBSP

final class CommandRunnerFake: CommandRunner {

    private(set) var commands: [(command: String, cwd: String?)] = []
    private var responses: [String: String] = [:]
    private var errors: [String: Error] = [:]

    func setResponse(for command: String, cwd: String? = nil, response: String) {
        responses[command + "|" + (cwd ?? "nil")] = response
    }

    func setError(for command: String, cwd: String? = nil, error: Error) {
        errors[command + "|" + (cwd ?? "nil")] = error
    }

    func run(_ cmd: String, cwd: String?) throws -> String {
        commands.append((command: cmd, cwd: cwd))

        if let error = errors[cmd + "|" + (cwd ?? "nil")] {
            throw error
        }

        return responses[cmd + "|" + (cwd ?? "nil")]
            ?? "Response/error not registered for command: \(cmd)"
    }

    func reset() {
        commands.removeAll()
        responses.removeAll()
        errors.removeAll()
    }
}
