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

enum BazelQueryParserError: Error, LocalizedError {
    case incorrectName(String)
    case convertUriFailed(String)
    case parentTargetNotFound(String, String)
    case parentActionNotFound(String, UInt32)
    case multipleParentActions(String, String)
    case configurationNotFound(UInt32)
    case indexOutOfBounds(Int, Int)
    case unexpectedLanguageRule(String, String)

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
        }
    }
}

/// Small abstraction to parse the results of bazel target queries and aqueries.
enum BazelQueryParser {

    struct ParsedCQueryResult {
        struct DependencyTargetInfo {
            let target: BuildTarget
            let srcs: [URI]
        }
        let buildTargets: [DependencyTargetInfo]
        let bazelLabelToParentsMap: [String: [String]]
    }

    /// Processes the initial cquery containing all top-level targets and their sources
    /// into BSP build targets. This does not include dependency information, which is filled later.
    static func parseTargets(
        inCquery cqueryResult: BazelTargetQuerier.CQueryResult,
        rootUri: String,
        toolchainPath: String,
    ) throws -> ParsedCQueryResult {

        // Start by pre-processing all of the provided source files into a map for quick lookup.
        var srcToUriMap: [String: URI] = [:]
        for target in cqueryResult.allSrcs {
            let label = target.sourceFile.name
            // The location is an absolute path and has suffix `:1:1`, thus we need to trim it.
            let location = target.sourceFile.location.dropLast(4)
            srcToUriMap[label] = try URI(string: "file://" + String(location))
        }

        // Do the same for the dependencies list.
        // This also defines which dependencies are "valid",
        // because the cquery result's deps field ignores the filters applied to the query.
        var depLabelToUriMap: [String: (BuildTargetIdentifier, String)] = [:]
        for target in cqueryResult.dependencyTargets {
            let label = target.rule.name
            depLabelToUriMap[label] = (BuildTargetIdentifier(
                uri: try label.toTargetId(rootUri: rootUri)
            ), label)
        }

        // Similarly, process the list of aliases. The cquery result's deps field does not
        // follow aliases, so we need to do this to find the actual targets.
        // We track a separate array for determinism reasons.
        var registeredAliases = [String]()
        var aliasToLabelMap: [String: String] = [:]
        for target in cqueryResult.allAliases {
            let label = target.rule.name
            let actual = target.rule.ruleInput[0]
            aliasToLabelMap[label] = actual
            registeredAliases.append(label)
        }
        // Treat test bundle rules as aliases as well. This allows us to locate the "true" dependency
        // when encountering a test bundle.
        for target in cqueryResult.testBundleTargets {
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
            depLabelToUriMap[label] = (BuildTargetIdentifier(
                uri: try realLabel.toTargetId(rootUri: rootUri)
            ), realLabel)
        }

        var result: [String: (BuildTarget, [URI])] = [:]
        var dependencyGraph: [String: [String]] = [:]
        for target in cqueryResult.dependencyTargets {
            guard target.type == .rule else {
                // Should not happen, but checking just in case.
                continue
            }

            let rule = target.rule

            let id: URI = try rule.name.toTargetId(rootUri: rootUri)
            let baseDirectory: URI = try rule.name.toBaseDirectory(rootUri: rootUri)

            let srcs = try processSrcsAttr(rule: rule, srcToUriMap: srcToUriMap)
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
            switch rule.ruleClass {
            case "swift_library":
                languageId = [.swift]
            case "objc_library":
                languageId = [.objective_c]
            default:
                throw BazelQueryParserError.unexpectedLanguageRule(rule.name, rule.ruleClass)
            }

            let buildTarget = BuildTarget(
                id: BuildTargetIdentifier(uri: id),
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
            result[rule.name] = (buildTarget, srcs)
        }

        // We can now wrap it up by determining which dependencies belong to which top-level targets.
        var bazelLabelToParentsMap: [String: [String]] = [:]
        for (target, ruleType) in cqueryResult.topLevelTargets {
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

        for (label, _) in result {
            let isOrphan = bazelLabelToParentsMap[label, default: []].isEmpty
            if isOrphan {
                // If we don't know how to parse the full path to a target, we need to drop it.
                // Otherwise we will not know how to properly communicate this target's capabilities to sourcekit-lsp.
                logger.warning("Skipping orphan target \(label, privacy: .public). This can happen if the target is a dependency of something we don't know how to parse.")
                result[label] = nil
            }
        }

        return ParsedCQueryResult(
            buildTargets: result.sorted(by: { $0.0 < $1.0 }).map {
                ParsedCQueryResult.DependencyTargetInfo(
                    target: $0.value.0,
                    srcs: $0.value.1
                )
            },
            bazelLabelToParentsMap: bazelLabelToParentsMap
        )
    }

    /// Resolves an alias to its actual target.
    /// If the label is not an alias, returns the label unchanged.
    private static func resolveAlias(
        label: String,
        from aliasToLabelMap: [String: String]
    ) -> String {
        var current = label
        while let resolved = aliasToLabelMap[current] {
            current = resolved
        }
        return current
    }

    private static func processSrcsAttr(
        rule: BlazeQuery_Rule,
        srcToUriMap: [String: URI],
    ) throws -> [URI] {
        let srcsAttribute = rule.attribute.first { $0.name == "srcs" }
        let srcs: [URI]
        if let attr = srcsAttribute {
            srcs = attr.stringListValue.compactMap {
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
        } else {
            srcs = []
        }
        return srcs
    }

    private static func processDependenciesAttr(
        rule: BlazeQuery_Rule,
        isBuildTestRule: Bool,
        depLabelToUriMap: [String: (BuildTargetIdentifier, String)],
        dependencyGraph: inout [String: [String]],
    ) throws -> [BuildTargetIdentifier] {
        let attrName = isBuildTestRule ? "targets" : "deps"
        let depsAttribute = rule.attribute.first { $0.name == attrName }
        let deps: [BuildTargetIdentifier]
        let thisRule = rule.name
        if let attr = depsAttribute {
            deps = attr.stringListValue.compactMap { label in
                guard let (depUri, depRealLabel) = depLabelToUriMap[label] else {
                    logger.debug(
                        "Skipping dependency \(label, privacy: .public): not considered a valid dependency"
                    )
                    return nil
                }
                dependencyGraph[thisRule, default: []].append(depRealLabel)
                return depUri
            }.sorted(by: { $0.uri.stringValue < $1.uri.stringValue })
        } else {
            deps = []
        }
        return deps
    }

    private static func traverseGraph(
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

// MARK: - Utilities for parsing top-level configuration data from aqueries

extension BazelQueryParser {
    static func topLevelConfigInfo(
        ofTarget target: String,
        withType type: TopLevelRuleType,
        in aquery: AqueryResult
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
        guard let parentTarget = aquery.targets[effectiveParentLabel] else {
            throw BazelQueryParserError.parentTargetNotFound(effectiveParentLabel, target)
        }
        guard let parentActions = aquery.actions[parentTarget.id] else {
            throw BazelQueryParserError.parentActionNotFound(effectiveParentLabel, parentTarget.id)
        }
        guard parentActions.count == 1 else {
            throw BazelQueryParserError.multipleParentActions(effectiveParentLabel, target)
        }
        // From the parent action, we can now fetch its configuration name.
        // e.g. darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6
        let parentAction = parentActions[0]
        let configId = parentAction.configurationID
        guard let fullConfig = aquery.configurations[configId]?.mnemonic else {
            throw BazelQueryParserError.configurationNotFound(configId)
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

extension Array {
    fileprivate func getIndexThrowing(_ index: Int, _ line: Int = #line) throws -> Element {
        guard index < count else {
            throw BazelQueryParserError.indexOutOfBounds(index, line)
        }
        return self[index]
    }
}

// MARK: - Bazel label parsing helpers

extension String {
    /// Converts a Bazel label into a URI and returns a unique target id.
    ///
    /// file://<path-to-root>/<package-name>___<target-name>
    ///
    func toTargetId(rootUri: String) throws -> URI {
        let (packageName, targetName) = try splitTargetLabel()
        let path = "file://" + rootUri + "/" + packageName + "___" + targetName
        guard let uri = try? URI(string: path) else {
            throw BazelQueryParserError.convertUriFailed(path)
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
            throw BazelQueryParserError.convertUriFailed(fileScheme)
        }

        return uri
    }

    /// Splits a full Bazel label into a tuple of its package and target names.
    fileprivate func splitTargetLabel() throws -> (packageName: String, targetName: String) {
        let components = split(separator: ":")

        guard components.count == 2 else {
            throw BazelQueryParserError.incorrectName(self)
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
}
