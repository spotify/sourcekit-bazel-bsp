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
import BuildServerProtocol
import Foundation
import LanguageServerProtocol

private let logger = makeFileLevelBSPLogger()

enum BazelTargetQuerierParserError: Error, LocalizedError {
    case incorrectName(String)
    case convertUriFailed(String)
    case parentTargetNotFound(String, String)
    case parentActionNotFound(String, UInt32)
    case multipleParentActions(String)
    case configurationNotFound(UInt32)
    case sdkNameNotFound(String)
    case unexpectedLanguageRule(String, String)
    case unexpectedTargetType(Int)
    case noTopLevelTargets([TopLevelRuleType])
    case missingPathExtension(String)
    case missingMnemonic(UInt32)
    case unexpectedTestBundleRuleWithoutSuffix(String)

    var errorDescription: String? {
        switch self {
        case .incorrectName(let target): return "Target name has zero or more than one colon: \(target)"
        case .convertUriFailed(let path): return "Cannot convert target name with path \(path) to Uri with file scheme"
        case .parentTargetNotFound(let parent, let target):
            return "Parent target \(parent) of \(target) was not found in the aquery output."
        case .parentActionNotFound(let parent, let id):
            return "Parent action \(id) for parent \(parent) not found in the aquery output."
        case .multipleParentActions(let parent):
            return
                "Multiple parent actions found for \(parent) in the aquery output. This means your project is building multiple variants of the same top-level target, which the BSP cannot handle today."
        case .configurationNotFound(let id):
            return "Configuration \(id) not found in the aquery output."
        case .sdkNameNotFound(let cpuAndArch):
            return "SDK info could not be inferred for \(cpuAndArch)."
        case .unexpectedLanguageRule(let target, let ruleClass):
            return "Could not determine \(target)'s language: Unexpected rule \(ruleClass)"
        case .unexpectedTargetType(let type): return "Parsed unexpected target type: \(type)"
        case .noTopLevelTargets(let rules):
            return """
                No top-level targets found in the query of kind: \
                \(rules.map { $0.rawValue }.joined(separator: ", "))
                """
        case .missingPathExtension(let path): return "Missing path extension for \(path)"
        case .missingMnemonic(let id): return "Missing mnemonic for configuration ID \(id). This is unexpected."
        case .unexpectedTestBundleRuleWithoutSuffix(let name):
            return "Unexpected test bundle rule without the expected suffix: \(name)"
        }
    }
}

/// Abstraction that handles the parsing of queries performed by BazelTargetQuerier.
protocol BazelTargetQuerierParser: AnyObject {
    func processCquery(
        from data: Data,
        testBundleRules: [String],
        supportedDependencyRuleTypes: [DependencyRuleType],
        supportedTopLevelRuleTypes: [TopLevelRuleType],
        rootUri: String,
        workspaceName: String,
        executionRoot: String,
        toolchainPath: String,
    ) throws -> ProcessedCqueryResult

    func processAquery(
        from data: Data,
        topLevelTargets: [(String, TopLevelRuleType, String)],
    ) throws -> ProcessedAqueryResult

    func processCqueryAddedFiles(
        from data: Data,
        srcs: [String],
        rootUri: String,
        workspaceName: String,
        executionRoot: String
    ) throws -> ProcessedCqueryAddedFilesResult
}

// MARK: - Processing Cqueries

