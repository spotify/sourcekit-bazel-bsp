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

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        case .invalidQueryOutput: return "Query output is not valid XML"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel queries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner

    private var queryCache = [String: [BlazeQuery_Target]]()
    private var dependencyGraphCache = [String: [String: [String]]]()

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

    func queryTargets(
        config: InitializedServerConfig,
        topLevelRuleKinds: Set<String>,
        dependencyKinds: Set<String>,
    ) throws -> [BlazeQuery_Target] {
        if topLevelRuleKinds.isEmpty || dependencyKinds.isEmpty {
            throw BazelTargetQuerierError.noKinds
        }

        let providedTargets = config.baseConfig.targets
        guard !providedTargets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        let providedTargetsQuerySet = "set(\(providedTargets.joined(separator: " ")))"

        // NOTE: important to sort for determinism
        let topLevelKindsFilter = topLevelRuleKinds.sorted().joined(separator: "|")
        let dependencyKindsFilter = dependencyKinds.sorted().joined(separator: "|")

        // Collect the top-level targets -> collect these targets' dependencies
        let topLevelTargetsQuery = """
            let topLevelTargets = kind("\(topLevelKindsFilter)", \(providedTargetsQuerySet)) in \
              $topLevelTargets \
              union \
              kind("\(dependencyKindsFilter)", deps($topLevelTargets))
            """

        let cacheKey = "QUERY_TARGETS+\(topLevelTargetsQuery)"
        logger.info("Processing query request for cache key: \(cacheKey, privacy: .public)")

        if let cached = queryCache[cacheKey] {
            logger.debug("Returning cached results for \(cacheKey, privacy: .public)")
            return cached
        }

        let cmd = "query '\(topLevelTargetsQuery)' --notool_deps --noimplicit_deps --output streamed_proto"
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        guard let targets = try? BazelProtobufBindings.parseQueryTargets(data: output) else {
            throw BazelTargetQuerierError.invalidQueryOutput
        }

        logger.debug("Parsed \(targets.count, privacy: .public) targets for cache key: \(cacheKey, privacy: .public)")
        queryCache[cacheKey] = targets

        return targets
    }

    func queryDependencyGraph(
        ofTargets targets: [String],
        forConfig config: InitializedServerConfig,
        rootUri: String,
        kinds: Set<String>
    ) throws -> [String: [String]] {
        guard !kinds.isEmpty else {
            throw BazelTargetQuerierError.noKinds
        }

        // NOTE: important to sort for determinism
        let kindsFilter = kinds.sorted().joined(separator: "|")

        var depsQuery = Self.queryDepsString(forTargets: targets)
        for target in targets {
            // Include the top-level target itself so that we can later traverse the graph correctly.
            depsQuery += " union \(target)"
        }

        let cacheKey = "\(kindsFilter)+\(depsQuery)"

        logger.info("Processing dependency graph request for \(cacheKey, privacy: .public)")

        if let cached = dependencyGraphCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        let cmd = "query \"kind('\(kindsFilter)', \(depsQuery))\" --output graph"
        let output: String = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: rootUri
        )
        let rawGraph = output.components(separatedBy: "\n").filter {
            $0.hasPrefix("  \"")
        }

        var graph = [String: [String]]()
        for line in rawGraph {
            let parts = line.components(separatedBy: "\"")
            // Example line:
            //   "//path/to/target" -> "//path/to/target2\n//path/to/target3"
            guard parts.count == 5 else {
                continue
            }
            let source = parts[1]
            let targets = parts[3].components(separatedBy: "\n")
            graph[source, default: []].append(contentsOf: targets)
        }

        dependencyGraphCache[cacheKey] = graph
        return graph
    }

    func clearCache() {
        queryCache = [:]
        dependencyGraphCache = [:]
    }
}
