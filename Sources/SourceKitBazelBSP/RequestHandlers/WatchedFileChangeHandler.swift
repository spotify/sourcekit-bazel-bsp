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

/// Handles the file changing notification.
///
/// This is intended to tell the LSP which targets are invalidated by a change.
final class WatchedFileChangeHandler {

    private let targetStore: BazelTargetStore

    private weak var connection: LSPConnection?

    init(targetStore: BazelTargetStore, connection: LSPConnection) {
        self.targetStore = targetStore
        self.connection = connection
    }

    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws {
        // FIXME: This only deals with changes, not deletions or creations
        // For those, we need to invalidate the compilation options cache too
        // and probably also re-compile the app
        let changes = notification.changes.filter { $0.type == .changed }.map { $0.uri }
        var affectedTargets: Set<URI> = []
        for change in changes {
            let targetsForSrc = try targetStore.bspURIs(containingSrc: change)
            for target in targetsForSrc {
                affectedTargets.insert(target)
            }
        }
        let response = OnBuildTargetDidChangeNotification(
            changes: affectedTargets.map {
                BuildTargetEvent(target: BuildTargetIdentifier(uri: $0), kind: .changed, dataKind: nil, data: nil)
            }
        )
        connection?.send(response)
    }
}