final class BazelTargetQuerierParserImpl: BazelTargetQuerierParser {
    func processCquery(
        from data: Data,
        testBundleRules: [String],
        supportedDependencyRuleTypes: [DependencyRuleType],
        supportedTopLevelRuleTypes: [TopLevelRuleType],
        rootUri: String,
        workspaceName: String,
        executionRoot: String,
        toolchainPath: String,
    ) throws -> ProcessedCqueryResult {
        let cquery = try BazelProtobufBindings.parseCqueryResult(data: data)

        logger.debug("Decoded cquery results")

        // FIXME: This class should be broken down into multiple smaller testable ones.
        // It was done this way to first make sure the BSP worked, but now it's time to refactor.

        // Separate / categorize all the data we received from the cquery.
        let supportedTopLevelRuleTypesSet = Set(supportedTopLevelRuleTypes)
        let supportedTestBundleRulesSet = Set(testBundleRules)
        var topLevelLabelToConfigMap: [String: String] = [:]
        var configurationToTopLevelLabelsMap: [String: [String]] = [:]
        var allTopLevelLabels = [(String, TopLevelRuleType)]()
        var allAliases = [BlazeQuery_Target]()
        var allTestBundles: [BlazeQuery_Target] = []
        var unfilteredDependencyTargets = [Analysis_ConfiguredTarget]()
        var seenSourceFiles = Set<String>()
        var allSrcs = [BlazeQuery_Target]()
        var testBundleToRealNameMap: [String: String] = [:]
        // We need to map configuration info based on the mnemonic instead of the actual UInt32 id
        // because build_test targets technically have their own configuration info despite being the
        // same mnemonic.
        var configIdToMnemonicMap: [UInt32: String] = [:]
        for configuration in cquery.configurations {
            configIdToMnemonicMap[configuration.id] = configuration.mnemonic
        }
        for configuredTarget in cquery.results {
            let target = configuredTarget.target
            if target.type == .rule {
                let kind = target.rule.ruleClass
                if let topLevelRuleType = TopLevelRuleType(rawValue: kind) {
                    guard let configuration = configIdToMnemonicMap[configuredTarget.configurationID] else {
                        throw BazelTargetQuerierParserError.missingMnemonic(configuredTarget.configurationID)
                    }
                    if supportedTopLevelRuleTypesSet.contains(topLevelRuleType) {
                        let label = target.rule.name
                        allTopLevelLabels.append((label, topLevelRuleType))
                        // If this rule generates a bundle target, the real information we're looking for will be available
                        // on said bundle target and will be handled below.
                        if topLevelRuleType.testBundleRule == nil {
                            configurationToTopLevelLabelsMap[configuration, default: []].append(label)
                            topLevelLabelToConfigMap[label] = configuration
                        }
                    }
                } else if kind == "alias" {
                    allAliases.append(target)
                } else if supportedTestBundleRulesSet.contains(kind) {
                    guard let configuration = configIdToMnemonicMap[configuredTarget.configurationID] else {
                        throw BazelTargetQuerierParserError.missingMnemonic(configuredTarget.configurationID)
                    }
                    guard target.rule.name.hasSuffix(TopLevelRuleType.testBundleRuleSuffix) else {
                        throw BazelTargetQuerierParserError.unexpectedTestBundleRuleWithoutSuffix(target.rule.name)
                    }
                    allTestBundles.append(target)
                    let realTopLevelName = String(
                        target.rule.name.dropLast(TopLevelRuleType.testBundleRuleSuffix.count)
                    )
                    testBundleToRealNameMap[target.rule.name] = realTopLevelName
                    configurationToTopLevelLabelsMap[configuration, default: []].append(realTopLevelName)
                    topLevelLabelToConfigMap[realTopLevelName] = configuration
                } else {
                    unfilteredDependencyTargets.append(configuredTarget)
                }
            } else if target.type == .sourceFile {
                guard !seenSourceFiles.contains(target.sourceFile.name) else {
                    logger.error(
                        "Unexpected duplicate entry for source \(target.sourceFile.name, privacy: .public). Ignoring."
                    )
                    continue
                }
                seenSourceFiles.insert(target.sourceFile.name)
                allSrcs.append(target)
            } else {
                throw BazelTargetQuerierParserError.unexpectedTargetType(target.type.rawValue)
            }
        }

        // We can now properly connect each top-level label to its configuration id.
        var topLevelTargets: [(String, TopLevelRuleType, String)] = []
        for (label, ruleType) in allTopLevelLabels {
            guard let configMnemonic = topLevelLabelToConfigMap[label] else {
                logger.error("Missing info for \(label) in topLevelLabelToConfigMap. This should not happen.")
                continue
            }
            topLevelTargets.append((label, ruleType, configMnemonic))
        }

        guard !topLevelTargets.isEmpty else {
            throw BazelTargetQuerierParserError.noTopLevelTargets(supportedTopLevelRuleTypes)
        }

        logger.debug(
            "Final configuration to top-level labels mapping: \(configurationToTopLevelLabelsMap, privacy: .public)"
        )

        logger.logFullObjectInMultipleLogMessages(
            level: .info,
            header: "Top-level targets",
            String(topLevelTargets.map { $0.0 }.joined(separator: ", "))
        )

        // The cquery will contain data about bundled apps (e.g extensions, companion watchOS apps) regardless of our filters.
        // We need to double check if the user's provided filters intend to have these included,
        // otherwise we need to drop them. We can do this by checking if the target's configuration
        // matches what we've parsed above as a valid top-level target.
        // We also use this opportunity to match which targets belong to which top-level targets.
        let supportedDependencyRuleTypesSet = Set(supportedDependencyRuleTypes)
        var dependencyTargets: [(BlazeQuery_Target, DependencyRuleType, BuildTargetIdentifier, String)] = []
        var bspUriToParentConfigMap: [URI: String] = [:]
        for configuredTarget in unfilteredDependencyTargets {
            guard let configuration = configIdToMnemonicMap[configuredTarget.configurationID] else {
                throw BazelTargetQuerierParserError.missingMnemonic(configuredTarget.configurationID)
            }
            guard configurationToTopLevelLabelsMap[configuration] != nil else {
                continue
            }
            let kind = configuredTarget.target.rule.ruleClass
            let label = configuredTarget.target.rule.name
            guard let ruleType = DependencyRuleType(rawValue: kind), supportedDependencyRuleTypesSet.contains(ruleType)
            else {
                continue
            }
            let id = try label.toTargetId(
                rootUri: rootUri,
                workspaceName: workspaceName,
                executionRoot: executionRoot,
                configMnemonic: configuration
            )
            bspUriToParentConfigMap[id] = configuration
            dependencyTargets.append((configuredTarget.target, ruleType, BuildTargetIdentifier(uri: id), configuration))
        }

        logger.debug("Parsed \(dependencyTargets.count, privacy: .public) dependency targets")

        let srcToUriMap = try preprocess(srcs: allSrcs)

        // Do the same for the dependencies list.
        // This also defines which dependencies are "valid",
        // because the cquery result's deps field ignores the filters applied to the query.
        var depLabelToUriMap: [String: [(BuildTargetIdentifier, String)]] = [:]
        for (target, _, id, config) in dependencyTargets {
            let label = target.rule.name
            depLabelToUriMap[label, default: []].append((id, config))
        }

        // Similarly, process the list of aliases. The cquery result's deps field does not
        // follow aliases, so we need to do this to find the actual targets.
        // We track a separate array for determinism reasons.
        var registeredAliases = [String]()
        var aliasToLabelMap: [String: String] = [:]
        for target in allAliases {
            let label = target.rule.name
            let actual = target.rule.ruleInput[0]
            aliasToLabelMap[label] = actual
            registeredAliases.append(label)
        }

        // Treat test bundle rules as aliases as well. This allows us to locate the "true" dependency
        // when encountering a test bundle.
        for (target) in allTestBundles {
            let label = target.rule.name
            let deps = target.rule.attribute.first { $0.name == "deps" }?.stringListValue ?? []
            // The first dependency of the generated test bundle is what we're looking for.
            guard let actual = deps.first else {
                logger.error("Unexpected missing dependency for test bundle \(label).")
                continue
            }
            aliasToLabelMap[label] = actual
            registeredAliases.append(label)
        }

        // After mapping out all aliases, inject them back into the dependencies map above.
        // Note that some of these aliases may resolve to invalid dependencies, which is why
        // we validate them beforehand.
        for label in registeredAliases {
            let realLabel = resolveAlias(label: label, from: aliasToLabelMap)
            guard depLabelToUriMap.keys.contains(realLabel) else {
                continue
            }
            depLabelToUriMap[label] = depLabelToUriMap[realLabel]
        }

        let buildTargets: [(BuildTarget, SourcesItem)] = try dependencyTargets.map {
            (target, ruleType, id, configMnemonic) in
            let rule = target.rule
            let idUri = id.uri

            let baseDirectory: URI? = idUri.toBaseDirectory()

            let sourcesItem = SourcesItem(
                target: id,
                sources: try buildSourceItems(
                    rule: rule,
                    srcToUriMap: srcToUriMap,
                    rootUri: rootUri,
                    executionRoot: executionRoot
                )
            )

            let deps = try processDependenciesAttr(
                rule: rule,
                isBuildTestRule: false,
                depLabelToUriMap: depLabelToUriMap,
                configMnemonic: configMnemonic
            )

            // AFAIK these settings serve no particular purpose today and are ignored by sourcekit-lsp.
            let capabilities = BuildTargetCapabilities(
                canCompile: true,
                canTest: false,
                canRun: false,
                canDebug: false
            )

            let isExternal = rule.name.hasPrefix("@")
            let tags: [BuildTargetTag] = {
                var tags: [BuildTargetTag] = [.library]
                if isExternal {
                    tags.append(.dependency)
                }
                return tags
            }()

            let buildTarget = BuildTarget(
                id: id,
                displayName: rule.name,
                baseDirectory: baseDirectory,
                tags: tags,
                capabilities: capabilities,
                languageIds: [ruleType.language],
                dependencies: deps,
                dataKind: .sourceKit,
                data: try SourceKitBuildTarget(
                    toolchain: URI(string: "file://" + toolchainPath)
                ).encodeToLSPAny()
            )
            return (buildTarget, sourcesItem)
        }

        var bspURIsToBazelLabelsMap: [URI: String] = [:]
        var displayNameToURIMap: [String: URI] = [:]
        var bspURIsToSrcsMap: [URI: SourcesItem] = [:]
        var srcToBspURIsMap: [URI: [URI]] = [:]
        for dependencyTargetInfo in buildTargets {
            let target = dependencyTargetInfo.0
            let sourcesItem = dependencyTargetInfo.1
            guard let displayName = target.displayName else {
                // Should not happen, but the property is an optional
                continue
            }
            let uri = target.id.uri
            bspURIsToBazelLabelsMap[uri] = displayName
            displayNameToURIMap[displayName] = uri
            bspURIsToSrcsMap[uri] = sourcesItem
            for src in sourcesItem.sources {
                srcToBspURIsMap[src.uri, default: []].append(uri)
            }
        }

        // Use the previously parsed test bundle info to infer which files
        // belong to which test targets. Used to power test tabs in IDE integrations.
        var bazelLabelToTestFilesMap: [String: [URI]] = [:]
        for (testBundle, realTestTarget) in testBundleToRealNameMap {
            let targetHoldingSources = resolveAlias(label: testBundle, from: aliasToLabelMap)
            guard let targetUri = displayNameToURIMap[targetHoldingSources] else {
                continue
            }
            guard let sourcesItem = bspURIsToSrcsMap[targetUri] else {
                continue
            }
            bazelLabelToTestFilesMap[realTestTarget] = sourcesItem.sources.map { $0.uri }
        }

        return ProcessedCqueryResult(
            buildTargets: buildTargets.map { $0.0 },
            topLevelTargets: topLevelTargets,
            bspURIsToBazelLabelsMap: bspURIsToBazelLabelsMap,
            bspURIsToSrcsMap: bspURIsToSrcsMap,
            srcToBspURIsMap: srcToBspURIsMap,
            configurationToTopLevelLabelsMap: configurationToTopLevelLabelsMap,
            bspUriToParentConfigMap: bspUriToParentConfigMap,
            bazelLabelToTestFilesMap: bazelLabelToTestFilesMap
        )
    }

