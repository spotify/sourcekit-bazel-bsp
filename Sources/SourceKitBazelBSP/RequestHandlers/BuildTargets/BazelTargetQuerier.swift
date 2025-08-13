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

enum BazelTargetQuerierError: Error, LocalizedError {
    case noKinds
    case noTargets
    case invalidQueryOutput
    case unsupportedTopLevelRuleType(String, String)

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        case .invalidQueryOutput: return "Query output is not valid XML"
        case .unsupportedTopLevelRuleType(let ruleType, let target): return "Unsupported top-level rule type: \(ruleType) for target: \(target)"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel queries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner
    private var queryCache = [String: [BlazeQuery_Target]]()

    static func queryDepsString(forTargets targets: [String]) -> String {
        var query = ""
        for target in targets {
            if query == "" {
                query = "deps(\(target))"
            } else {
                query += " union deps(\(target))"
            }
        }
        return query
    }

    init(commandRunner: CommandRunner = ShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func queryTopLevelRuleTypes(
        forConfig config: BaseServerConfig,
        rootUri: String,
    ) throws -> [(String, TopLevelRuleType)] {
        let targetQuery = config.targets.joined(separator: " union ")
        let cmd = "query \"kind('rule', \(targetQuery))\" --output label_kind"
        let output: String = try commandRunner.run(config.bazelWrapper + " " + cmd, cwd: rootUri)
        let parsed = output.components(separatedBy: "\n")
        var topLevelTargetData: [(String, TopLevelRuleType)] = []
        for line in parsed {
            let parts = line.split(separator: " ")
            let kind = String(parts[0])
            let target = String(parts[2])
            guard let ruleType = TopLevelRuleType(rawValue: kind) else {
                throw BazelTargetQuerierError.unsupportedTopLevelRuleType(kind, target)
            }
            topLevelTargetData.append((target, ruleType))
        }
        return topLevelTargetData
    }

    func queryTargetDependencies(
        forTargets targets: [String],
        forConfig config: BaseServerConfig,
        rootUri: String,
        kinds: Set<String>
    ) throws -> [BlazeQuery_Target] {
        guard !kinds.isEmpty else {
            throw BazelTargetQuerierError.noKinds
        }

        guard !targets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        let kindsFilter = kinds.sorted().joined(separator: "|")
        let depsQuery = Self.queryDepsString(forTargets: targets)
        let cacheKey = "\(kindsFilter)+\(depsQuery)"

        logger.info("Processing query request for \(cacheKey)")

        if let cached = queryCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        // We run this one on the main output base since it's not related to the actual indexing bits
        let cmd = "query \"kind('\(kindsFilter)', \(depsQuery))\" --output streamed_proto"
        let output = try commandRunner.run(config.bazelWrapper + " " + cmd, cwd: rootUri)

        logger.debug("Finished querying, building result Protobuf")

        guard let targets = try? BazelProtobufBindings.parseQueryTargets(data: output) else {
            throw BazelTargetQuerierError.invalidQueryOutput
        }

        logger.debug("Parsed \(targets.count) targets")
        queryCache[cacheKey] = targets

        return targets
    }

    func queryDependencyLabels(
        ofTarget target: String,
        forConfig config: BaseServerConfig,
        rootUri: String,
        kinds: Set<String>
    ) throws -> [String] {
        guard !kinds.isEmpty else {
            throw BazelTargetQuerierError.noKinds
        }

        let kindsFilter = kinds.sorted().joined(separator: "|")
        let cmd = "query \"kind('\(kindsFilter)', deps(\(target)))\" --output label"
        let output: String = try commandRunner.run(config.bazelWrapper + " " + cmd, cwd: rootUri)
        return output.components(separatedBy: "\n")
    }

    func clearCache() {
        queryCache = [:]
    }
}
