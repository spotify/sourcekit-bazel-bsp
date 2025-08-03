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
///
/// FIXME: Currently uses XML, should use proto instead so that we can organize and test this properly
enum BazelQueryParser {
    static func parseTargets(
        from xml: XMLElement,
        supportedRuleTypes: Set<String>,
        rootUri: String,
        toolchainPath: String
    ) throws -> [(BuildTarget, [URI])] {

        // FIXME: Most of this logic is hacked together and not thought through, with the
        // sole intention of getting the example project to work.
        // Need to understand what exactly we can receive from the queries to know how to properly
        // parse this info.

        var targets: [(BuildTarget, [URI])] = []
        for child in (xml.children ?? []) {
            if child.name != "rule" { continue }
            guard let childElement = child as? XMLElement else { continue }
            let className = childElement.attribute(forName: "class")?.stringValue ?? ""
            guard supportedRuleTypes.contains(className) else { continue }
            if let data = try getTargetForLibrary(childElement, className, rootUri, toolchainPath) {
                targets.append(data)
            }
        }
        return targets
    }

    static private func getTargetForLibrary(
        _ childElement: XMLElement,
        _ className: String,
        _ rootUri: String,
        _ toolchainPath: String
    ) throws -> (BuildTarget, [URI])? {
        let bazelTarget = childElement.attribute(forName: "name")?.stringValue ?? ""
        guard bazelTarget.starts(with: "//") else {
            // FIXME
            return nil
        }
        let isSwift = className.contains("swift")
        let fullPath = rootUri + "/" + bazelTarget.dropFirst(2)
        let uriRaw = bazelTargetToURI(fullPath)
        let basePath = uriRaw.components(separatedBy: "___")[0]
        var targetSrcs: [URI] = []
        let uri: URI = try URI(string: uriRaw)

        for child in (childElement.children ?? []) {
            if child.name != "list" { continue }
            guard let childElement = child as? XMLElement else { continue }
            let name = childElement.attribute(forName: "name")?.stringValue ?? ""
            guard name == "srcs" else { continue }
            for srcsEntry in (childElement.children ?? []) {
                if srcsEntry.name != "label" { continue }
                guard let srcsEntryElement = srcsEntry as? XMLElement else { continue }
                let srcValue = srcsEntryElement.attribute(forName: "value")?.stringValue ?? ""
                // FIXME
                if !srcValue.starts(with: "//") { continue }
                let src = srcValue.replacingOccurrences(of: ":", with: "/")
                let srcUri = try URI(string: "file://" + rootUri + "/" + src.dropFirst(2))
                targetSrcs.append(srcUri)
            }
        }

        var targetDeps: [BuildTargetIdentifier] = []
        for child in (childElement.children ?? []) {
            if child.name != "list" { continue }
            guard let childElement = child as? XMLElement else { continue }
            let name = childElement.attribute(forName: "name")?.stringValue ?? ""
            guard name == "deps" else { continue }
            for depsEntry in (childElement.children ?? []) {
                if depsEntry.name != "label" { continue }
                guard let depsEntryElement = depsEntry as? XMLElement else { continue }
                let depValue = depsEntryElement.attribute(forName: "value")?.stringValue ?? ""
                // FIXME
                if !depValue.starts(with: "//") { continue }
                let depFullPath = rootUri + "/" + depValue.dropFirst(2)
                let depUri = bazelTargetToURI(depFullPath)
                targetDeps.append(BuildTargetIdentifier(uri: try URI(string: depUri)))
            }
        }

        var tags: [BuildTargetTag] = [.library]
        var capabilities = BuildTargetCapabilities(canCompile: true, canTest: false, canRun: false, canDebug: false)
        // FIXME: Not the way to do this
        if bazelTarget.hasSuffix("TestsLib") {
            capabilities.canTest = true
            tags.append(.test)
        }
        return (
            BuildTarget(
                id: BuildTargetIdentifier(uri: uri),
                displayName: bazelTarget,
                baseDirectory: try URI(string: basePath),
                tags: tags,
                capabilities: capabilities,
                languageIds: isSwift ? [.swift] : [.objective_c],
                dependencies: targetDeps,
                dataKind: .sourceKit,
                data: SourceKitBuildTarget(toolchain: try URI(string: "file://" + toolchainPath)).encodeToLSPAny()
            ), targetSrcs
        )
    }

    static func bazelTargetToURI(_ bazelTarget: String) -> String {
        return "file://\(bazelTarget.replacingOccurrences(of: ":", with: "___"))"
    }
}

// MARK: - Proto
extension BazelQueryParser {
    static func parseTargetsWithProto(
        from targets: [BlazeQuery_Target],
        supportedRuleTypes: Set<String>,
        rootUri: String,
        toolchainPath: String
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
    /// Convert the target name into file URI scheme and returns unique target id
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

    /// Convert the target name into file URI scheme and returns the directory
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

    /// Split bazel target label into packageName and targetName
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
