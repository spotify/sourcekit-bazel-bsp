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
    private let prepareHandler: PrepareHandler

    private weak var connection: LSPConnection?

    init(targetStore: BazelTargetStore, prepareHandler: PrepareHandler, connection: LSPConnection) {
        self.targetStore = targetStore
        self.prepareHandler = prepareHandler
        self.connection = connection
    }

    func onWatchedFilesDidChange(_: OnWatchedFilesDidChangeNotification) throws {
        // Invalidate the build cache so the next build request will actually run
        // No need to send `OnBuildTargetDidChangeNotification`
        // for cross-module changes to be picked up.
        prepareHandler.invalidateBuildCache()
    }
}