    /// Resolves an alias to its actual target.
    /// If the label is not an alias, returns the label unchanged.
    private func resolveAlias(
        label: String,
        from aliasToLabelMap: [String: String]
    ) -> String {
        var current = label
        while let resolved = aliasToLabelMap[current] {
            current = resolved
        }
        return current
    }

    /// Builds a map of source file labels to their BSP URIs for quick lookup.
    private func preprocess(srcs allSrcs: [BlazeQuery_Target]) throws -> [String: URI] {
        var srcToUriMap: [String: URI] = [:]
        for target in allSrcs {
            let label = target.sourceFile.name
            // The location is an absolute path and has suffix `:1:1`, thus we need to trim it.
            let location = target.sourceFile.location.dropLast(4)
            srcToUriMap[label] = try URI(string: "file://" + String(location))
        }
        return srcToUriMap
    }

    private func buildSourceItems(
        rule: BlazeQuery_Rule,
        srcToUriMap: [String: URI],
        rootUri: String,
        executionRoot: String
    ) throws -> [SourceItem] {
        let srcsAttribute = rule.attribute.first { $0.name == "srcs" }?.stringListValue ?? []
        let hdrsAttribute = rule.attribute.first { $0.name == "hdrs" }?.stringListValue ?? []
        let srcs: [URI] = (srcsAttribute + hdrsAttribute).compactMap {
            guard let srcUri = srcToUriMap[$0] else {
                return nil
            }
            return srcUri
        }
        return try srcs.map {
            try buildSourceItem(
                forSrc: $0,
                rootUri: rootUri,
                executionRoot: executionRoot
            )
        }
    }

