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
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC

enum WorkspaceBuildTargetsError: Error, LocalizedError {
    case invalidQueryOutput

    var errorDescription: String? {
        switch self {
        case .invalidQueryOutput:
            return "Query output is not valid XML"
        }
    }
}

final class WorkspaceBuildTargetsHandler {

    let initializedConfig: InitializedServerConfig

    private(set) var targetsToBazelMap: [URI: String] = [:]
    private(set) var targetsToSrcsMap: [URI: [URI]] = [:]
    private(set) var srcToTargetsMap: [URI: [URI]] = [:]
    private var queryCache: XMLElement?

    init(initializedConfig: InitializedServerConfig) {
        self.initializedConfig = initializedConfig
    }

    func handle(
        request: WorkspaceBuildTargetsRequest,
        id: RequestID
    ) throws -> WorkspaceBuildTargetsResponse {
        var targets: [BuildTarget] = []

        let allowedClasses: Set<String> = [
            "swift_library",
            "objc_library",
        ]
        let xml = try queryTargets(allowedClasses)
        let rootUri = initializedConfig.rootUri
        let toolchain = initializedConfig.devDir + "/Toolchains/XcodeDefault.xctoolchain/"
        for child in (xml.children ?? []) {
            if child.name != "rule" {
                continue
            }
            guard let childElement = child as? XMLElement else {
                continue
            }
            let className = childElement.attribute(forName: "class")?.stringValue ?? ""
            guard allowedClasses.contains(className) else {
                continue
            }
            if var target = try getTargetForLibrary(childElement, className, rootUri) {
                target.dataKind = .sourceKit
                target.data = SourceKitBuildTarget(
                    toolchain: try URI(string: "file://" + toolchain)
                ).encodeToLSPAny()
                targets.append(target)
            }
        }

        logger.info("Found \(xml.children?.count ?? -1, privacy: .public) targets")

        return WorkspaceBuildTargetsResponse(targets: targets)
    }

    func queryTargets(_ allowedClasses: Set<String>) throws -> XMLElement {
        if let cached = queryCache {
            logger.info("Returning cached targets")
            return cached
        }
        logger.info("Querying targets")
        let bazelWrapper = initializedConfig.baseConfig.bazelWrapper
        let targets = initializedConfig.baseConfig.aqueryString
        let args =
            bazelWrapper
            + " query \"kind('\(allowedClasses.sorted().joined(separator: "|"))', \(targets))\" --output xml"
        let output = try shell(args, cwd: initializedConfig.rootUri)
        logger.info("Finished querying targets")
        guard let xml = try XMLDocument(xmlString: output).rootElement() else {
            throw WorkspaceBuildTargetsError.invalidQueryOutput
        }
        queryCache = xml
        logger.info("Will return XML")
        return xml
    }

    func getTargetForLibrary(_ childElement: XMLElement, _ className: String, _ rootUri: String)
        throws -> BuildTarget?
    {
        let bazelTarget = childElement.attribute(forName: "name")?.stringValue ?? ""
        guard bazelTarget.starts(with: "//") else {
            // FIXME
            return nil
        }
        // logger.info("Found target \(bazelTarget, privacy: .public)")
        let isSwift = className.contains("swift")
        let fullPath = rootUri + "/" + bazelTarget.dropFirst(2)
        let uriRaw = bazelTargetToURI(fullPath)
        let basePath = uriRaw.components(separatedBy: "___")[0]
        var targetSrcs: [URI] = []
        let uri: URI = try URI(string: uriRaw)

        for child in (childElement.children ?? []) {
            if child.name != "list" {
                continue
            }
            guard let childElement = child as? XMLElement else {
                continue
            }
            let name = childElement.attribute(forName: "name")?.stringValue ?? ""
            guard name == "srcs" else {
                continue
            }
            for srcsEntry in (childElement.children ?? []) {
                if srcsEntry.name != "label" {
                    continue
                }
                guard let srcsEntryElement = srcsEntry as? XMLElement else {
                    continue
                }
                let srcValue = srcsEntryElement.attribute(forName: "value")?.stringValue ?? ""
                // FIXME
                if !srcValue.starts(with: "//") {
                    continue
                }
                let src = srcValue.replacingOccurrences(of: ":", with: "/")
                let srcUri = try URI(string: "file://" + rootUri + "/" + src.dropFirst(2))
                targetSrcs.append(srcUri)
            }
        }

        var targetDeps: [BuildTargetIdentifier] = []
        for child in (childElement.children ?? []) {
            if child.name != "list" {
                continue
            }
            guard let childElement = child as? XMLElement else {
                continue
            }
            let name = childElement.attribute(forName: "name")?.stringValue ?? ""
            guard name == "deps" else {
                continue
            }
            for depsEntry in (childElement.children ?? []) {
                if depsEntry.name != "label" {
                    continue
                }
                guard let depsEntryElement = depsEntry as? XMLElement else {
                    continue
                }
                let depValue = depsEntryElement.attribute(forName: "value")?.stringValue ?? ""
                // FIXME
                if !depValue.starts(with: "//") {
                    continue
                }
                let depFullPath = rootUri + "/" + depValue.dropFirst(2)
                let depUri = bazelTargetToURI(depFullPath)
                targetDeps.append(BuildTargetIdentifier(uri: try URI(string: depUri)))
            }
        }

        targetsToBazelMap[uri] = bazelTarget
        targetsToSrcsMap[uri] = targetSrcs
        for src in targetSrcs {
            srcToTargetsMap[src, default: []].append(uri)
        }

        var tags: [BuildTargetTag] = [.library]
        var capabilities = BuildTargetCapabilities(
            canCompile: true,
            canTest: false,
            canRun: false,
            canDebug: false
        )
        if bazelTarget.hasSuffix("TestsLib") {
            capabilities.canTest = true
            tags.append(.test)
        }

        return BuildTarget(
            id: BuildTargetIdentifier(uri: uri),
            displayName: bazelTarget,
            baseDirectory: try URI(string: basePath),
            tags: tags,
            capabilities: capabilities,
            languageIds: isSwift ? [.swift] : [.objective_c],
            dependencies: targetDeps,
        )
    }

    func bazelTargetToURI(_ bazelTarget: String) -> String {
        return "file://\(bazelTarget.replacingOccurrences(of: ":", with: "___"))"
    }
}
