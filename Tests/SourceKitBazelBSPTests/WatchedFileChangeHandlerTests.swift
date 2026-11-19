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
    /// In production, `SourceKitBazelBSPServer.run(parkThread: true)` blocks the main thread forever,
    /// so nothing scheduled on `RunLoop.main` ever fires. We reproduce that by occupying the main thread
    /// for the duration of the test, and check that the debounced notification is still processed.
    @Test
    func processesChangesWhileMainThreadIsBlocked() throws {
        let store = BazelTargetStoreFake()
        _ = try store.fetchTargets()
        let handler = WatchedFileChangeHandler(targetStore: store, connection: LSPConnectionFake())

        let releaseMainThread = DispatchSemaphore(value: 0)
        let mainThreadBlocked = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            mainThreadBlocked.signal()
            releaseMainThread.wait()
        }
        defer { releaseMainThread.signal() }
        // Only proceed if the main thread was actually taken, otherwise this test would prove nothing.
        #expect(mainThreadBlocked.wait(timeout: .now() + 5) == .success)

        let file = try DocumentURI(string: "file:///workspace/New.swift")
        handler.onWatchedFilesDidChange(
            OnWatchedFilesDidChangeNotification(changes: [FileEvent(uri: file, type: .created)])
        )

        // The handler debounces for 1 second.
        Thread.sleep(forTimeInterval: 3)

        #expect(store.receivedFileChanges() == [[FileEvent(uri: file, type: .created)]])
    }
}