    private func buildSourceItem(
        forSrc src: URI,
        rootUri: String,
        executionRoot: String
    ) throws -> SourceItem {
        guard let pathExtension = src.fileURL?.pathExtension else {
            throw BazelTargetQuerierParserError.missingPathExtension(src.stringValue)
        }
        let kind: SourceKitSourceItemKind
        let language: Language?

        if let extensionKind = SupportedExtension(rawValue: pathExtension) {
            kind = extensionKind.kind
            language = extensionKind.language
        } else {
            logger.error(
                "Unexpected file extension \(pathExtension) for \(src.stringValue). Will recover by setting `language` to `nil`."
            )
            kind = .source
            language = nil
        }

        let copyDestinations = srcCopyDestinations(for: src, rootUri: rootUri, executionRoot: executionRoot)

        return SourceItem(
            uri: src,
            kind: .file,
            generated: false,  // FIXME: Need to handle this properly
            dataKind: .sourceKit,
            data: SourceKitSourceItemData(
                language: language,
                kind: kind,
                outputPath: nil,
                copyDestinations: copyDestinations
            ).encodeToLSPAny()
        )
    }

    /// The path sourcekit-lsp has is the "real" path of the file,
    /// but Bazel works by copying them over to the execroot.
    /// This method calculates this fake path so that sourcekit-lsp can
    /// map the file back to the original workspace path for features like jump to definition.
    private func srcCopyDestinations(
        for src: URI,
        rootUri: String,
        executionRoot: String
    ) -> [DocumentURI]? {
        guard let srcPath = src.fileURL?.path else {
            return nil
        }

        guard srcPath.hasPrefix(rootUri) else {
            return nil
        }

        var relativePath = srcPath.dropFirst(rootUri.count)
        // Not sure how much we can assume about rootUri, so adding this as an edge-case check
        if relativePath.first == "/" {
            relativePath = relativePath.dropFirst()
        }

        let newPath = executionRoot + "/" + String(relativePath)
        return [
            DocumentURI(filePath: newPath, isDirectory: false)
        ]
    }

