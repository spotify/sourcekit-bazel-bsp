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

private let logger = makeFileLevelBSPLogger()

enum BazelTargetParserError: Error, LocalizedError {
    case incorrectName
    case convertUriFailed
    case noSrcFound(String)

    var errorDescription: String? {
        switch self {
        case .incorrectName: return "Target name has zero or more than one colon"
        case .convertUriFailed: return "Cannot convert target name to Uri with file scheme"
        case .noSrcFound(let src): return "Cannot find source file: \(src)"
        }
    }
}

/// Small abstraction to parse the results of bazel target queries.
enum BazelQueryParser {
    /// Parses Bazel query results from protobuf format into Build Server Protocol (BSP) build targets.
    ///
    /// This method processes protobuf-formatted query results (`--output streamed_proto`) from Bazel
    /// and converts them into BSP-compatible build targets with associated source files.
    ///
    /// - Parameters:
    ///   - targets: Array of `BlazeQuery_Target` protobuf objects from Bazel query output
    ///   - supportedRuleTypes: Set of Bazel rule types to process (e.g., "swift_library", "objc_library")
    ///   - rootUri: Absolute path to the project root directory
    ///   - toolchainPath: Absolute path to the development toolchain
    ///
    /// - Returns: Array of tuples containing:
    ///   - `BuildTarget`: BSP build target with metadata (ID, capabilities, dependencies, etc.)
    ///   - `[URI]`: Array of source file URIs associated with the target
    static func parseTargetsWithProto(
        from targets: [BlazeQuery_Target],
        supportedRuleTypes: Set<String>,
        rootUri: String,
        toolchainPath: String,
        buildTestSuffix: String
    ) throws -> [(BuildTarget, [URI])] {
        var result: [(BuildTarget, [URI])] = []
        let srcMap = buildSourceFilesMap(targets)

        for target in targets {
            // make sure BlazeQuery_Target.Discriminator is rule type
            guard target.type == .rule else {
                continue
            }

            let rule = target.rule

            let id: URI = try rule.name.toTargetId(rootUri: rootUri)

            let baseDirectory: URI = try rule.name.toBaseDirectory(rootUri: rootUri)

            // get test_only
            let testOnly = rule.attribute.first { $0.name == "testonly" }?.booleanValue ?? false

            // BuildTargetCapabilities
            let capabilities = BuildTargetCapabilities(
                canCompile: true,
                canTest: testOnly,
                canRun: false,
                canDebug: false
            )

            // get language
            let isSwift = target.rule.ruleClass.contains("swift")

            // get direct upstream dependencies
            let deps: [BuildTargetIdentifier] = try rule.attribute.flatMap { attr in
                attr.name == "deps" ? attr.stringListValue : []
            }.map { label in
                let id = try label.toTargetId(rootUri: rootUri)
                return BuildTargetIdentifier(uri: id)
            }

            // get srcs
            let srcs: [URI] = try rule.attribute.flatMap { attr in
                attr.name == "srcs" ? attr.stringListValue : []
            }.compactMap { src in
                guard let path = srcMap[src] else {
                    let error = BazelTargetParserError.noSrcFound(src)
                    logger.info("\(error, privacy: .public)")
                    return nil
                }
                return try URI(string: path)
            }

            let data = SourceKitBuildTarget(
                toolchain: try URI(string: "file://" + toolchainPath)
            ).encodeToLSPAny()

            // FIXME: This is assuming everything is iOS code. Will soon update this to handle all platforms.
            let platformBuildTestSuffix = "_ios" + buildTestSuffix
            let idWithSuffix: URI = try URI(string: id.stringValue + platformBuildTestSuffix)
            let nameWithSuffix = rule.name + platformBuildTestSuffix

            let buildTarget = BuildTarget(
                id: BuildTargetIdentifier(uri: idWithSuffix),
                displayName: nameWithSuffix,
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
    static func buildSourceFilesMap(
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
}

// MARK: - Bazel target name helpers

extension String {
    /// Converts the target name into a URI and returns a unique target id.
    ///
    /// file://<path-to-root>/<package-name>___<target-name>
    ///
    func toTargetId(rootUri: String) throws -> URI {
        let (packageName, targetName) = try self.splitTargetLabel()

        let path = "file://" + rootUri + "/" + packageName + "___" + targetName

        guard let uri = try? URI(string: path) else {
            throw BazelTargetParserError.convertUriFailed
        }

        return uri
    }

    /// Converts the target name a URI and returns the target's base directory.
    ///
    /// file://<path-to-root>/<package-name>
    ///
    func toBaseDirectory(rootUri: String) throws -> URI {
        let (packageName, _) = try self.splitTargetLabel()

        let fileScheme = "file://" + rootUri + "/" + packageName

        guard let uri = try? URI(string: fileScheme) else {
            throw BazelTargetParserError.convertUriFailed
        }

        return uri
    }

    /// Splits a full Bazel label into a tuple of its package and target names.
    func splitTargetLabel() throws -> (packageName: String, targetName: String) {
        let components = self.split(separator: ":")

        guard components.count == 2 else {
            throw BazelTargetParserError.incorrectName
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
