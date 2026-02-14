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

import BuildServerProtocol
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

/// Abstraction to handle and cache the results of bazel queries, cqueries, and aqueries.
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner
    private let parser: BazelTargetQuerierParser

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

        logger.info("Processing cquery request...")

        // We use cquery here because we are interested on what's actually compiled.
        // Also, this shares more analysis cache compared to the regular query.
        let cmd = "cquery '\(topLevelTargetsQuery)' --noinclude_aspects --notool_deps --noimplicit_deps --output proto"
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        logger.info("Decoding cquery results...")

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

        return processedCqueryResult
    }

    /// Runs an aquery across the codebase over a list of specific target dependencies.
    func aquery(
        topLevelTargets: [(String, TopLevelRuleType, String)],
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

        // Run the aquery with the special index flags since that's what we will build with.
        let output: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: cmd,
            rootUri: config.rootUri
        )

        logger.info("Decoding aquery results...")

        let processedAqueryResult = try parser.processAquery(
            from: output,
            topLevelTargets: topLevelTargets
        )

        logger.debug("Aqueried \(processedAqueryResult.targets.count, privacy: .public) targets")
        logger.info("Finished processing aquery results")

        return processedAqueryResult
    }

    /// Runs a query + cquery combo to determine which targets the given files belong to.
    func cqueryTargets(
        forAddedSrcs srcsURIs: [URI],
        inTopLevelTargets topLevelTargets: [String],
        config: InitializedServerConfig
    ) throws -> ProcessedCqueryAddedFilesResult? {

        // Start by filtering out files that are not in the main workspace,
        // e.g. files from external repositories.
        let localFilePrefix = "file://" + config.rootUri + "/"
        let srcs =
            srcsURIs
            .map { $0.stringValue }
            .filter {
                $0.hasPrefix(localFilePrefix)
            }
            .compactMap {
                String($0.dropFirst(localFilePrefix.count)).removingPercentEncoding
            }

        guard !srcs.isEmpty else {
            return nil
        }

        // This needs to be done in two phases:
        // 1. Determine which files are actually part of the Bazel graph (regular query)
        // 2. Run a cquery to determine which targets the (valid) files belong to.
        // This is because --keep_going doesn't work with cquery for some reason...

        logger.info("Determining valid files within: \(srcs, privacy: .public)")
        let fileLabelQuery = "query \"\(srcs.map { "'\($0)'" }.joined(separator: " + "))\""
        let queryFlags =
            [
                "--keep_going"  // Continue even if one of the inputs is not part of the Bazel graph
            ] + config.baseConfig.queryFlags
        let fileLabelsQueryProcess: RunningProcess = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: fileLabelQuery,
            rootUri: config.rootUri,
            additionalFlags: queryFlags,
            skipIndexFlags: true  // Can't pass the usual build flags to regular queries
        )

        // Treat exit code 3 from --keep_going as a success.
        // When this happens, irrelevant files are automatically filtered out from the output.
        let labelsStdout: String = try fileLabelsQueryProcess.result(acceptingExitCodes: [0, 3])
        let filesToCheck = labelsStdout.components(separatedBy: "\n")

        guard !filesToCheck.isEmpty && filesToCheck.first?.isEmpty == false else {
            return nil
        }

        // `rdeps(1)`` returns the list of targets that directly depend on the given files.
        let filesSet = filesToCheck.map { "'\($0)'" }.joined(separator: " + ")
        let topLevelUnion = Self.unionString(forTargets: topLevelTargets)
        let query = "cquery \"rdeps(\(topLevelUnion), \(filesSet), 1)\""

        logger.info("Determining targets for added files: \(filesToCheck, privacy: .public)")

        let data: Data = try commandRunner.bazelIndexAction(
            baseConfig: config.baseConfig,
            outputBase: config.outputBase,
            cmd: query,
            rootUri: config.rootUri,
            additionalFlags: [
                "--output=proto"
            ]
        )

        logger.info("Decoding cquery results for added files...")

        return try parser.processCqueryAddedFiles(
            from: data,
            srcs: srcs,
            rootUri: config.rootUri,
            workspaceName: config.workspaceName,
            executionRoot: config.executionRoot
        )
    }
}