    private func processDependenciesAttr(
        rule: BlazeQuery_Rule,
        isBuildTestRule: Bool,
        depLabelToUriMap: [String: [(BuildTargetIdentifier, String)]],
        configMnemonic: String
    ) throws -> [BuildTargetIdentifier] {
        let attrName = isBuildTestRule ? "targets" : "deps"
        let depsAttribute = rule.attribute.first { $0.name == attrName }?.stringListValue ?? []
        let implDeps = rule.attribute.first { $0.name == "implementation_deps" }?.stringListValue ?? []
        return (depsAttribute + implDeps).compactMap { label in
            guard let depUris = depLabelToUriMap[label] else {
                return nil
            }
            // When a dependency is available over multiple configs, we need to find the one matching the parent.
            guard let depUri = depUris.first(where: { $0.1 == configMnemonic }) else {
                logger.info(
                    "No dependency found for \(label) with config mnemonic \(configMnemonic). Falling back to first available config."
                )
                return depUris.first?.0
            }
            return depUri.0
        }
    }
}

// MARK: - Processing Aqueries

extension BazelTargetQuerierParserImpl {
    func processAquery(
        from data: Data,
        topLevelTargets: [(String, TopLevelRuleType, String)]
    ) throws -> ProcessedAqueryResult {
        let aquery = try BazelProtobufBindings.parseActionGraph(data: data)

        logger.debug("Decoded aquery results")

        // Pre-aggregate the aquery results to make them easier to work with later.
        let targets: [String: Analysis_Target] = aquery.targets.reduce(into: [:]) { result, target in
            if result.keys.contains(target.label) {
                logger.error(
                    "Duplicate target found when aquerying (\(target.label))! This is unexpected. Will ignore the duplicate."
                )
            }
            result[target.label] = target
        }
        let actions: [UInt32: [Analysis_Action]] = aquery.actions.reduce(into: [:]) { result, action in
            // If the aquery contains data of multiple platforms,
            // then we will see multiple entries for the same targetID.
            // We need to store all of them and find the correct variant later.
            result[action.targetID, default: []].append(action)
        }
        let configurations: [UInt32: Analysis_Configuration] = aquery.configuration.reduce(into: [:]) {
            result,
            configuration in
            if result.keys.contains(configuration.id) {
                logger.error(
                    "Duplicate configuration found when aquerying (\(configuration.id))! This is unexpected. Will ignore the duplicate."
                )
            }
            result[configuration.id] = configuration
        }

        // Now, extract the platform info for each of the mnemonics we parsed.
        var topLevelConfigMnemonicToInfoMap: [String: BazelTargetConfigurationInfo] = [:]
        for (_, _, configMnemonic) in topLevelTargets {
            guard topLevelConfigMnemonicToInfoMap[configMnemonic] == nil else {
                continue
            }
            let configInfo = try parseTopLevelConfigInfo(from: configMnemonic)
            topLevelConfigMnemonicToInfoMap[configMnemonic] = configInfo
        }

        return ProcessedAqueryResult(
            targets: targets,
            actions: actions,
            configurations: configurations,
            topLevelConfigMnemonicToInfoMap: topLevelConfigMnemonicToInfoMap
        )
    }

