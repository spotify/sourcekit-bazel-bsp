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

enum BazelTargetAquerierError: Error, LocalizedError {
    case noMnemonics
    case noTargets

    var errorDescription: String? {
        switch self {
        case .noMnemonics: return "A list of mnemonics is necessary to aquery targets"
        case .noTargets: return "A list of targets is necessary to run aqueries"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel _action queries_.
/// FIXME: This is separate from BazelTargetQuerier because of the different output types, but we can unify these.
///
/// FIXME: Currently uses text outputs, should use proto instead so that we can organize and test this properly.
final class BazelTargetAquerier {

    private let commandRunner: CommandRunner
    private var queryCache = [String: String]()

    init(commandRunner: CommandRunner = ShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func aquery(
        forConfig config: InitializedServerConfig,
        mnemonics: Set<String>,
        additionalFlags: [String]
    ) throws -> String {
        guard !mnemonics.isEmpty else {
            throw BazelTargetAquerierError.noMnemonics
        }

        let targets = config.baseConfig.targets
        guard !targets.isEmpty else {
            throw BazelTargetAquerierError.noTargets
        }

        let mnemonicsFilter = mnemonics.sorted().joined(separator: "|")
        let depsQuery = BazelTargetQuerier.queryDepsString(forTargets: targets)

        let otherFlags = additionalFlags.joined(separator: " ")
        let cmd = "aquery \"mnemonic('\(mnemonicsFilter)', \(depsQuery))\" \(otherFlags)"
        logger.info("Processing root aquery request")

        if let cached = queryCache[cmd] {
            logger.debug("Returning cached results")
            return cached
        }

        // Run the aquery on the special index output base since that's where we will build at.
        let output = try commandRunner.bazelIndexAction(initializedConfig: config, cmd: cmd)

        queryCache[cmd] = output

        return output
    }

    func clearCache() {
        queryCache = [:]
    }
}
