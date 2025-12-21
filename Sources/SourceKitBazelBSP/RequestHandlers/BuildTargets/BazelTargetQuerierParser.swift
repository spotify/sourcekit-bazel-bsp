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
    case multipleParentActions(String, String)
    case configurationNotFound(UInt32)
    case indexOutOfBounds(Int, Int)
    case unexpectedLanguageRule(String, String)
    case unexpectedTargetType(Int)
    case unsupportedTopLevelTargetType(String, String, [TopLevelRuleType])
    case noTopLevelTargets([TopLevelRuleType])
    case missingPathExtension(String)
    case unexpectedFileExtension(String)

    var errorDescription: String? {
        switch self {
        case .incorrectName(let target): return "Target name has zero or more than one colon: \(target)"
        case .convertUriFailed(let path): return "Cannot convert target name with path \(path) to Uri with file scheme"
        case .parentTargetNotFound(let parent, let target):
            return "Parent target \(parent) of \(target) was not found in the aquery output."
        case .parentActionNotFound(let parent, let id):
            return "Parent action \(id) for parent \(parent) not found in the aquery output."
        case .multipleParentActions(let parent, let target):
            return "Multiple parent actions found for parent \(parent) of \(target). This is unexpected."
        case .configurationNotFound(let id):
            return "Configuration \(id) not found in the aquery output."
        case .indexOutOfBounds(let index, let line):
            return "Index \(index) is out of bounds for array at line \(line)"
        case .unexpectedLanguageRule(let target, let ruleClass):
            return "Could not determine \(target)'s language: Unexpected rule \(ruleClass)"
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
        case .missingPathExtension(let path): return "Missing path extension for \(path)"
        case .unexpectedFileExtension(let pathExtension): return "Unexpected file extension: \(pathExtension)"
        }
    }
}