    fileprivate func parseTopLevelConfigInfo(
        from mnemonic: String
    ) throws -> BazelTargetConfigurationInfo {
        let configComponents = mnemonic.components(separatedBy: "-")
        // min15.0 -> 15.0
        let minTargetArg = String(try configComponents.getIndexThrowing(4).dropFirst(3))
        // The first component contains the platform and arch info.
        // e.g darwin_arm64 -> (darwin, arm64)
        let cpuAndArch = try configComponents.getIndexThrowing(0)
        let sdkName = try inferSdkName(from: cpuAndArch)
        let cpuComponents = cpuAndArch.split(separator: "_", maxSplits: 1)
        let platform = String(try cpuComponents.getIndexThrowing(0))
        let cpuArch = String(try cpuComponents.getIndexThrowing(1))

        // To support compiling libraries directly, we need to additionally strip out
        // the transition and distinguisher parts of the configuration name, as those will not
        // be present when compiling directly.

        // Edge case: rules_apple 4.3.3 dropped configuration distinguishers
        let stepsToDrop = try configComponents.getIndexThrowing(5).hasPrefix("applebin_") ? 3 : 2

        let configWithoutTransitionOrDistinguisher = configComponents.dropLast(stepsToDrop)
        let effectiveConfigurationName = configWithoutTransitionOrDistinguisher.joined(separator: "-")

        return BazelTargetConfigurationInfo(
            configurationName: mnemonic,
            effectiveConfigurationName: effectiveConfigurationName,
            minimumOsVersion: minTargetArg,
            platform: platform,
            cpuArch: cpuArch,
            sdkName: sdkName.lowercased()
        )
    }

