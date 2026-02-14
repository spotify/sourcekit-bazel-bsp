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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct ProcessedCqueryResultTests {
    private func makeSourceItem(uri: URI) -> SourceItem {
        SourceItem(
            uri: uri,
            kind: .file,
            generated: false,
            dataKind: .sourceKit,
            data: SourceKitSourceItemData(
                language: .swift,
                kind: .source,
                outputPath: nil,
                copyDestinations: nil
            ).encodeToLSPAny()
        )
    }

    @Test
    func processesRemovals() throws {
        let targetUri = try URI(string: "bsp://target1")
        let targetId = BuildTargetIdentifier(uri: targetUri)
        let otherTargetUri = try URI(string: "bsp://target2")
        let otherTargetId = BuildTargetIdentifier(uri: otherTargetUri)
        let fileToDelete = try URI(string: "file:///src/File1.swift")
        let fileToKeep = try URI(string: "file:///src/File2.swift")
        let irrelevantFile = try URI(string: "file:///src/File3.swift")

        let sourcesItem = SourcesItem(
            target: targetId,
            sources: [makeSourceItem(uri: fileToDelete), makeSourceItem(uri: fileToKeep)],
            roots: nil
        )
        let otherSourcesItem = SourcesItem(
            target: otherTargetId,
            sources: [makeSourceItem(uri: irrelevantFile)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [targetUri: sourcesItem, otherTargetUri: otherSourcesItem],
            srcToBspURIsMap: [fileToDelete: [targetUri], fileToKeep: [targetUri], irrelevantFile: [otherTargetUri]],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        let (newResult, invalidatedTargets) = try #require(
            initialResult.processFileChanges(
                addedFilesResult: nil,
                deletedFiles: [fileToDelete]
            )
        )

        #expect(invalidatedTargets == Set([targetId]))
        #expect(
            newResult.srcToBspURIsMap == [
                fileToKeep: [targetUri],
                irrelevantFile: [otherTargetUri],
            ]
        )
        #expect(
            newResult.bspURIsToSrcsMap == [
                targetUri: SourcesItem(
                    target: targetId,
                    sources: [makeSourceItem(uri: fileToKeep)],
                    roots: nil
                ),
                otherTargetUri: otherSourcesItem,
            ]
        )
    }

    @Test
    func processesAdditions() throws {
        let targetUri = try URI(string: "bsp://target1")
        let targetId = BuildTargetIdentifier(uri: targetUri)
        let otherTargetUri = try URI(string: "bsp://target2")
        let otherTargetId = BuildTargetIdentifier(uri: otherTargetUri)
        let fileToAdd = try URI(string: "file:///src/File1.swift")
        let fileToKeep = try URI(string: "file:///src/File2.swift")
        let irrelevantFile = try URI(string: "file:///src/File3.swift")

        let sourcesItem = SourcesItem(
            target: targetId,
            sources: [makeSourceItem(uri: fileToKeep)],
            roots: nil
        )
        let otherSourcesItem = SourcesItem(
            target: otherTargetId,
            sources: [makeSourceItem(uri: irrelevantFile)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [targetUri: sourcesItem, otherTargetUri: otherSourcesItem],
            srcToBspURIsMap: [fileToKeep: [targetUri], irrelevantFile: [otherTargetUri]],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        let (newResult, invalidatedTargets) = try #require(
            initialResult.processFileChanges(
                addedFilesResult: ProcessedCqueryAddedFilesResult(
                    bspURIsToNewSourceItemsMap: [targetUri: [makeSourceItem(uri: fileToAdd)]],
                    newSrcToBspURIsMap: [fileToAdd: [targetUri]]
                ),
                deletedFiles: []
            )
        )

        #expect(invalidatedTargets == Set([targetId]))
        #expect(
            newResult.srcToBspURIsMap == [
                fileToKeep: [targetUri],
                fileToAdd: [targetUri],
                irrelevantFile: [otherTargetUri],
            ]
        )
        #expect(
            newResult.bspURIsToSrcsMap == [
                targetUri: SourcesItem(
                    target: targetId,
                    sources: [makeSourceItem(uri: fileToKeep), makeSourceItem(uri: fileToAdd)],
                    roots: nil
                ),
                otherTargetUri: otherSourcesItem,
            ]
        )
    }

    @Test
    func processesBothAdditionsAndRemovals() throws {
        let targetUri = try URI(string: "bsp://target1")
        let targetId = BuildTargetIdentifier(uri: targetUri)
        let otherTargetUri = try URI(string: "bsp://target2")
        let otherTargetId = BuildTargetIdentifier(uri: otherTargetUri)
        let fileToAdd = try URI(string: "file:///src/File1.swift")
        let fileToKeep = try URI(string: "file:///src/File2.swift")
        let fileToDelete = try URI(string: "file:///src/File3.swift")
        let irrelevantFile = try URI(string: "file:///src/File4.swift")

        let sourcesItem = SourcesItem(
            target: targetId,
            sources: [makeSourceItem(uri: fileToKeep), makeSourceItem(uri: fileToDelete)],
            roots: nil
        )
        let otherSourcesItem = SourcesItem(
            target: otherTargetId,
            sources: [makeSourceItem(uri: irrelevantFile)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [targetUri: sourcesItem, otherTargetUri: otherSourcesItem],
            srcToBspURIsMap: [fileToKeep: [targetUri], fileToDelete: [targetUri], irrelevantFile: [otherTargetUri]],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        let (newResult, invalidatedTargets) = try #require(
            initialResult.processFileChanges(
                addedFilesResult: ProcessedCqueryAddedFilesResult(
                    bspURIsToNewSourceItemsMap: [targetUri: [makeSourceItem(uri: fileToAdd)]],
                    newSrcToBspURIsMap: [fileToAdd: [targetUri]]
                ),
                deletedFiles: [fileToDelete]
            )
        )

        #expect(invalidatedTargets == Set([targetId]))
        #expect(
            newResult.srcToBspURIsMap == [
                fileToKeep: [targetUri],
                fileToAdd: [targetUri],
                irrelevantFile: [otherTargetUri],
            ]
        )
        #expect(
            newResult.bspURIsToSrcsMap == [
                targetUri: SourcesItem(
                    target: targetId,
                    sources: [makeSourceItem(uri: fileToKeep), makeSourceItem(uri: fileToAdd)],
                    roots: nil
                ),
                otherTargetUri: otherSourcesItem,
            ]
        )
    }

    @Test
    func processesRemovalCoveringSeveralTargets() throws {
        let target1Uri = try URI(string: "bsp://target1")
        let target1Id = BuildTargetIdentifier(uri: target1Uri)
        let target2Uri = try URI(string: "bsp://target2")
        let target2Id = BuildTargetIdentifier(uri: target2Uri)
        let target3Uri = try URI(string: "bsp://target3")
        let target3Id = BuildTargetIdentifier(uri: target3Uri)

        let fileToDelete = try URI(string: "file:///src/SharedFile.swift")
        let fileToKeep = try URI(string: "file:///src/OtherSharedFile.swift")

        let sourcesItem1 = SourcesItem(
            target: target1Id,
            sources: [makeSourceItem(uri: fileToDelete), makeSourceItem(uri: fileToKeep)],
            roots: nil
        )
        let sourcesItem2 = SourcesItem(
            target: target2Id,
            sources: [makeSourceItem(uri: fileToDelete), makeSourceItem(uri: fileToKeep)],
            roots: nil
        )
        let sourcesItem3 = SourcesItem(
            target: target3Id,
            sources: [makeSourceItem(uri: fileToDelete), makeSourceItem(uri: fileToKeep)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [
                target1Uri: sourcesItem1,
                target2Uri: sourcesItem2,
                target3Uri: sourcesItem3,
            ],
            srcToBspURIsMap: [
                fileToDelete: [target1Uri, target2Uri, target3Uri],
                fileToKeep: [target1Uri, target2Uri, target3Uri],
            ],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        let (newResult, invalidatedTargets) = try #require(
            initialResult.processFileChanges(
                addedFilesResult: nil,
                deletedFiles: [fileToDelete]
            )
        )

        #expect(invalidatedTargets == Set([target1Id, target2Id, target3Id]))
        #expect(
            newResult.srcToBspURIsMap == [
                fileToKeep: [target1Uri, target2Uri, target3Uri]
            ]
        )
        #expect(
            newResult.bspURIsToSrcsMap == [
                target1Uri: SourcesItem(
                    target: target1Id,
                    sources: [makeSourceItem(uri: fileToKeep)],
                    roots: nil
                ),
                target2Uri: SourcesItem(
                    target: target2Id,
                    sources: [makeSourceItem(uri: fileToKeep)],
                    roots: nil
                ),
                target3Uri: SourcesItem(
                    target: target3Id,
                    sources: [makeSourceItem(uri: fileToKeep)],
                    roots: nil
                ),
            ]
        )
    }

    @Test
    func processesAdditionCoveringSeveralTargets() throws {
        let target1Uri = try URI(string: "bsp://target1")
        let target1Id = BuildTargetIdentifier(uri: target1Uri)
        let target2Uri = try URI(string: "bsp://target2")
        let target2Id = BuildTargetIdentifier(uri: target2Uri)
        let target3Uri = try URI(string: "bsp://target3")
        let target3Id = BuildTargetIdentifier(uri: target3Uri)

        let fileToAdd = try URI(string: "file:///src/NewSharedFile.swift")
        let existingFile = try URI(string: "file:///src/ExistingSharedFile.swift")

        let sourcesItem1 = SourcesItem(
            target: target1Id,
            sources: [makeSourceItem(uri: existingFile)],
            roots: nil
        )
        let sourcesItem2 = SourcesItem(
            target: target2Id,
            sources: [makeSourceItem(uri: existingFile)],
            roots: nil
        )
        let sourcesItem3 = SourcesItem(
            target: target3Id,
            sources: [makeSourceItem(uri: existingFile)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [
                target1Uri: sourcesItem1,
                target2Uri: sourcesItem2,
                target3Uri: sourcesItem3,
            ],
            srcToBspURIsMap: [
                existingFile: [target1Uri, target2Uri, target3Uri]
            ],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        let (newResult, invalidatedTargets) = try #require(
            initialResult.processFileChanges(
                addedFilesResult: ProcessedCqueryAddedFilesResult(
                    bspURIsToNewSourceItemsMap: [
                        target1Uri: [makeSourceItem(uri: fileToAdd)],
                        target2Uri: [makeSourceItem(uri: fileToAdd)],
                        target3Uri: [makeSourceItem(uri: fileToAdd)],
                    ],
                    newSrcToBspURIsMap: [fileToAdd: [target1Uri, target2Uri, target3Uri]]
                ),
                deletedFiles: []
            )
        )

        #expect(invalidatedTargets == Set([target1Id, target2Id, target3Id]))
        #expect(
            newResult.srcToBspURIsMap == [
                existingFile: [target1Uri, target2Uri, target3Uri],
                fileToAdd: [target1Uri, target2Uri, target3Uri],
            ]
        )
        #expect(
            newResult.bspURIsToSrcsMap == [
                target1Uri: SourcesItem(
                    target: target1Id,
                    sources: [makeSourceItem(uri: existingFile), makeSourceItem(uri: fileToAdd)],
                    roots: nil
                ),
                target2Uri: SourcesItem(
                    target: target2Id,
                    sources: [makeSourceItem(uri: existingFile), makeSourceItem(uri: fileToAdd)],
                    roots: nil
                ),
                target3Uri: SourcesItem(
                    target: target3Id,
                    sources: [makeSourceItem(uri: existingFile), makeSourceItem(uri: fileToAdd)],
                    roots: nil
                ),
            ]
        )
    }

    @Test
    func onlyProcessesExisting() throws {
        let targetUri = try URI(string: "bsp://target1")
        let targetId = BuildTargetIdentifier(uri: targetUri)
        let otherTargetUri = try URI(string: "bsp://target2")
        let filetoKepp = try URI(string: "file:///src/File1.swift")
        let irrelevantFile = try URI(string: "file:///src/File2.swift")

        let sourcesItem = SourcesItem(
            target: targetId,
            sources: [makeSourceItem(uri: irrelevantFile)],
            roots: nil
        )

        let initialResult = SourceKitBazelBSP.ProcessedCqueryResult(
            buildTargets: [],
            topLevelTargets: [],
            bspURIsToBazelLabelsMap: [:],
            bspURIsToSrcsMap: [targetUri: sourcesItem],
            srcToBspURIsMap: [filetoKepp: [targetUri]],
            configurationToTopLevelLabelsMap: [:],
            bspUriToParentConfigMap: [:],
            bazelLabelToTestFilesMap: [:]
        )

        var response = initialResult.processFileChanges(
            addedFilesResult: ProcessedCqueryAddedFilesResult(
                bspURIsToNewSourceItemsMap: [otherTargetUri: [makeSourceItem(uri: irrelevantFile)]],
                newSrcToBspURIsMap: [irrelevantFile: [otherTargetUri]]
            ),
            deletedFiles: []
        )

        #expect(response == nil)

        response = initialResult.processFileChanges(
            addedFilesResult: nil,
            deletedFiles: [irrelevantFile]
        )

        #expect(response == nil)
    }
}