/// Abstraction that handles the parsing of queries performed by BazelTargetQuerier.
protocol BazelTargetQuerierParser: AnyObject {
    func processCquery(
        from data: Data,
        testBundleRules: [String],
        userProvidedTargets: [String],
        supportedTopLevelRuleTypes: [TopLevelRuleType],
        rootUri: String,
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
        userProvidedTargets: [String],
        supportedTopLevelRuleTypes: [TopLevelRuleType],
        rootUri: String,
        executionRoot: String,
        toolchainPath: String,
    ) throws -> ProcessedCqueryResult {
        let cquery = try BazelProtobufBindings.parseCqueryResult(data: data)
        let targets = cquery.results
            .map { $0.target }
            .filter {
                // Ignore external labels.
                // FIXME: I guess _technically_ we could index those, but skipping for now.
                return !$0.rule.name.hasPrefix("@")
            }

        let testBundleRulesSet = Set(testBundleRules)
        var seenLabels = Set<String>()
        var seenSourceFiles = Set<String>()
        var allRules = [BlazeQuery_Target]()
        var allTestBundles = [BlazeQuery_Target]()
        var allAliases = [BlazeQuery_Target]()
        var allSrcs = [BlazeQuery_Target]()
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
                    allAliases.append(target)
                } else if testBundleRulesSet.contains(target.rule.ruleClass) {
                    allTestBundles.append(target)
                } else {
                    allRules.append(target)
                }
            } else if target.type == .sourceFile {
                guard !seenSourceFiles.contains(target.sourceFile.name) else {
                    logger.error(
                        "Skipping duplicate entry for source \(target.sourceFile.name, privacy: .public). This is unexpected."
                    )
                    continue
                }
                seenSourceFiles.insert(target.sourceFile.name)
                allSrcs.append(target)
            } else {
                throw BazelTargetQuerierParserError.unexpectedTargetType(target.type.rawValue)
            }
        }

        // Now, separate the parsed content between top-level and non-top-level targets.
        // We don't need to handle the case where a top-level target is missing entirely
        // because Bazel itself will fail when this is the case.
        let supportedTopLevelRuleTypesSet = Set(supportedTopLevelRuleTypes)
        var topLevelTargets: [(BlazeQuery_Target, TopLevelRuleType)] = []
        var dependencyTargets: [BlazeQuery_Target] = []
        // Convert the user's provided targets to full labels if needed, since this is what
        // the cquery result will contain.
        let userProvidedTargetsSet = Set(userProvidedTargets.map { $0.toFullLabel() })
        for target in allRules {
            let kind = target.rule.ruleClass
            let name = target.rule.name
            if userProvidedTargetsSet.contains(name) {
                guard let topLevelRuleType = TopLevelRuleType(rawValue: kind),
                    supportedTopLevelRuleTypesSet.contains(topLevelRuleType)
                else {
                    throw BazelTargetQuerierParserError.unsupportedTopLevelTargetType(
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
            throw BazelTargetQuerierParserError.noTopLevelTargets(supportedTopLevelRuleTypes)
        }

        // Start by pre-processing all of the provided source files into a map for quick lookup.
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
        var depLabelToUriMap: [String: (BuildTargetIdentifier, String)] = [:]
        for target in dependencyTargets {
            let label = target.rule.name
            depLabelToUriMap[label] = (
                BuildTargetIdentifier(
                    uri: try label.toTargetId(rootUri: rootUri)
                ), label
            )
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
            depLabelToUriMap[label] = (
                BuildTargetIdentifier(
                    uri: try realLabel.toTargetId(rootUri: rootUri)
                ), realLabel
            )
        }

        var result: [String: (BuildTarget, SourcesItem)] = [:]
        var dependencyGraph: [String: [String]] = [:]
        for target in dependencyTargets {
            guard target.type == .rule else {
                // Should not happen, but checking just in case.
                continue
            }

            let rule = target.rule
            let idUri: URI = try rule.name.toTargetId(rootUri: rootUri)
            let id = BuildTargetIdentifier(uri: idUri)
            let baseDirectory: URI = try rule.name.toBaseDirectory(rootUri: rootUri)

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
                depLabelToUriMap: depLabelToUriMap,
                dependencyGraph: &dependencyGraph
            )

            // These settings serve no particular purpose today. They are ignored by sourcekit-lsp.
            let capabilities = BuildTargetCapabilities(
                canCompile: true,
                canTest: false,
                canRun: false,
                canDebug: false
            )

            let languageId: [Language]
            if let language = SupportedLanguages.ruleKinds[rule.ruleClass] {
                languageId = [language]
            } else {
                throw BazelTargetQuerierParserError.unexpectedLanguageRule(rule.name, rule.ruleClass)
            }

            let buildTarget = BuildTarget(
                id: id,
                displayName: rule.name,
                baseDirectory: baseDirectory,
                tags: [.library],
                capabilities: capabilities,
                languageIds: languageId,
                dependencies: deps,
                dataKind: .sourceKit,
                data: try SourceKitBuildTarget(
                    toolchain: URI(string: "file://" + toolchainPath)
                ).encodeToLSPAny()
            )
            result[rule.name] = (buildTarget, sourcesItem)
        }

        // Determine which dependencies belong to which top-level targets.
        var bazelLabelToParentsMap: [String: [String]] = [:]
        for (target, ruleType) in topLevelTargets {
            let topLevelTarget = target.rule.name
            _ = try processDependenciesAttr(
                rule: target.rule,
                isBuildTestRule: ruleType.isBuildTestRule,
                depLabelToUriMap: depLabelToUriMap,
                dependencyGraph: &dependencyGraph
            )
            let deps = traverseGraph(from: topLevelTarget, in: dependencyGraph)
            for dep in deps {
                bazelLabelToParentsMap[dep, default: []].append(topLevelTarget)
            }
        }

        // If necessary, drop any targets that we don't know how to (fully) parse.
        for (label, _) in result {
            let isOrphan = bazelLabelToParentsMap[label, default: []].isEmpty
            if isOrphan {
                // If we don't know how to parse the full path to a target, we need to drop it.
                // Otherwise we will not know how to properly communicate this target's capabilities to sourcekit-lsp.
                logger.warning(
                    "Skipping orphan target \(label, privacy: .public). This can happen if the target is a dependency of a test host or of something we don't know how to parse."
                )
                result[label] = nil
            }
        }

        let buildTargets = result.sorted(
            by: { $0.0 < $1.0 }
        )

        var bspURIsToBazelLabelsMap: [URI: String] = [:]
        var bspURIsToSrcsMap: [URI: SourcesItem] = [:]
        var srcToBspURIsMap: [URI: [URI]] = [:]
        var availableBazelLabels: Set<String> = []
        var topLevelLabelToRuleMap: [String: TopLevelRuleType] = [:]
        for dependencyTargetInfo in buildTargets {
            let target = dependencyTargetInfo.value.0
            let sourcesItem = dependencyTargetInfo.value.1
            guard let displayName = target.displayName else {
                // Should not happen, but the property is an optional
                continue
            }
            let uri = target.id.uri
            bspURIsToBazelLabelsMap[uri] = displayName
            bspURIsToSrcsMap[uri] = sourcesItem
            availableBazelLabels.insert(displayName)
            for src in sourcesItem.sources {
                srcToBspURIsMap[src.uri, default: []].append(uri)
            }
        }
        for (target, ruleType) in topLevelTargets {
            let label = target.rule.name
            topLevelLabelToRuleMap[label] = ruleType
        }

        return ProcessedCqueryResult(
            buildTargets: buildTargets.map { $0.value.0 },
            topLevelTargets: topLevelTargets.map { ($0.0.rule.name, $0.1) },
            bspURIsToBazelLabelsMap: bspURIsToBazelLabelsMap,
            bspURIsToSrcsMap: bspURIsToSrcsMap,
            srcToBspURIsMap: srcToBspURIsMap,
            availableBazelLabels: availableBazelLabels,
            topLevelLabelToRuleMap: topLevelLabelToRuleMap,
            bazelLabelToParentsMap: bazelLabelToParentsMap
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
                // If the file is not part of the original array provided to this function,
                // then this is likely a generated file.
                // FIXME: Generated files are handled by the `generated file` mmnemonic,
                // which we don't handle today. Ignoring them for now.
                logger.debug(
                    "Skipping \($0, privacy: .public): Source does not exist, most likely a generated file."
                )
                return nil
            }
            return srcUri
        }.sorted(by: { $0.stringValue < $1.stringValue })
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
        if SupportedLanguages.headerExtensions.contains(pathExtension) {
            kind = .header
        } else if SupportedLanguages.sourceExtensions.contains(pathExtension) {
            kind = .source
        } else {
            throw BazelTargetQuerierParserError.unexpectedFileExtension(pathExtension)
        }

        // Source: https://github.com/swiftlang/sourcekit-lsp/blob/7495f5532fdb17184d69518f46a207e596b26c64/Sources/LanguageServerProtocolExtensions/Language%2BInference.swift#L33
        // let language: Language? = {
        //     switch pathExtension {
        //     case "c": return .c
        //     case "cpp", "cc", "cxx", "hpp": return .cpp
        //     case "m": return .objective_c
        //     case "mm", "h": return .objective_cpp
        //     case "swift": return .swift
        //     default: return nil
        //     }
        // }()
        let language: Language? = nil

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
        depLabelToUriMap: [String: (BuildTargetIdentifier, String)],
        dependencyGraph: inout [String: [String]],
    ) throws -> [BuildTargetIdentifier] {
        let attrName = isBuildTestRule ? "targets" : "deps"
        let thisRule = rule.name
        let depsAttribute = rule.attribute.first { $0.name == attrName }?.stringListValue ?? []
        return depsAttribute.compactMap { label in
            guard let (depUri, depRealLabel) = depLabelToUriMap[label] else {
                logger.debug(
                    "Skipping dependency \(label, privacy: .public): not considered a valid dependency"
                )
                return nil
            }
            dependencyGraph[thisRule, default: []].append(depRealLabel)
            return depUri
        }.sorted(by: { $0.uri.stringValue < $1.uri.stringValue })
    }

    private func traverseGraph(
        from target: String,
        in graph: [String: [String]],
    ) -> Set<String> {
        var visited = Set<String>()
        var result = Set<String>()
        var queue: [String] = graph[target, default: []]
        while let curr = queue.popLast() {
            result.insert(curr)
            for dep in graph[curr, default: []] {
                if !visited.contains(dep) {
                    visited.insert(dep)
                    queue.append(dep)
                }
            }
        }
        return result
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
            throw BazelTargetQuerierParserError.multipleParentActions(effectiveParentLabel, target)
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
    /// file://<path-to-root>/<package-name>___<target-name>
    ///
    fileprivate func toTargetId(rootUri: String) throws -> URI {
        let (packageName, targetName) = try splitTargetLabel()
        let path = "file://" + rootUri + "/" + packageName + "___" + targetName
        guard let uri = try? URI(string: path) else {
            throw BazelTargetQuerierParserError.convertUriFailed(path)
        }
        return uri
    }

    /// Fetches the base directory of a target based on its id.
    ///
    /// file://<path-to-root>/<package-name>
    ///
    fileprivate func toBaseDirectory(rootUri: String) throws -> URI {
        let (packageName, _) = try splitTargetLabel()

        let fileScheme = "file://" + rootUri + "/" + packageName

        guard let uri = try? URI(string: fileScheme) else {
            throw BazelTargetQuerierParserError.convertUriFailed(fileScheme)
        }

        return uri
    }

    /// Splits a full Bazel label into a tuple of its package and target names.
    fileprivate func splitTargetLabel() throws -> (packageName: String, targetName: String) {
        let components = split(separator: ":")

        guard components.count == 2 else {
            throw BazelTargetQuerierParserError.incorrectName(self)
        }

        let packageName =
            if components[0].starts(with: "//") {
                String(components[0].dropFirst(2))
            } else {
                String(components[0])
            }

        let targetName = String(components[1])

        return (packageName: packageName, targetName: targetName)
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
