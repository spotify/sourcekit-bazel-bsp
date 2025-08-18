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

    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws {

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

        // First, calculate deleted targets before we clear them from the targetStore
        let deletedTargets = {
            do {
                return try changes.filter { $0.type == .deleted }.flatMap { change -> [AffectedTarget] in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        AffectedTarget(uri: $0, kind: change.type)
                    }
                }
            } catch {
                logger.error("Error calculating deleted targets: \(error)")
                return []
            }
        }()

        // If there are any 'created' files, we need to clear the targetStore and fetch targets again
        // Otherwise, the targetStore won't know about them
        if changes.contains(where: { $0.type == .created }) {
            let taskId = TaskId(id: "watchedFiles-\(UUID().uuidString)")
            connection?.startWorkTask(id: taskId, title: "Indexing: Re-processing build graph")
            targetStore.clearCache()
            do {
                _ = try targetStore.fetchTargets()
            } catch {
                logger.error("Error fetching targets after file creation: \(error)")
                // Continue processing with existing target store data
            }
            connection?.finishTask(id: taskId, status: .ok)
        }

        // Now that the targetStore knows about the newly created files, we can calculate the created targets
        let createdTargets = {
            do {
                return try changes.filter { $0.type == .created }.flatMap { change -> [AffectedTarget] in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        AffectedTarget(uri: $0, kind: change.type)
                    }
                }
            } catch {
                logger.error("Error calculating created targets: \(error)")
                return []
            }
        }()

        // Finally, calculate the changed targets
        let changedTargets = {
            do {
                return try changes.filter { $0.type == .changed }.flatMap { change -> [AffectedTarget] in
                    try targetStore.bspURIs(containingSrc: change.uri).map {
                        AffectedTarget(uri: $0, kind: change.type)
                    }
                }
            } catch {
                logger.error("Error calculating changed targets: \(error)")
                return []
            }
        }()

        let affectedTargets: Set<AffectedTarget> = Set(deletedTargets + createdTargets + changedTargets)

        // Invalidate our observers about the affected targets
        for observer in observers {
            do {
                try observer.invalidate(targets: affectedTargets)
            } catch {
                logger.error("Error invalidating observer: \(error)")
                // Continue with other observers
            }
        }

        // Notify SK-LSP about the affected targets
        let response = OnBuildTargetDidChangeNotification(
            changes: affectedTargets.map { target in
                BuildTargetEvent(
                    target: BuildTargetIdentifier(uri: target.uri),
                    kind: target.kind.buildTargetEventKind,
                    dataKind: nil,
                    data: nil
                )
            }
        )

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

extension FileChangeType {
    fileprivate var buildTargetEventKind: BuildTargetEventKind? {
        switch self {
        case .changed: return .changed
        case .created: return .created
        case .deleted: return .deleted
        default: return nil
        }
    }
}
