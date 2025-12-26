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
    case indexOutOfBounds(Int, Int)
    case unexpectedLanguageRule(String, String)
    case unexpectedTargetType(Int)
    case noTopLevelTargets([TopLevelRuleType])
    case missingPathExtension(String)

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
                "Multiple parent actions found for \(parent). This means your project is somehow building multiple variants of the same top-level target, which the BSP cannot handle at the moment. This can happen for example if you are building for multiple platforms."
        case .configurationNotFound(let id):
            return "Configuration \(id) not found in the aquery output."
        case .indexOutOfBounds(let index, let line):
            return "Index \(index) is out of bounds for array at line \(line)"
        case .unexpectedLanguageRule(let target, let ruleClass):
            return "Could not determine \(target)'s language: Unexpected rule \(ruleClass)"
        case .unexpectedTargetType(let type): return "Parsed unexpected target type: \(type)"
        case .noTopLevelTargets(let rules):
            return """
                No top-level targets found in the query of kind: \
                \(rules.map { $0.rawValue }.joined(separator: ", "))
                """
        case .missingPathExtension(let path): return "Missing path extension for \(path)"
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
        topLevelTargets: [(String, TopLevelRuleType)],
    ) throws -> ProcessedAqueryResult
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

        // FIXME: This class should be broken down into multiple smaller testable ones.
        // It was done this way to first make sure the BSP worked, but now it's time to refactor.

        // Separate / categorize all the data we received from the cquery.
        let supportedTopLevelRuleTypesSet = Set(supportedTopLevelRuleTypes)
        let supportedTestBundleRulesSet = Set(testBundleRules)
        var topLevelTargets: [(BlazeQuery_Target, TopLevelRuleType)] = []
        var configurationToTopLevelLabelsMap: [UInt32: [String]] = [:]
        var bazelLabelToParentConfigMap: [String: UInt32] = [:]
        var allAliases = [BlazeQuery_Target]()
        var allTestBundles = [BlazeQuery_Target]()
        var unfilteredDependencyTargets = [Analysis_ConfiguredTarget]()
        var seenSourceFiles = Set<String>()
        var allSrcs = [BlazeQuery_Target]()
        for configuredTarget in cquery.results {
            let target = configuredTarget.target
            let configuration = configuredTarget.configurationID
            if target.type == .rule {
                let kind = target.rule.ruleClass
                if let topLevelRuleType = TopLevelRuleType(rawValue: kind) {
                    if supportedTopLevelRuleTypesSet.contains(topLevelRuleType) {
                        topLevelTargets.append((target, topLevelRuleType))
                        // If this rule generates a bundle target, the real information we're looking for will be available
                        // on said bundle target and will be handled below.
                        if topLevelRuleType.testBundleRule == nil {
                            configurationToTopLevelLabelsMap[configuration, default: []].append(target.rule.name)
                            bazelLabelToParentConfigMap[target.rule.name] = configuration
                        }
                    }
                } else if kind == "alias" {
                    allAliases.append(target)
                } else if supportedTestBundleRulesSet.contains(kind) {
                    if !target.rule.name.hasSuffix(TopLevelRuleType.testBundleRuleSuffix) {
                        logger.error(
                            "Unexpected test bundle rule without the expected suffix: \(target.rule.name, privacy: .public)"
                        )
                    }
                    allTestBundles.append(target)
                    let realTopLevelName = String(
                        target.rule.name.dropLast(TopLevelRuleType.testBundleRuleSuffix.count)
                    )
                    configurationToTopLevelLabelsMap[configuration, default: []].append(realTopLevelName)
                    bazelLabelToParentConfigMap[realTopLevelName] = configuration
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

        guard !topLevelTargets.isEmpty else {
            throw BazelTargetQuerierParserError.noTopLevelTargets(supportedTopLevelRuleTypes)
        }

        logger.debug(
            "Final configuration to top-level labels mapping: \(configurationToTopLevelLabelsMap, privacy: .public)"
        )

        logger.logFullObjectInMultipleLogMessages(
            level: .info,
            header: "Top-level targets",
            String(topLevelTargets.map { $0.0.rule.name }.joined(separator: ", "))
        )

        // The cquery will contain data about bundled apps (e.g extensions, companion watchOS apps) regardless of our filters.
        // We need to double check if the user's provided filters intend to have these included,
        // otherwise we need to drop them. We can do this by checking if the target's configuration
        // matches what we've parsed above as a valid top-level target.
        // We also use this opportunity to match which targets belong to which top-level targets.
        let supportedDependencyRuleTypesSet = Set(supportedDependencyRuleTypes)
        var dependencyTargets: [(BlazeQuery_Target, DependencyRuleType)] = []
        var seenDependencyLabels = Set<String>()
        for configuredTarget in unfilteredDependencyTargets {
            let configuration = configuredTarget.configurationID
            guard configurationToTopLevelLabelsMap[configuration] != nil else {
                continue
            }
            let kind = configuredTarget.target.rule.ruleClass
            let label = configuredTarget.target.rule.name
            guard let ruleType = DependencyRuleType(rawValue: kind), supportedDependencyRuleTypesSet.contains(ruleType)
            else {
                continue
            }
            guard !seenDependencyLabels.contains(label) else {
                // FIXME: It should be possible to lift this limitation, I just didn't check deep enough how to structure it.
                // We should notify sourcekit-lsp of all different target variants.
                // Note: When fixing this, the aquery logic below also needs to be updated to handle multiple variants.
                // Same for the logic in platformBuildLabelInfo.
                logger.debug(
                    "Skipping duplicate entry for dependency \(label, privacy: .public). This can happen if your configuration contains multiple variants of the same target and should be fine as long as the inputs are the same across all variants."
                )
                continue
            }
            bazelLabelToParentConfigMap[label] = configuration
            seenDependencyLabels.insert(label)
            dependencyTargets.append((configuredTarget.target, ruleType))
        }

        logger.debug("Parsed \(dependencyTargets.count, privacy: .public) dependency targets")

        // Pre-process all of the provided source files into a map for quick lookup.
        var srcToUriMap: [String: URI] = [:]
        for target in allSrcs {
            let label = target.sourceFile.name
            // The location is an absolute path and has suffix `:1:1`, thus we need to trim it.
            let location = target.sourceFile.location.dropLast(4)
            srcToUriMap[label] = try URI(string: "file://" + String(location))
        }

        // Do the same for the dependencies list.
        // This also defines which dependencies are "valid",
        // because the cquery result's deps field ignores the filters applied to the query.
        var depLabelToUriMap: [String: BuildTargetIdentifier] = [:]
        for (target, _) in dependencyTargets {
            let label = target.rule.name
            depLabelToUriMap[label] =
                (BuildTargetIdentifier(
                    uri: try label.toTargetId(
                        rootUri: rootUri,
                        workspaceName: workspaceName,
                        executionRoot: executionRoot
                    )
                ))
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
        for target in allTestBundles {
            let label = target.rule.name
            let actual = target.rule.ruleInput[0]
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
            depLabelToUriMap[label] =
                (BuildTargetIdentifier(
                    uri: try realLabel.toTargetId(
                        rootUri: rootUri,
                        workspaceName: workspaceName,
                        executionRoot: executionRoot
                    )
                ))
        }

        let buildTargets: [(BuildTarget, SourcesItem)] = try dependencyTargets.map { (target, ruleType) in
            let rule = target.rule
            let idUri: URI = try rule.name.toTargetId(
                rootUri: rootUri,
                workspaceName: workspaceName,
                executionRoot: executionRoot
            )
            let id = BuildTargetIdentifier(uri: idUri)
            let baseDirectory: URI? = idUri.toBaseDirectory()

            let sourcesItem = try processSrcsAttr(
                rule: rule,
                targetId: id,
                srcToUriMap: srcToUriMap,
                rootUri: rootUri,
                executionRoot: executionRoot
            )
            let deps = try processDependenciesAttr(
                rule: rule,
                isBuildTestRule: false,
                depLabelToUriMap: depLabelToUriMap
            )

            // These settings serve no particular purpose today. They are ignored by sourcekit-lsp.
            let capabilities = BuildTargetCapabilities(
                canCompile: true,
                canTest: false,
                canRun: false,
                canDebug: false
            )

            let buildTarget = BuildTarget(
                id: id,
                displayName: rule.name,
                baseDirectory: baseDirectory,
                tags: [.library],
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
        var bspURIsToSrcsMap: [URI: SourcesItem] = [:]
        var srcToBspURIsMap: [URI: [URI]] = [:]
        var topLevelLabelToRuleMap: [String: TopLevelRuleType] = [:]
        for dependencyTargetInfo in buildTargets {
            let target = dependencyTargetInfo.0
            let sourcesItem = dependencyTargetInfo.1
            guard let displayName = target.displayName else {
                // Should not happen, but the property is an optional
                continue
            }
            let uri = target.id.uri
            bspURIsToBazelLabelsMap[uri] = displayName
            bspURIsToSrcsMap[uri] = sourcesItem
            for src in sourcesItem.sources {
                srcToBspURIsMap[src.uri, default: []].append(uri)
            }
        }
        for (target, ruleType) in topLevelTargets {
            let label = target.rule.name
            topLevelLabelToRuleMap[label] = ruleType
        }

        return ProcessedCqueryResult(
            buildTargets: buildTargets.map { $0.0 },
            topLevelTargets: topLevelTargets.map { ($0.0.rule.name, $0.1) },
            bspURIsToBazelLabelsMap: bspURIsToBazelLabelsMap,
            bspURIsToSrcsMap: bspURIsToSrcsMap,
            srcToBspURIsMap: srcToBspURIsMap,
            topLevelLabelToRuleMap: topLevelLabelToRuleMap,
            configurationToTopLevelLabelsMap: configurationToTopLevelLabelsMap,
            bazelLabelToParentConfigMap: bazelLabelToParentConfigMap
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

    private func processSrcsAttr(
        rule: BlazeQuery_Rule,
        targetId: BuildTargetIdentifier,
        srcToUriMap: [String: URI],
        rootUri: String,
        executionRoot: String
    ) throws -> SourcesItem {
        let srcsAttribute = rule.attribute.first { $0.name == "srcs" }?.stringListValue ?? []
        let hdrsAttribute = rule.attribute.first { $0.name == "hdrs" }?.stringListValue ?? []
        let srcs: [URI] = (srcsAttribute + hdrsAttribute).compactMap {
            guard let srcUri = srcToUriMap[$0] else {
                return nil
            }
            return srcUri
        }
        return SourcesItem(
            target: targetId,
            sources: try srcs.map {
                try buildSourceItem(
                    forSrc: $0,
                    rootUri: rootUri,
                    executionRoot: executionRoot
                )
            }
        )
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
        depLabelToUriMap: [String: BuildTargetIdentifier],
    ) throws -> [BuildTargetIdentifier] {
        let attrName = isBuildTestRule ? "targets" : "deps"
        let depsAttribute = rule.attribute.first { $0.name == attrName }?.stringListValue ?? []
        let implDeps = rule.attribute.first { $0.name == "implementation_deps" }?.stringListValue ?? []
        return (depsAttribute + implDeps).compactMap { label in
            guard let depUri = depLabelToUriMap[label] else {
                return nil
            }
            return depUri
        }
    }
}

// MARK: - Processing Aqueries

extension BazelTargetQuerierParserImpl {
    func processAquery(
        from data: Data,
        topLevelTargets: [(String, TopLevelRuleType)],
    ) throws -> ProcessedAqueryResult {
        let aquery = try BazelProtobufBindings.parseActionGraph(data: data)

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

        // Now, locate the Bazel config information for each of our top-level targets.
        var topLevelLabelToConfigMap: [String: BazelTargetConfigurationInfo] = [:]
        for (target, ruleType) in topLevelTargets {
            let configInfo = try topLevelConfigInfo(
                ofTarget: target,
                withType: ruleType,
                aqueryTargets: targets,
                aqueryActions: actions,
                aqueryConfigurations: configurations
            )
            topLevelLabelToConfigMap[target] = configInfo
        }

        return ProcessedAqueryResult(
            targets: targets,
            actions: actions,
            configurations: configurations,
            topLevelLabelToConfigMap: topLevelLabelToConfigMap
        )
    }

    fileprivate func topLevelConfigInfo(
        ofTarget target: String,
        withType type: TopLevelRuleType,
        aqueryTargets: [String: Analysis_Target],
        aqueryActions: [UInt32: [Analysis_Action]],
        aqueryConfigurations: [UInt32: Analysis_Configuration],
    ) throws -> BazelTargetConfigurationInfo {
        // If this is a test rule wrapped by a bundle target,
        // then we need to search for this bundle target instead of the original rule.
        let effectiveParentLabel: String
        if type.testBundleRule != nil {
            effectiveParentLabel = target + TopLevelRuleType.testBundleRuleSuffix
        } else {
            effectiveParentLabel = target
        }
        // First, fetch the configuration id of the target's parent.
        guard let parentTarget = aqueryTargets[effectiveParentLabel] else {
            throw BazelTargetQuerierParserError.parentTargetNotFound(effectiveParentLabel, target)
        }
        guard let parentActions = aqueryActions[parentTarget.id] else {
            throw BazelTargetQuerierParserError.parentActionNotFound(effectiveParentLabel, parentTarget.id)
        }
        guard parentActions.count == 1 else {
            throw BazelTargetQuerierParserError.multipleParentActions(effectiveParentLabel)
        }
        // From the parent action, we can now fetch its configuration name.
        // e.g. darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6
        let parentAction = parentActions[0]
        let configId = parentAction.configurationID
        guard let fullConfig = aqueryConfigurations[configId]?.mnemonic else {
            throw BazelTargetQuerierParserError.configurationNotFound(configId)
        }
        let configComponents = fullConfig.components(separatedBy: "-")
        // min15.0 -> 15.0
        let minTargetArg = String(try configComponents.getIndexThrowing(4).dropFirst(3))
        // The first component contains the platform and arch info.
        // e.g darwin_arm64 -> (darwin, arm64)
        let cpuComponents = try configComponents.getIndexThrowing(0).split(separator: "_", maxSplits: 1)
        let platform = try cpuComponents.getIndexThrowing(0)
        let cpuArch = try cpuComponents.getIndexThrowing(1)
        // To support compiling libraries directly, we need to additionally strip out
        // the transition and distinguisher parts of the configuration name, as those will not
        // be present when compiling directly.
        let configWithoutTransitionOrDistinguisher = configComponents.dropLast(3)
        let effectiveConfigurationName = configWithoutTransitionOrDistinguisher.joined(separator: "-")
        return BazelTargetConfigurationInfo(
            configurationName: fullConfig,
            effectiveConfigurationName: effectiveConfigurationName,
            minimumOsVersion: minTargetArg,
            platform: String(platform),
            cpuArch: String(cpuArch),
        )
    }
}

// MARK: - Bazel label parsing helpers

extension Array {
    fileprivate func getIndexThrowing(_ index: Int, _ line: Int = #line) throws -> Element {
        guard index < count else {
            throw BazelTargetQuerierParserError.indexOutOfBounds(index, line)
        }
        return self[index]
    }
}

extension String {
    /// Converts a Bazel label into a URI and returns a unique target id.
    ///
    /// For local labels: file://<path-to-root>/<package-name>___<target-name>
    /// For external labels: file://<execution-root>/external/<repo-name>/<package-name>___<target-name>
    ///
    fileprivate func toTargetId(rootUri: String, workspaceName: String, executionRoot: String) throws -> URI {
        let (repoName, packageName, targetName) = try splitTargetLabel(workspaceName: workspaceName)
        let packagePath = packageName.isEmpty ? "" : "/" + packageName
        let path: String
        if repoName == workspaceName {
            path = "file://" + rootUri + packagePath + "/" + targetName
        } else {
            // External repo: use execution root + external path
            path = "file://" + executionRoot + "/external/" + repoName + packagePath + "/" + targetName
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