    private func inferSdkName(from cpuAndArch: String) throws -> String {
        // Source: https://github.com/bazelbuild/apple_support/blob/main/crosstool/cc_toolchain_config.bzl
        // We can't rely on APPLE_SDK_PLATFORM in all cases because build_test rules won't have it at the top-level.
        if cpuAndArch.hasPrefix("darwin") {
            return "macosx"
        } else if cpuAndArch.hasPrefix("ios") {
            switch cpuAndArch {
            case "ios_arm64", "ios_arm64e": return "iphoneos"
            case "ios_sim_arm64", "ios_x86_64": return "iphonesimulator"
            default: break
            }
        } else if cpuAndArch.hasPrefix("tvos") {
            switch cpuAndArch {
            case "tvos_arm64": return "appletvos"
            case "tvos_sim_arm64", "tvos_x86_64": return "appletvsimulator"
            default: break
            }
        } else if cpuAndArch.hasPrefix("watchos") {
            switch cpuAndArch {
            case "watchos_arm64_32", "watchos_armv7k", "watchos_device_arm64", "watchos_device_arm64e": return "watchos"
            case "watchos_arm64", "watchos_x86_64": return "watchsimulator"
            default: break
            }
        } else if cpuAndArch.hasPrefix("visionos") {
            switch cpuAndArch {
            case "visionos_arm64": return "xros"
            case "visionos_sim_arm64": return "xrsimulator"
            default: break
            }
        }
        throw BazelTargetQuerierParserError.sdkNameNotFound(cpuAndArch)
    }
}

// MARK: - Cquery added files processing

extension BazelTargetQuerierParserImpl {
    func processCqueryAddedFiles(
        from data: Data,
        srcs: [String],
        rootUri: String,
        workspaceName: String,
        executionRoot: String
    ) throws -> ProcessedCqueryAddedFilesResult {
        let cquery = try BazelProtobufBindings.parseCqueryResult(data: data)

        logger.debug("Decoded cquery added files results")

        var configIdToMnemonicMap: [UInt32: String] = [:]
        for configuration in cquery.configurations {
            configIdToMnemonicMap[configuration.id] = configuration.mnemonic
        }

        let targets = cquery.results.filter { $0.target.type == .rule }
        let srcTargets = cquery.results.filter { $0.target.type == .sourceFile }
        let srcToUriMap = try preprocess(
            srcs: srcTargets.map { $0.target }
        )

        // From the resulting proto, extract which targets these new files belong to.
        var bspURIsToNewSourceItemsMap: [URI: [SourceItem]] = [:]
        var newSrcToBspURIsMap: [URI: [URI]] = [:]
        for configuredTarget in targets {
            let displayName = configuredTarget.target.rule.name

            let sourceItems = try buildSourceItems(
                rule: configuredTarget.target.rule,
                srcToUriMap: srcToUriMap,
                rootUri: rootUri,
                executionRoot: executionRoot
            )

            guard !sourceItems.isEmpty else {
                continue
            }

            guard let configMnemonic = configIdToMnemonicMap[configuredTarget.configurationID] else {
                throw BazelTargetQuerierParserError.missingMnemonic(configuredTarget.configurationID)
            }
            let id = try displayName.toTargetId(
                rootUri: rootUri,
                workspaceName: workspaceName,
                executionRoot: executionRoot,
                configMnemonic: configMnemonic
            )

            bspURIsToNewSourceItemsMap[id] = sourceItems
            for sourceItem in sourceItems {
                newSrcToBspURIsMap[sourceItem.uri, default: []].append(id)
            }
        }

        return ProcessedCqueryAddedFilesResult(
            bspURIsToNewSourceItemsMap: bspURIsToNewSourceItemsMap,
            newSrcToBspURIsMap: newSrcToBspURIsMap
        )
    }
}

