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
final class WatchedFileChangeHandler {
    private let targetStore: BazelTargetStore
    private var observers: [any InvalidatedTargetObserver]
    private weak var connection: LSPConnection?

    private let supportedFileExtensions: Set<String> = [
        "swift",
        "h",
        "m",
    ]

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

        // In this case, we keep the lock until the very end of the notification to avoid race conditions
        // with how the LSP follows up with this by calling waitForBuildSystemUpdates and buildTargets again.
        // Also because we need the targetStore at multiple points of this function.
        let invalidatedTargets = targetStore.stateLock.withLockUnchecked {

            logger.info("Received \(changes.count) file changes")

            let deletedFiles = changes.filter { $0.type == .deleted }
            let createdFiles = changes.filter { $0.type == .created }

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

            // Follow-up by removing the targetStore cache. This will prompt the LSP to fetch
            // the (now modified) compiler arguments for the affected targets.
            // FIXME: This is quite expensive, but the easier thing to do. We can try improving this later.
            // FIXME2: We should detect if a target was completely removed when this happens.
            var didAlreadyClearTargetCache = false
            if !targetsAffectedByDeletions.isEmpty {
                didAlreadyClearTargetCache = true
                try? clearTargetCache()
            }

            // If there are any 'created' files, we need to clear the targetStore immediately and fetch targets again.
            // Otherwise, the targetStore won't know about them.
            if !createdFiles.isEmpty {
                let taskId = TaskId(id: "watchedFiles-\(UUID().uuidString)")
                connection?.startWorkTask(
                    id: taskId,
                    title: "sourcekit-bazel-bsp: Re-building the graph due to created files..."
                )
                if !didAlreadyClearTargetCache {
                    try? clearTargetCache()
                    didAlreadyClearTargetCache = true
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

            return targetsAffectedByDeletions + targetsAffectedByCreations

        }

        guard !invalidatedTargets.isEmpty else {
            logger.debug("No target changes to notify about.")
            return
        }

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

        connection?.send(response)
    }

    private func clearTargetCache() throws {
        targetStore.clearCache()
        _ = try targetStore.fetchTargets()
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
