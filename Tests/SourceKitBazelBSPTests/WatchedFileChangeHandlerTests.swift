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

    @Test
    func canHandleDeletedFiles() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/MyFile.swift")
        let targetURI1 = try makeURI("build://target1")
        let targetURI2 = try makeURI("build://target2")
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI1, targetURI2]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .deleted)
            ]
        )

        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 2)
        #expect(
            observer.invalidatedTargets.contains(InvalidatedTarget(uri: targetURI1, fileUri: fileURI, kind: .deleted))
        )
        #expect(
            observer.invalidatedTargets.contains(InvalidatedTarget(uri: targetURI2, fileUri: fileURI, kind: .deleted))
        )

        #expect(connection.sentNotifications.count == 1)
        let sentNotification = try #require(
            connection.sentNotifications.first as? OnBuildTargetDidChangeNotification
        )
        let changes = try #require(sentNotification.changes)
        #expect(changes.count == 2)
        #expect(Set(changes.map { $0.target.uri }) == Set([targetURI1, targetURI2]))
        #expect(changes.allSatisfy { $0.kind == .changed })
    }

    @Test
    func canHandleCreatedFiles() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/NewFile.swift")
        let targetURI = try makeURI("build://newTarget")
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .created)
            ]
        )

        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 1)
        #expect(
            observer.invalidatedTargets.contains(InvalidatedTarget(uri: targetURI, fileUri: fileURI, kind: .created))
        )

        #expect(connection.sentNotifications.count == 1)
        let sentNotification = try #require(
            connection.sentNotifications.first as? OnBuildTargetDidChangeNotification
        )
        let changes = try #require(sentNotification.changes)
        #expect(changes.count == 1)
        #expect(changes[0].target.uri == targetURI)
        #expect(changes[0].kind == .changed)
    }

    @Test
    func updatedFilesAreIgnored() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/UpdatedFile.swift")
        let targetURI = try makeURI("build://updatedTarget")
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .changed)
            ]
        )

        handler.onWatchedFilesDidChange(notification)

        #expect(!targetStore.clearCacheCalled)
        #expect(!targetStore.fetchTargetsCalled)
        #expect(!observer.invalidateCalled)
        #expect(observer.invalidatedTargets.isEmpty)
        #expect(connection.sentNotifications.isEmpty)
    }

    @Test
    func mixedFileChanges() throws {
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

        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 2)
        #expect(
            observer.invalidatedTargets.contains(
                InvalidatedTarget(uri: deletedTargetURI, fileUri: deletedFileURI, kind: .deleted)
            )
        )
        #expect(
            observer.invalidatedTargets.contains(
                InvalidatedTarget(uri: createdTargetURI, fileUri: createdFileURI, kind: .created)
            )
        )

        #expect(connection.sentNotifications.count == 1)
        let sentNotification = try #require(
            connection.sentNotifications.first as? OnBuildTargetDidChangeNotification
        )
        let changes = try #require(sentNotification.changes)
        #expect(changes.count == 2)
        #expect(changes.contains { $0.target.uri == deletedTargetURI && $0.kind == .changed })
        #expect(changes.contains { $0.target.uri == createdTargetURI && $0.kind == .changed })
    }

    @Test
    func createdFileWithNoAssociatedTargets() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let otherFileURI = try makeURI("file:///path/to/project/Sources/OtherFile.swift")
        let otherTargetURI = try makeURI("build://otherTarget")
        targetStore.mockSrcToBspURIs[otherFileURI] = [otherTargetURI]

        let orphanFileURI = try makeURI("file:///path/to/project/Sources/OrphanFile.swift")
        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: orphanFileURI, type: .created)
            ]
        )

        #expect(targetStore.isInitialized)
        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(!observer.invalidateCalled)
        #expect(observer.invalidatedTargets.isEmpty)
        #expect(connection.sentNotifications.isEmpty)
    }

    @Test
    func earlyExitsWhenTargetStoreIsNotInitialized() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/NewFile.swift")
        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .created)
            ]
        )

        #expect(!targetStore.isInitialized)
        handler.onWatchedFilesDidChange(notification)

        #expect(!observer.invalidateCalled)
        #expect(connection.sentNotifications.isEmpty)
    }

    @Test
    func sendsNotificationDespiteObserverErrors() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let fileURI = try makeURI("file:///path/to/project/Sources/NewFile.swift")
        let targetURI = try makeURI("build://newTarget")
        targetStore.mockSrcToBspURIs[fileURI] = [targetURI]
        observer.shouldThrowOnInvalidate = true

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: fileURI, type: .created)
            ]
        )

        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(observer.invalidateCalled)
        #expect(connection.sentNotifications.count == 1)
    }

    @Test
    func handlesMultipleValidFileExtensions() throws {
        let (handler, targetStore, connection, observer) = createHandler()

        let swiftFileURI = try makeURI("file:///path/to/project/Sources/File.swift")
        let objcFileURI = try makeURI("file:///path/to/project/Sources/File.m")
        let objcppFileURI = try makeURI("file:///path/to/project/Sources/File.mm")

        let swiftTarget = try makeURI("build://swiftTarget")
        let objcTarget = try makeURI("build://objcTarget")
        let objcppTarget = try makeURI("build://objcppTarget")

        targetStore.mockSrcToBspURIs[swiftFileURI] = [swiftTarget]
        targetStore.mockSrcToBspURIs[objcFileURI] = [objcTarget]
        targetStore.mockSrcToBspURIs[objcppFileURI] = [objcppTarget]

        let notification = OnWatchedFilesDidChangeNotification(
            changes: [
                FileEvent(uri: swiftFileURI, type: .created),
                FileEvent(uri: objcFileURI, type: .created),
                FileEvent(uri: objcppFileURI, type: .created),
            ]
        )

        handler.onWatchedFilesDidChange(notification)

        #expect(targetStore.clearCacheCalled)
        #expect(targetStore.fetchTargetsCalled)
        #expect(observer.invalidateCalled)
        #expect(observer.invalidatedTargets.count == 3)
        #expect(
            observer.invalidatedTargets.contains(
                InvalidatedTarget(uri: swiftTarget, fileUri: swiftFileURI, kind: .created)
            )
        )
        #expect(
            observer.invalidatedTargets.contains(
                InvalidatedTarget(uri: objcTarget, fileUri: objcFileURI, kind: .created)
            )
        )
        #expect(
            observer.invalidatedTargets.contains(
                InvalidatedTarget(uri: objcppTarget, fileUri: objcppFileURI, kind: .created)
            )
        )

        #expect(connection.sentNotifications.count == 1)
        let sentNotification = try #require(
            connection.sentNotifications.first as? OnBuildTargetDidChangeNotification
        )
        let changes = try #require(sentNotification.changes)
        #expect(changes.count == 3)
        #expect(changes.contains { $0.target.uri == swiftTarget && $0.kind == .changed })
        #expect(changes.contains { $0.target.uri == objcTarget && $0.kind == .changed })
        #expect(changes.contains { $0.target.uri == objcppTarget && $0.kind == .changed })
    }
}