// MARK: - Bazel label parsing helpers

extension String {
    /// Converts a Bazel label into a URI and returns a unique target id.
    ///
    /// For local labels: bazel://<path-to-root>/<package-name>___<target-name>
    /// For external labels: bazel://<execution-root>/external/<repo-name>/<package-name>___<target-name>
    ///
    fileprivate func toTargetId(
        rootUri: String,
        workspaceName: String,
        executionRoot: String,
        configMnemonic: String
    ) throws -> URI {
        let (repoName, packageName, targetName) = try splitTargetLabel(workspaceName: workspaceName)
        let packagePath = packageName.isEmpty ? "" : "/" + packageName
        let path: String
        if repoName == workspaceName {
            path = "bazel://" + rootUri + packagePath + "/" + targetName + "_" + configMnemonic
        } else {
            // External repo: use execution root + external path
            path =
                "bazel://" + executionRoot + "/external/" + repoName + packagePath + "/" + targetName + "_"
                + configMnemonic
        }
        guard let uri = try? URI(string: path) else {
            throw BazelTargetQuerierParserError.convertUriFailed(path)
        }
        return uri
    }

    /// Splits a full Bazel label into a tuple of its repo, package, and target names.
    /// For local labels (//package:target), the repo name is the provided workspace name.
    /// For external labels (@repo//package:target), the repo name is extracted.
    fileprivate func splitTargetLabel(
        workspaceName: String
    ) throws -> (repoName: String, packageName: String, targetName: String) {
        let components = split(separator: ":")

        guard components.count == 2 else {
            throw BazelTargetQuerierParserError.incorrectName(self)
        }

        let repoAndPackage = components[0]
        let targetName = String(components[1])

        let repoName: String
        let packageName: String

        if repoAndPackage.hasPrefix("@//") {
            // Alias for the main repo.
            repoName = workspaceName
            packageName = String(repoAndPackage.dropFirst(3))
        } else if repoAndPackage.hasPrefix("//") {
            // Also the main repo.
            repoName = workspaceName
            packageName = String(repoAndPackage.dropFirst(2))
        } else if repoAndPackage.hasPrefix("@") && repoAndPackage.contains("//") {
            // External label
            let withoutAt = repoAndPackage.dropFirst()
            guard let slashIndex = withoutAt.firstIndex(of: "/") else {
                throw BazelTargetQuerierParserError.incorrectName(self)
            }
            repoName = String(withoutAt[..<slashIndex])
            packageName = String(withoutAt[slashIndex...].dropFirst(2))
        } else {
            throw BazelTargetQuerierParserError.incorrectName(self)
        }

        return (repoName: repoName, packageName: packageName, targetName: targetName)
    }

    // Converts a Bazel label to its "full" equivalent, if needed.
    // e.g: "//foo/bar" -> "//foo/bar:bar"
    fileprivate func toFullLabel() -> String {
        let paths = components(separatedBy: "/")
        let lastComponent = paths.last
        if lastComponent?.contains(":") == true {
            return self
        } else if let lastComponent = lastComponent {
            return "\(self):\(lastComponent)"
        } else {
            return self
        }
    }
}

extension URI {
    /// Fetches the base directory of a target by dropping the last path component (target name) from the URI.
    fileprivate func toBaseDirectory() -> URI? {
        guard let url = fileURL else {
            return nil
        }
        return URI(url.deletingLastPathComponent())
    }
}
