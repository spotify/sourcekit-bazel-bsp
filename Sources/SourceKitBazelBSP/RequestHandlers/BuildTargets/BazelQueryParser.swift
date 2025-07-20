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
