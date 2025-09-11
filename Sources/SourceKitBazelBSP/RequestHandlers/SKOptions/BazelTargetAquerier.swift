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

import BazelProtobufBindings
import Foundation

private let logger = makeFileLevelBSPLogger()

enum BazelTargetAquerierError: Error, LocalizedError {
    case noMnemonics

    var errorDescription: String? {
        switch self {
        case .noMnemonics: return "A list of mnemonics is necessary to aquery targets"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel _action queries_.
/// FIXME: This is separate from BazelTargetQuerier because of the different output types, but we can unify these.
final class BazelTargetAquerier {

    private let commandRunner: CommandRunner
    private var queryCache = [String: AqueryResult]()

    init(commandRunner: CommandRunner = ShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func aquery(
        targets: [String],
        config: InitializedServerConfig,
        mnemonics: Set<String>,
        additionalFlags: [String]
    ) throws -> AqueryResult {
        guard !mnemonics.isEmpty else {
            throw BazelTargetAquerierError.noMnemonics
        }

        let mnemonicsFilter = mnemonics.sorted().joined(separator: "|")
        let depsQuery = BazelTargetQuerier.queryDepsString(forTargets: targets)

        let otherFlags = additionalFlags.joined(separator: " ") + " --output proto"
        let cmd = "aquery \"mnemonic('\(mnemonicsFilter)', \(depsQuery))\" \(otherFlags)"
        logger.info("Processing aquery request for \(targets)")

        if let cached = queryCache[cmd] {
            logger.debug("Returning cached results")
            return cached
        }

        // Run the aquery with the special index flags since that's what we will build with.
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.aqueryOutputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        let parsedOutput = try BazelProtobufBindings.parseActionGraph(data: output)
        let aqueryResult = try AqueryResult(results: parsedOutput)

        logger.debug("ActionGraphContainer parsed \(parsedOutput.actions.count) actions")

        queryCache[cmd] = aqueryResult

        return aqueryResult
    }

    func clearCache() {
        queryCache = [:]
    }
}
