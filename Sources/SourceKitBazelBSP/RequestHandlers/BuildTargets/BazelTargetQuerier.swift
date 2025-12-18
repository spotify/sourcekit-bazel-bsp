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

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel queries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner

    private var queryCache = [String: ([BlazeQuery_Target], [BlazeQuery_Target])]()
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
        dependencyKinds: Set<String>,
    ) throws -> (rules: [BlazeQuery_Target], srcs: [BlazeQuery_Target]) {
        if dependencyKinds.isEmpty {
            throw BazelTargetQuerierError.noKinds
        }

        let providedTargets = config.baseConfig.targets
        guard !providedTargets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        let providedTargetsQuerySet = "set(\(providedTargets.joined(separator: " ")))"

        // NOTE: important to sort for determinism
        let dependencyKindsFilter = dependencyKinds.sorted().joined(separator: "|")

        // Collect the top-level targets -> collect these targets' dependencies
        let topLevelTargetsQuery = """
            let topLevelTargets = kind("rule", \(providedTargetsQuerySet)) in \
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

        // We use cquery here because we are interested on what's actually compiled.
        // Also, this shares more analysis cache compared to the regular query.
        let cmd = "cquery '\(topLevelTargetsQuery)' --notool_deps --noimplicit_deps --output proto"
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        let queryResult = try BazelProtobufBindings.parseCqueryResult(data: output)

        let targets = queryResult.results.map { $0.target }

        logger.debug("Parsed \(targets.count, privacy: .public) targets for cache key: \(cacheKey, privacy: .public)")

        var rules = [BlazeQuery_Target]()
        var srcs = [BlazeQuery_Target]()
        for target in targets {
            if target.type == .rule {
                rules.append(target)
            } else if target.type == .sourceFile {
                srcs.append(target)
            } else {
                logger.error("Parsed unexpected target type: \(target.type.rawValue)")
            }
        }

        // Sort for determinism
        rules = rules.sorted(by: { $0.rule.name < $1.rule.name })
        srcs = srcs.sorted(by: { $0.sourceFile.name < $1.sourceFile.name })

        let result = (rules, srcs)
        queryCache[cacheKey] = result
        return result
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

        // We use cquery here because we are interested on what's actually compiled.
        // Also, this shares more analysis cache compared to the regular query.
        let cmd = "cquery \"kind('\(kindsFilter)', \(depsQuery))\" --output graph"
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
            //   "//path/to/target (abc)" -> "//path/to/target2 (abc)\n//path/to/target3 (abc)"
            guard parts.count == 5 else {
                continue
            }
            let source = parts[1].components(separatedBy: " (")[0]
            let targets = parts[3].components(separatedBy: "\n").map {
                $0.components(separatedBy: " (")[0]
            }
            graph[source, default: []].append(contentsOf: targets)
        }

        // Sort for determinism
        graph = graph.mapValues { $0.sorted() }

        dependencyGraphCache[cacheKey] = graph
        return graph
    }

    func clearCache() {
        queryCache = [:]
        dependencyGraphCache = [:]
    }
}
