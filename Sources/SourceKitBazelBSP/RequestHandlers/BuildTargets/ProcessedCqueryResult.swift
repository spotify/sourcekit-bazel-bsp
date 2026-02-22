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

private let logger = makeFileLevelBSPLogger()

struct ProcessedCqueryResult {
    let buildTargets: [BuildTarget]
    let topLevelTargets: [(String, TopLevelRuleType, String)]
    let topLevelLabelToRuleTypeMap: [String: TopLevelRuleType]
    let bspURIsToBazelLabelsMap: [URI: String]
    let bspURIsToSrcsMap: [URI: SourcesItem]
    let srcToBspURIsMap: [URI: [URI]]
    let configurationToTopLevelLabelsMap: [String: [String]]
    let bspUriToParentConfigMap: [URI: String]
    let bazelLabelToTestFilesMap: [String: [URI]]

    /// Merges the result of a cquery for added and removed files into the current result.
    /// Makes sure files that are unrelated to known targets are ignored.
    /// Important: This method assumes that the inputs are sanitized (e.g. no duplicates or conflicting info).
    /// Returns the new result and the targets that were invalidated by the changes.
    func processFileChanges(
        addedFilesResult: ProcessedCqueryAddedFilesResult?,
        deletedFiles: [URI]
    ) -> (ProcessedCqueryResult, Set<BuildTargetIdentifier>)? {
        var _bspURIsToSrcsMap = bspURIsToSrcsMap
        var _srcToBspURIsMap = srcToBspURIsMap
        var invalidatedTargets = Set<BuildTargetIdentifier>()

        // First, handle the deleted files
        for uri in deletedFiles {
            guard let bspUris = _srcToBspURIsMap[uri] else {
                continue
            }
            _srcToBspURIsMap.removeValue(forKey: uri)
            for bspURI in bspUris {
                guard let currentSrcs = _bspURIsToSrcsMap[bspURI] else {
                    continue
                }
                invalidatedTargets.insert(currentSrcs.target)
                _bspURIsToSrcsMap[bspURI] = SourcesItem(
                    target: currentSrcs.target,
                    sources: currentSrcs.sources.filter { $0.uri != uri },
                    roots: currentSrcs.roots
                )
            }
        }

        guard addedFilesResult != nil || !invalidatedTargets.isEmpty else {
            // If there were no valid deletions and no info on added files,
            // there's nothing to do here.
            return nil
        }

        // Now we can process the additions
        for (uri, sourceItems) in (addedFilesResult?.bspURIsToNewSourceItemsMap ?? [:]) {
            guard let currentSrcs = _bspURIsToSrcsMap[uri] else {
                continue
            }
            invalidatedTargets.insert(currentSrcs.target)
            _bspURIsToSrcsMap[uri] = SourcesItem(
                target: currentSrcs.target,
                sources: currentSrcs.sources + sourceItems,
                roots: currentSrcs.roots
            )
        }
        for (uri, bspUris) in (addedFilesResult?.newSrcToBspURIsMap ?? [:]) {
            let validUris = bspUris.filter { _bspURIsToSrcsMap[$0] != nil }
            guard !validUris.isEmpty else {
                continue
            }
            _srcToBspURIsMap[uri, default: []].append(contentsOf: validUris)
        }

        guard !invalidatedTargets.isEmpty else {
            // If the added files were also irrelevant, there's nothing to do here.
            return nil
        }

        let result = ProcessedCqueryResult(
            buildTargets: buildTargets,
            topLevelTargets: topLevelTargets,
            topLevelLabelToRuleTypeMap: topLevelLabelToRuleTypeMap,
            bspURIsToBazelLabelsMap: bspURIsToBazelLabelsMap,
            bspURIsToSrcsMap: _bspURIsToSrcsMap,
            srcToBspURIsMap: _srcToBspURIsMap,
            configurationToTopLevelLabelsMap: configurationToTopLevelLabelsMap,
            bspUriToParentConfigMap: bspUriToParentConfigMap,
            bazelLabelToTestFilesMap: bazelLabelToTestFilesMap
        )
        return (result, invalidatedTargets)
    }
}
