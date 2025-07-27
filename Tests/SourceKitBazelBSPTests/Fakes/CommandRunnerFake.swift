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

enum CommandRunnerFakeError: Error, LocalizedError {
    case unregisteredCommand(String, String?)

    var errorDescription: String? {
        switch self {
        case .unregisteredCommand(let cmd, let cwd): return "Unexpected command: \(cmd) (cwd: \(cwd ?? "nil"))"
        }
    }
}

final class CommandRunnerFake: CommandRunner {

    private(set) var commands: [(command: String, cwd: String?)] = []
    private var responses: [String: String] = [:]
    private var errors: [String: Error] = [:]

    func setResponse(for command: String, cwd: String? = nil, response: String) {
        responses[key(for: command, cwd: cwd)] = response
    }

    func setError(for command: String, cwd: String? = nil, error: Error) { errors[key(for: command, cwd: cwd)] = error }

    func run(_ cmd: String, cwd: String?) throws -> String {
        commands.append((command: cmd, cwd: cwd))

        let cacheKey = key(for: cmd, cwd: cwd)
        if let error = errors[cacheKey] { throw error }

        guard let response = responses[cacheKey] else { throw CommandRunnerFakeError.unregisteredCommand(cmd, cwd) }

        return response
    }

    private func key(for command: String, cwd: String?) -> String { return command + "|" + (cwd ?? "nil") }

    func reset() {
        commands.removeAll()
        responses.removeAll()
        errors.removeAll()
    }
}
