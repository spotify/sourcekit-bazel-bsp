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
import Combine
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

    private let supportedFileExtensions: Set<String> = Set(SupportedExtension.allCases.map { $0.rawValue })

    // Use Combine to handle debouncing
    private var changeSubscription: PassthroughSubject<[FileEvent], Never>
    private var cancellables = Set<AnyCancellable>()

    init(
        targetStore: BazelTargetStore,
        observers: [any InvalidatedTargetObserver] = [],
        connection: LSPConnection,
    ) {
        self.targetStore = targetStore
        self.observers = observers
        self.connection = connection
        changeSubscription = PassthroughSubject<[FileEvent], Never>()
        changeSubscription
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .sink { [weak self] changes in
                self?.debouncedOnWatchedFilesDidChange(changes.flatMap { $0 })
            }
            .store(in: &cancellables)
    }

    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) {
        // We need to debounce this request to avoid spamming Bazel.
        changeSubscription.send(notification.changes)
    }

    func debouncedOnWatchedFilesDidChange(_ allChanges: [FileEvent]) {
        // As of writing, SourceKit-LSP intentionally ignores our fileSystemWatchers
        // and notifies us of everything. This means we need to filter them out on our end.
        // See SourceKitLSPServer.didChangeWatchedFiles in sourcekit-lsp for more details.
        let changes = allChanges.filter { change in
            guard isSupportedFile(uri: change.uri) else {
                logger.debug(
                    "Ignoring file change (unsupported extension): \(change.uri.stringValue, privacy: .public)"
                )
                return false
            }
            return true
        }

        guard !changes.isEmpty else {
            logger.debug("No (supported) file changes to process.")
            return
        }

        for change in changes {
            logger.debug(
                "File change: \(change.uri.stringValue, privacy: .public) \(change.type.rawValue, privacy: .public)"
            )
        }

        // We need to hold the lock here because the LSP follows up by calling waitForBuildSystemUpdates and buildTargets again.
        let invalidatedTargets: Set<BuildTargetIdentifier> = targetStore.stateLock.withLockUnchecked {
            // If we received this notification before the build graph was calculated, we should stop.
            guard targetStore.isInitialized else {
                logger.debug("Received file changes before the build graph was calculated. Ignoring.")
                return []
            }

            logger.debug("Received \(changes.count, privacy: .public) file changes")

            let taskId = TaskId(id: "watchedFiles-\(UUID().uuidString)")
            connection?.startWorkTask(
                id: taskId,
                title: "sourcekit-bazel-bsp: Updating the build graph due to file changes..."
            )
            do {
                let invalidatedTargets = try targetStore.process(
                    fileChanges: changes,
                )
                connection?.finishTask(id: taskId, status: .ok)
                return invalidatedTargets
            } catch {
                logger.error("Error processing file changes: \(error, privacy: .public)")
                connection?.finishTask(id: taskId, status: .error)
                return []
            }
        }

        guard !invalidatedTargets.isEmpty else {
            logger.debug("No target changes to notify about.")
            return
        }

        logger.debug(
            "Notifying invalidated targets: \(invalidatedTargets.map { $0.uri.stringValue }.joined(separator: ", "))"
        )

        // Notify our observers about the affected targets
        for observer in observers {
            try? observer.invalidate(targets: invalidatedTargets)
        }

        let response = OnBuildTargetDidChangeNotification(
            changes: invalidatedTargets.map { targetUri in
                BuildTargetEvent(
                    target: targetUri,
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
