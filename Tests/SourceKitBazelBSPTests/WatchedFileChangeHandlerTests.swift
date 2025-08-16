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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct WatchedFileChangeHandlerTests {

    // MARK: - Helper Methods

    private func createHandler() -> (
        handler: WatchedFileChangeHandler,
        targetStore: BazelTargetStoreFake,
        connection: LSPConnectionFake,
        observer: InvalidatedTargetObserverFake
    ) {
        let targetStore = BazelTargetStoreFake()
        let connection = LSPConnectionFake()
        let observer = InvalidatedTargetObserverFake()
        let handler = WatchedFileChangeHandler(
            targetStore: targetStore,
            observers: [observer],
            connection: connection
        )
        return (handler, targetStore, connection, observer)
    }

    private func makeURI(_ path: String) throws -> DocumentURI {
        try DocumentURI(string: path)
    }

    // MARK: - Tests

    @Test
    func deletedFiles() throws {
        // Arrange
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/MyFile.swift")
        let targetURI1 = try makeURI("build://target1")
        let targetURI2 = try makeURI("build://target2")

        // Set up the target store to return targets for the deleted file
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI1, targetURI2]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .deleted)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert
        #expect(!targetStore.clearCacheCalled, "clearCache should not be called for deleted files")
        #expect(!targetStore.fetchTargetsCalled, "fetchTargets should not be called for deleted files")

        // Check that the observer was notified
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 2)
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: targetURI1, kind: .deleted)))
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: targetURI2, kind: .deleted)))

        // Check that the LSP connection received the notification
        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.count == 2)

            let expectedTargetURIs = Set([targetURI1, targetURI2])
            if let changes = sentNotification.changes {
                let actualTargetURIs = Set(changes.map { $0.target.uri })
                #expect(actualTargetURIs == expectedTargetURIs)

                for change in changes {
                    #expect(change.kind == .deleted)
                }
            }
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }

    @Test
    func createdFiles() throws {
        // Arrange
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/NewFile.swift")
        let targetURI = try makeURI("build://newTarget")

        // Set up the target store to return a target for the created file after fetchTargets is called
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .created)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert
        #expect(targetStore.clearCacheCalled, "clearCache should be called for created files")
        #expect(targetStore.fetchTargetsCalled, "fetchTargets should be called for created files")

        // Check that the observer was notified
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 1)
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: targetURI, kind: .created)))

        // Check that the LSP connection received the notification
        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.count == 1)
            #expect(sentNotification.changes?[0].target.uri == targetURI)
            #expect(sentNotification.changes?[0].kind == .created)
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }

    @Test
    func updatedFiles() throws {
        // Arrange
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/UpdatedFile.swift")
        let targetURI = try makeURI("build://updatedTarget")

        // Set up the target store to return a target for the updated file
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .changed)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert
        #expect(!targetStore.clearCacheCalled, "clearCache should not be called for changed files")
        #expect(!targetStore.fetchTargetsCalled, "fetchTargets should not be called for changed files")

        // Check that the observer was notified
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 1)
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: targetURI, kind: .changed)))

        // Check that the LSP connection received the notification
        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.count == 1)
            #expect(sentNotification.changes?[0].target.uri == targetURI)
            #expect(sentNotification.changes?[0].kind == .changed)
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }

    @Test
    func mixedFileChanges() throws {
        // Arrange - test with multiple file changes of different types in one notification
        let (handler, targetStore, connection, observer) = createHandler()

        let deletedFileURI = try makeURI("file:///path/to/project/Sources/DeletedFile.swift")
        let createdFileURI = try makeURI("file:///path/to/project/Sources/CreatedFile.swift")
        let changedFileURI = try makeURI("file:///path/to/project/Sources/ChangedFile.swift")

        let deletedTargetURI = try makeURI("build://deletedTarget")
        let createdTargetURI = try makeURI("build://createdTarget")
        let changedTargetURI = try makeURI("build://changedTarget")

        targetStore.mockSrcToBspURIs[deletedFileURI] = [deletedTargetURI]
        targetStore.mockSrcToBspURIs[createdFileURI] = [createdTargetURI]
        targetStore.mockSrcToBspURIs[changedFileURI] = [changedTargetURI]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: deletedFileURI, type: .deleted),
                FileEvent(uri: createdFileURI, type: .created),
                FileEvent(uri: changedFileURI, type: .changed),
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert
        #expect(targetStore.clearCacheCalled, "clearCache should be called when there are created files")
        #expect(targetStore.fetchTargetsCalled, "fetchTargets should be called when there are created files")

        // Check that the observer was notified with all affected targets
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 3)
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: deletedTargetURI, kind: .deleted)))
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: createdTargetURI, kind: .created)))
        #expect(observer.invalidatedTargets.contains(AffectedTarget(uri: changedTargetURI, kind: .changed)))

        // Check that the LSP connection received the notification with all changes
        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.count == 3)

            if let notificationChanges = sentNotification.changes {
                let changes = notificationChanges.map { (uri: $0.target.uri, kind: $0.kind) }
                #expect(changes.contains { $0.uri == deletedTargetURI && $0.kind == .deleted })
                #expect(changes.contains { $0.uri == createdTargetURI && $0.kind == .created })
                #expect(changes.contains { $0.uri == changedTargetURI && $0.kind == .changed })
            }
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }

    @Test
    func fileWithNoAssociatedTargets() throws {
        // Arrange - test handling of files that don't belong to any target
        let (handler, _, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/OrphanFile.swift")
        // Don't set up any targets for this file - bspURIs will throw an error

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .changed)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert - should handle gracefully without targets
        // The observer is still called but with an empty set when files have no targets
        #expect(observer.invalidateCalled, "Observer should be called even for files with no targets")
        #expect(observer.invalidatedTargets.isEmpty, "No targets should be invalidated for orphan files")

        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.isEmpty ?? true)
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }

    @Test
    func errorHandlingDuringFetchTargets() throws {
        // Arrange - test that errors during fetchTargets are handled gracefully
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/NewFile.swift")
        let targetURI = try makeURI("build://newTarget")

        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]
        targetStore.fetchTargetsError = InvalidatedTargetObserverFake.TestError.intentional

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .created)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert - the handler should continue processing despite the error
        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)

        // The observer should still be notified
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 1)

        // The LSP connection should still receive a notification
        #expect(connection.sentNotifications.count == 1)
    }

    @Test
    func errorHandlingDuringObserverInvalidation() throws {
        // Arrange - test that errors from observers don't stop processing
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/File.swift")
        let targetURI = try makeURI("build://target")

        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]
        observer.shouldThrowOnInvalidate = true

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .changed)
            ]
        )

        // Act
        try handler.onWatchedFilesDidChange(notification)

        // Assert - despite the observer error, the LSP connection should still receive notification
        #expect(observer.invalidateCalled)
        #expect(connection.sentNotifications.count == 1)
        if let sentNotification = connection.sentNotifications.first as? OnBuildTargetDidChangeNotification {
            #expect(sentNotification.changes?.count == 1)
            #expect(sentNotification.changes?[0].target.uri == targetURI)
        } else {
            Issue.record("Expected OnBuildTargetDidChangeNotification")
        }
    }
}
