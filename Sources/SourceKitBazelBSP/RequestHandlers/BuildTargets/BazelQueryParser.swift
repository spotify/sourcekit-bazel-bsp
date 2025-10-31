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
    case noArguments(String, String)
    case indexOutOfBounds(Int, [String])

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
        case .noArguments(let parent, let target):
            return "No arguments found for parent \(parent) of \(target)."
        case .indexOutOfBounds(let index, let array):
            return "Index \(index) is out of bounds for array: \(array)"
        }
    }
}

/// Small abstraction to parse the results of bazel target queries and aqueries.
enum BazelQueryParser {
    /// Parses Bazel query results from protobuf format into Build Server Protocol (BSP) build targets.
    ///
    /// This method processes protobuf-formatted query results (`--output streamed_proto`) from Bazel
    /// and converts them into BSP-compatible build targets with associated source files.
    ///
    /// - Parameters:
    ///   - targets: Array of `BlazeQuery_Target` protobuf objects from Bazel query output
    ///   - rootUri: Absolute path to the project root directory
    ///   - toolchainPath: Absolute path to the development toolchain
    ///
    /// - Returns: Array of tuples containing:
    ///   - `BuildTarget`: BSP build target with metadata (ID, capabilities, dependencies, etc.)
    ///   - `[URI]`: Array of source file URIs associated with the target
    static func parseTargetsWithProto(
        from targets: [BlazeQuery_Target],
        rootUri: String,
        toolchainPath: String,
    ) throws -> [(BuildTarget, [URI])] {

        // FIXME: Most of this logic is hacked together and not thought through, with the
        // sole intention of getting the example project to work.
        // Need to understand what exactly we can receive from the queries to know how to properly
        // parse this info.

        var result: [(BuildTarget, [URI])] = []
        let srcMap = buildSourceFilesMap(targets)

        for target in targets {
            guard target.type == .rule else {
                continue
            }

            // Ignore third party deps
            guard !target.rule.name.hasPrefix("@") else {
                continue
            }

            let rule = target.rule

            let id: URI = try rule.name.toTargetId(rootUri: rootUri)

            let baseDirectory: URI = try rule.name.toBaseDirectory(rootUri: rootUri)

            var testOnly = false
            var deps: [BuildTargetIdentifier] = []
            var srcs: [URI] = []
            for attr in rule.attribute {
                if attr.name == "testonly" {
                    testOnly = attr.booleanValue
                }
                // get direct upstream dependencies only
                if attr.name == "deps" {
                    let _deps: [BuildTargetIdentifier] = try attr.stringListValue.map {
                        let id = try $0.toTargetId(rootUri: rootUri)
                        return .init(uri: id)
                    }
                    deps = _deps
                }
                if attr.name == "srcs" {
                    let _srcs: [URI] = try attr.stringListValue.compactMap {
                        guard let path = srcMap[$0] else {
                            // FIXME: We should somehow find where the file would be generated to
                            // and register it as a proper generated file.
                            logger.debug(
                                "Skipping \($0, privacy: .public): Source does not exist, most likely a generated file."
                            )
                            return nil
                        }
                        return try URI(string: path)
                    }
                    srcs = _srcs
                }
            }

            // BuildTargetCapabilities
            let capabilities = BuildTargetCapabilities(
                canCompile: true,
                canTest: testOnly,
                canRun: false,
                canDebug: false
            )

            // get language
            let isSwift = target.rule.ruleClass.contains("swift")

            let data = try buildTargetData(for: toolchainPath)

            let buildTarget = BuildTarget(
                id: BuildTargetIdentifier(uri: id),
                displayName: rule.name,
                baseDirectory: baseDirectory,
                tags: testOnly ? [.test, .library] : [.library],
                capabilities: capabilities,
                languageIds: isSwift ? [.swift] : [.objective_c],
                dependencies: deps,
                dataKind: .sourceKit,
                data: data
            )

            result.append((buildTarget, srcs))
        }

        return result
    }

