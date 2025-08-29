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

/// Handles the file changing notification.
///
/// This is intended to tell the LSP which targets are invalidated by a change.
final class WatchedFileChangeHandler: @unchecked Sendable {
    private let targetStore: BazelTargetStore
    private var observers: [any InvalidatedTargetObserver]
    private weak var connection: LSPConnection?

    private let supportedFileExtensions: Set<String> = [
        "swift",
        "h",
        "m",
    ]

    // File changes are handled in the background because we may need to re-query the build graph as part of it.
    private let queue = DispatchQueue(label: "WatchedFileChangeHandler", qos: .userInitiated)

    init(
        targetStore: BazelTargetStore,
        observers: [any InvalidatedTargetObserver] = [],
        connection: LSPConnection
    ) {
        self.targetStore = targetStore
        self.observers = observers
        self.connection = connection
    }

    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) {
        // As of writing, SourceKit-LSP intentionally ignores our fileSystemWatchers
        // and notifies us of everything. This means we need to filter them out on our end.
        // See SourceKitLSPServer.didChangeWatchedFiles in sourcekit-lsp for more details.
        let changes = notification.changes.filter { change in
            guard isSupportedFile(uri: change.uri) else {
                logger.debug("Ignoring file change (unsupported extension): \(change.uri.stringValue)")
                return false
            }
            return true
        }

        guard !changes.isEmpty else {
            logger.info("No (supported) file changes to process.")
            return
        }

        logger.info("Received \(changes.count) file changes")

        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.process(changes: changes)
        }
    }

    func process(changes: [FileEvent]) {
        let deletedFiles = changes.filter { $0.type == .deleted }
        let createdFiles = changes.filter { $0.type == .created }
        let changedFiles = changes.filter { $0.type == .changed }

        // First, determine which targets had removed files.
        let targetsAffectedByDeletions: [InvalidatedTarget] = {
            do {
                return try deletedFiles.flatMap { change in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        InvalidatedTarget(uri: $0, fileUri: change.uri, kind: .deleted)
                    }
                }
            } catch {
                logger.error("Error calculating deleted targets: \(error)")
                return []
            }
        }()

        // If there are any 'created' files, we need to clear the targetStore immediately and fetch targets again.
        // Otherwise, the targetStore won't know about them.
        // FIXME: This is quite expensive, but the easier thing to do. We can try improving this later.
        if !createdFiles.isEmpty {
            let taskId = TaskId(id: "watchedFiles-\(UUID().uuidString)")
            connection?.startWorkTask(id: taskId, title: "Indexing: Re-processing build graph")
            targetStore.clearCache()
            do {
                _ = try targetStore.fetchTargets()
            } catch {
                logger.error("Error fetching targets after file creation: \(error)")
                connection?.finishTask(id: taskId, status: .error)
                // Continue processing with existing target store data
            }
            connection?.finishTask(id: taskId, status: .ok)
        }

        // Now that the targetStore knows about the newly created files, we can determine which targets
        // were affected by those creations.
        let targetsAffectedByCreations: [InvalidatedTarget] = {
            do {
                return try createdFiles.flatMap { change in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        InvalidatedTarget(uri: $0, fileUri: change.uri, kind: .created)
                    }
                }
            } catch {
                logger.error("Error calculating created targets: \(error)")
                return []
            }
        }()

        // Finally, calculate the targets affected by regular changes.
        let targetsAffectedByChanges: [InvalidatedTarget] = {
            do {
                return try changedFiles.flatMap { change in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        InvalidatedTarget(uri: $0, fileUri: change.uri, kind: .changed)
                    }
                }
            } catch {
                logger.error("Error calculating changed targets: \(error)")
                return []
            }
        }()

        let invalidatedTargets = targetsAffectedByDeletions + targetsAffectedByCreations + targetsAffectedByChanges

        // Notify our observers about the affected targets
        for observer in observers {
            try? observer.invalidate(targets: invalidatedTargets)
        }

        // Notify SK-LSP about the affected targets
        let uniqueInvalidatedTargets = Set(invalidatedTargets.map { $0.uri })
        let response = OnBuildTargetDidChangeNotification(
            changes: uniqueInvalidatedTargets.map { targetUri in
                BuildTargetEvent(
                    target: BuildTargetIdentifier(uri: targetUri),
                    kind: .changed,  // FIXME: We should eventually detect here also if the target is new/deleted.
                    dataKind: nil,
                    data: nil
                )
            }
        )

        logger.debug("Notifying SK-LSP about \(uniqueInvalidatedTargets.count) changes")

        connection?.send(response)
    }

    private func isSupportedFile(uri: DocumentURI) -> Bool {
        let path = uri.stringValue
        let ext: [ReversedCollection<String>.SubSequence] = path.reversed().split(separator: ".", maxSplits: 1)
        guard let result = ext.first else {
            return false
        }
        return supportedFileExtensions.contains(String(result.reversed()))
    }
}
