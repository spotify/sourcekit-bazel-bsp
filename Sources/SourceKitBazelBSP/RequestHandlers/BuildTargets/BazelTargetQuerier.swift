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
    case noTopLevelRuleTypes
    case unexpectedTargetType(Int)
    case unsupportedTopLevelTargetType(String, String, [TopLevelRuleType])
    case noTopLevelTargets([TopLevelRuleType])
    case noMnemonics

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        case .noTopLevelRuleTypes: return "A list of top-level rule types is necessary to query targets"
        case .unexpectedTargetType(let type): return "Parsed unexpected target type: \(type)"
        case .unsupportedTopLevelTargetType(let target, let type, let supportedTypes):
            return """
                Unsupported top-level target type: '\(type)' for target: \
                '\(target)' supported types: \(supportedTypes.map { $0.rawValue }.joined(separator: ", "))
                """
        case .noTopLevelTargets(let rules):
            return """
                No top-level targets found in the query of kind: \
                \(rules.map { $0.rawValue }.joined(separator: ", "))
                """
        case .noMnemonics: return "A list of mnemonics is necessary to aquery targets"
        }
    }
}

/// Abstraction to handle and cache the results of bazel cqueries and aqueries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner
    private var cqueryCache = [String: CQueryResult]()
    private var aqueryCache = [String: AQueryResult]()

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

    // Runs a cquery across the codebase based on the user's provided list of top level targets,
    // listing all of their dependencies and source files.
    func cqueryTargets(
        config: InitializedServerConfig,
        supportedTopLevelRuleTypes: [TopLevelRuleType],
    ) throws -> CQueryResult {
        if supportedTopLevelRuleTypes.isEmpty {
            throw BazelTargetQuerierError.noTopLevelRuleTypes
        }

        let providedTargets = config.baseConfig.targets
        guard !providedTargets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        var kindsToFilterFor = SupportedLanguage.allCases.map { $0.ruleKind }

        // Fetch all source files as well.
        kindsToFilterFor.append("source file")

        // We need to also use the `alias` mnemonic for this query to work properly.
        // This is because --output proto doesn't follow the aliases automatically,
        // so we need this info to do it ourselves.
        kindsToFilterFor.append("alias")

        // If we're searching for test rules, we need to also include their test bundle rules.
        // Otherwise we won't be able to map test dependencies back to their top level parents.
        let testBundleRules = supportedTopLevelRuleTypes.compactMap { $0.testBundleRule }
        kindsToFilterFor.append(contentsOf: testBundleRules)

        // Collect the top-level targets -> collect these targets' dependencies
        let providedTargetsQuerySet = "set(\(providedTargets.joined(separator: " ")))"
        let dependencyKindsFilter = kindsToFilterFor.joined(separator: "|")
        let topLevelTargetsQuery = """
            let topLevelTargets = kind("rule", \(providedTargetsQuerySet)) in \
              $topLevelTargets \
              union \
              kind("\(dependencyKindsFilter)", deps($topLevelTargets))
            """

        let cacheKey = "QUERY_TARGETS+\(topLevelTargetsQuery)"
        logger.info("Processing cquery request for cache key: \(cacheKey, privacy: .public)")

        if let cached = cqueryCache[cacheKey] {
            logger.debug("Returning cached results for \(cacheKey, privacy: .public)")
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

        let queryResult = try BazelProtobufBindings.parseCqueryResult(data: output)
        let targets = queryResult.results
            .map { $0.target }
            .filter {
                // Ignore external labels.
                // FIXME: I guess _technically_ we could index those, but skipping for now.
                return !$0.rule.name.hasPrefix("@")
            }

        logger.debug("Parsed \(targets.count, privacy: .public) targets for cache key: \(cacheKey, privacy: .public)")

        let testBundleRulesSet = Set(testBundleRules)
        var seenLabels = Set<String>()
        var seenSourceFiles = Set<String>()
        var rules = [BlazeQuery_Target]()
        var testBundles = [BlazeQuery_Target]()
        var aliases = [BlazeQuery_Target]()
        var srcs = [BlazeQuery_Target]()
        for target in targets {
            if target.type == .rule {
                guard !seenLabels.contains(target.rule.name) else {
                    // FIXME: It might be possible to lift this limitation, just didn't check deep enough.
                    logger.warning(
                        "Skipping duplicate entry for target \(target.rule.name, privacy: .public). This can happen if your configuration contains multiple variants of the same target due to differing transitions. This should be fine as long as the inputs are the same across all variants."
                    )
                    continue
                }
                seenLabels.insert(target.rule.name)
                if target.rule.ruleClass == "alias" {
                    aliases.append(target)
                } else if testBundleRulesSet.contains(target.rule.ruleClass) {
                    testBundles.append(target)
                } else {
                    rules.append(target)
                }
            } else if target.type == .sourceFile {
                guard !seenSourceFiles.contains(target.sourceFile.name) else {
                    logger.error(
                        "Skipping duplicate entry for source \(target.sourceFile.name, privacy: .public). This is unexpected."
                    )
                    continue
                }
                seenSourceFiles.insert(target.sourceFile.name)
                srcs.append(target)
            } else {
                throw BazelTargetQuerierError.unexpectedTargetType(target.type.rawValue)
            }
        }

        // Now, separate the parsed content between top-level and non-top-level targets.
        // We don't need to handle the case where a top-level target is missing entirely
        // because Bazel itself will fail when this is the case.
        let userProvidedTargets = Set(providedTargets)
        let supportedTopLevelRuleTypesSet = Set(supportedTopLevelRuleTypes)
        var topLevelTargets: [(BlazeQuery_Target, TopLevelRuleType)] = []
        var dependencyTargets: [BlazeQuery_Target] = []
        for target in rules {
            let kind = target.rule.ruleClass
            let name = target.rule.name
            if userProvidedTargets.contains(name) {
                guard let topLevelRuleType = TopLevelRuleType(rawValue: kind),supportedTopLevelRuleTypesSet.contains(topLevelRuleType) else {
                    throw BazelTargetQuerierError.unsupportedTopLevelTargetType(
                        name,
                        kind,
                        supportedTopLevelRuleTypes
                    )
                }
                topLevelTargets.append((target, topLevelRuleType))
            } else {
                dependencyTargets.append(target)
            }
        }

        guard !topLevelTargets.isEmpty else {
            throw BazelTargetQuerierError.noTopLevelTargets(supportedTopLevelRuleTypes)
        }

        logger.debug("Queried \(topLevelTargets.count, privacy: .public) top-level targets")

        let result = CQueryResult(
            topLevelTargets: topLevelTargets,
            dependencyTargets: dependencyTargets,
            testBundleTargets: testBundles,
            allAliases: aliases,
            allSrcs: srcs
        )

        cqueryCache[cacheKey] = result
        return result
    }

    // Runs an aquery across the codebase over a list of specific target dependencies.
    func aquery(
        targets: [String],
        config: InitializedServerConfig,
        mnemonics: [String]
    ) throws -> AQueryResult {
        guard !mnemonics.isEmpty else {
            throw BazelTargetQuerierError.noMnemonics
        }

        let mnemonicsFilter = mnemonics.joined(separator: "|")
        let depsQuery = Self.queryDepsString(forTargets: targets)

        let otherFlags = [
            "--noinclude_artifacts",
            "--noinclude_aspects",
            "--features=-compiler_param_file",  // Context: https://github.com/spotify/sourcekit-bazel-bsp/pull/60
        ].joined(separator: " ") + " --output proto"
        let cmd = "aquery \"mnemonic('\(mnemonicsFilter)', \(depsQuery))\" \(otherFlags)"
        logger.info("Processing aquery request for \(targets, privacy: .public)")

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

        let aqueryResult = try AQueryResult(data: output)
        aqueryCache[cmd] = aqueryResult

        return aqueryResult
    }

    func clearCache() {
        cqueryCache = [:]
        aqueryCache = [:]
    }
}