    /// Bazel query outputs a list of targets and each target contains list of attributes.
    /// The `srcs` attribute is a list of source_file labels instead of URI, thus we need
    /// a hashmap to reduce the time complexity.
    private static func buildSourceFilesMap(
        _ targets: [BlazeQuery_Target]
    ) -> [String: String] {
        var srcMap: [String: String] = [:]
        for target in targets {
            // making sure the target is a source_file type
            guard target.type == .sourceFile else {
                continue
            }

            // name is source_file label
            let label = target.sourceFile.name

            // location is absolute path and has suffix `:1:1`, thus trimming
            let location = target.sourceFile.location.dropLast(4)
            srcMap[label] = "file://" + String(location)
        }

        return srcMap
    }

    private static func buildTargetData(for toolchainPath: String) throws -> LanguageServerProtocol.LSPAny {
        try SourceKitBuildTarget(
            toolchain: URI(string: "file://" + toolchainPath)
        ).encodeToLSPAny()
    }
}

// MARK: - Utilities for parsing top-level configuration data from aqueries

extension BazelQueryParser {
    static func topLevelConfigInfo(
        ofTarget target: String,
        withType type: TopLevelRuleType,
        in aquery: AqueryResult
    ) throws -> BazelTargetConfigurationInfo {
        // If the parent is a test target, we need to append __internal__.__test_bundle to the label to find it in the output.
        let effectiveParentLabel: String
        if type.isTestRule {
            effectiveParentLabel = target + ".__internal__.__test_bundle"
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
        let parentAction = parentActions[0]
        let configId = parentAction.configurationID
        let parentArgs = parentAction.arguments
        // The last argument for all of these actions is the output (bazel-out/a/b/c...).
        // We will parse the "a/b/c" bit (the target configuration) out of that.
        // e.g. darwin_arm64-dbg-macos-arm64-min15.0-applebin_macos-ST-d1334902beb6
        guard let lastArgument = parentArgs.last else {
            throw BazelQueryParserError.noArguments(effectiveParentLabel, target)
        }
        let outputArg: String
        switch type {
        case .macosCommandLineApplication:
            // In macOS CLI SignBinary actions, the last action is slightly different.
            outputArg = try lastArgument.components(separatedBy: " ").getIndexThrowing(1)
        default:
            outputArg = lastArgument
        }

        let fullConfig = try outputArg.components(separatedBy: "/").getIndexThrowing(1)
        let configComponents = fullConfig.components(separatedBy: "-")
        // min15.0 -> 15.0
        let minTargetArg = String(try configComponents.getIndexThrowing(4).dropFirst(3))

        // To support compiling libraries directly, we need to additionally strip out
        // the transition and distinguisher parts of the configuration name, as those will not
        // be present when compiling directly.
        let configWithoutTransitionOrDistinguisher = configComponents.dropLast(3)
        let effectiveConfigurationName = configWithoutTransitionOrDistinguisher.joined(separator: "-")
        return BazelTargetConfigurationInfo(
            configurationID: configId,
            configurationName: fullConfig,
            effectiveConfigurationName: effectiveConfigurationName,
            minimumOsVersion: minTargetArg,
            action: parentAction
        )
    }
}

extension Array where Element == String {
    fileprivate func getIndexThrowing(_ index: Int) throws -> Element {
        guard index < count else {
            throw BazelQueryParserError.indexOutOfBounds(index, self)
        }
        return self[index]
    }
}

// MARK: - Bazel target name helpers

extension String {
    /// Converts the target name into a URI and returns a unique target id.
    ///
    /// file://<path-to-root>/<package-name>___<target-name>
    ///
    fileprivate func toTargetId(rootUri: String) throws -> URI {
        let (packageName, targetName) = try splitTargetLabel()
        let path = "file://" + rootUri + "/" + packageName + "___" + targetName
        guard let uri = try? URI(string: path) else {
            throw BazelQueryParserError.convertUriFailed(path)
        }
        return uri
    }

    /// Fetches the base directory of a target based on its unique identifier.
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
