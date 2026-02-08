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

enum BazelTargetQuerierError: Error, LocalizedError {
    case noKinds
    case noTargets
    case noTopLevelRuleTypes
    case noMnemonics

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        case .noTopLevelRuleTypes: return "A list of top-level rule types is necessary to query targets"
        case .noMnemonics: return "A list of mnemonics is necessary to aquery targets"
        }
    }
}

/// Abstraction to handle and cache the results of bazel cqueries and aqueries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner
    private let parser: BazelTargetQuerierParser
    private var cqueryCache = [String: ProcessedCqueryResult]()
    private var aqueryCache = [String: ProcessedAqueryResult]()

    private static func queryDepsString(forTargets targets: [String]) -> String {
        return unionString(forTargets: targets.map { "deps(\($0))" })
    }

    private static func unionString(forTargets targets: [String]) -> String {
        return targets.joined(separator: " union ")
    }

    init(
        commandRunner: CommandRunner = ShellCommandRunner(),
        parser: BazelTargetQuerierParser = BazelTargetQuerierParserImpl()
    ) {
        self.commandRunner = commandRunner
        self.parser = parser
    }

    /// Runs a cquery across the codebase based on the user's provided list of top level targets,
    /// listing all of their dependencies and source files.
    func cqueryTargets(
        config: InitializedServerConfig,
        supportedDependencyRuleTypes: [DependencyRuleType],
        supportedTopLevelRuleTypes: [TopLevelRuleType],
    ) throws -> ProcessedCqueryResult {
        if supportedDependencyRuleTypes.isEmpty {
            throw BazelTargetQuerierError.noKinds
        }
        if supportedTopLevelRuleTypes.isEmpty {
            throw BazelTargetQuerierError.noTopLevelRuleTypes
        }

        let userProvidedTargets = config.baseConfig.targets
        guard !userProvidedTargets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        var dependencyKindsFilter = supportedDependencyRuleTypes.map { $0.rawValue }
        // We need to also use the `alias` mnemonic for this query to work properly.
        // This is because --output proto doesn't follow the aliases automatically,
        // so we need this info to do it ourselves.
        dependencyKindsFilter.append("alias")
        // Always fetch source information.
        // FIXME: Need to also handle `generated file`
        dependencyKindsFilter.append("source file")
        // If we're searching for test rules, we need to also include their test bundle rules.
        // Otherwise we won't be able to map test dependencies back to their top level parents.
        let testBundleRules = supportedTopLevelRuleTypes.compactMap { $0.testBundleRule }
        dependencyKindsFilter.append(contentsOf: testBundleRules)

        let topLevelKindsFilter = supportedTopLevelRuleTypes.map { $0.rawValue }
        let topLevelDepsFilter = Self.queryDepsString(forTargets: userProvidedTargets)

        // Build exclusion clauses if filters are provided
        let topLevelExclusions = config.baseConfig.topLevelTargetsToExclude
        let dependencyExclusions = config.baseConfig.dependencyTargetsToExclude

        let topLevelExceptClause =
            topLevelExclusions.isEmpty
            ? "" : " except set(\(topLevelExclusions.joined(separator: " ")))"
        let dependencyExceptClause =
            dependencyExclusions.isEmpty
            ? "" : " except set(\(dependencyExclusions.joined(separator: " ")))"

        let topLevelTargetsQuery = """
            let topLevelTargets = kind("\(topLevelKindsFilter.joined(separator: "|"))", \(topLevelDepsFilter))\(topLevelExceptClause) in \
              $topLevelTargets \
              union \
              (kind("\(dependencyKindsFilter.joined(separator: "|"))", deps($topLevelTargets))\(dependencyExceptClause))
            """

        let cacheKey = "QUERY_TARGETS+\(topLevelTargetsQuery)"
        logger.info("Processing cquery request...")
        logger.debug("Cache key: \(cacheKey, privacy: .public)")

        if let cached = cqueryCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        // We use cquery here because we are interested on what's actually compiled.
        // Also, this shares more analysis cache compared to the regular query.
        let cmd = "cquery '\(topLevelTargetsQuery)' --noinclude_aspects --notool_deps --noimplicit_deps --output proto"
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        logger.info("Processing cquery results...")

        let processedCqueryResult = try parser.processCquery(
            from: output,
            testBundleRules: testBundleRules,
            supportedDependencyRuleTypes: supportedDependencyRuleTypes,
            supportedTopLevelRuleTypes: supportedTopLevelRuleTypes,
            rootUri: config.rootUri,
            workspaceName: config.workspaceName,
            executionRoot: config.executionRoot,
            toolchainPath: config.devToolchainPath,
        )

        logger.debug("Cqueried \(processedCqueryResult.buildTargets.count, privacy: .public) targets")
        logger.info("Finished processing cquery results")

        cqueryCache[cacheKey] = processedCqueryResult
        return processedCqueryResult
    }

    /// Runs an aquery across the codebase over a list of specific target dependencies.
    func aquery(
        topLevelTargets: [(String, TopLevelRuleType, UInt32)],
        config: InitializedServerConfig,
        mnemonics: [String]
    ) throws -> ProcessedAqueryResult {
        guard !mnemonics.isEmpty else {
            throw BazelTargetQuerierError.noMnemonics
        }

        let targets = topLevelTargets.map { $0.0 }

        let mnemonicsFilter = mnemonics.joined(separator: "|")
        let depsQuery = Self.queryDepsString(forTargets: targets)

        let baseFlags =
            [
                "--noinclude_artifacts",
                "--noinclude_aspects",
            ] + config.baseConfig.aqueryFlags
        let otherFlags = baseFlags.joined(separator: " ") + " --output proto"
        let cmd = "aquery \"mnemonic('\(mnemonicsFilter)', \(depsQuery))\" \(otherFlags)"

        logger.info("Processing aquery request...")
        logger.debug("Cache key: \(cmd, privacy: .public)")

        if let cached = aqueryCache[cmd] {
            logger.debug("Returning cached results")
            return cached
        }

        // Run the aquery with the special index flags since that's what we will build with.
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        logger.info("Processing aquery results...")

        let processedAqueryResult = try parser.processAquery(
            from: output,
            topLevelTargets: topLevelTargets
        )

        logger.debug("Aqueried \(processedAqueryResult.targets.count, privacy: .public) targets")
        logger.info("Finished processing aquery results")

        aqueryCache[cmd] = processedAqueryResult

        return processedAqueryResult
    }

    func clearCache() {
        cqueryCache = [:]
        aqueryCache = [:]
    }
}
