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

import ArgumentParser
import SourceKitBazelBSP

private let logger = makeFileLevelBSPLogger()

@main
struct SourcekitBazelBspCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Build Server Protocol server for Bazel, for usage with SourceKit-LSP.",
        version: sourcekitBazelBSPVersion,
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

extension SourcekitBazelBspCommand {
    static func main() throws {
        var command: ParsableCommand
        do {
            command = try parseAsRoot()
        } catch {
            logger.fault("Failed to parse arguments for the BSP: \(error, privacy: .public)")
            exit(withError: error)
        }
        do {
            try command.run()
        } catch {
            logger.fault("Failed to initialize the BSP: \(error, privacy: .public)")
            exit(withError: error)
        }
    }
}
