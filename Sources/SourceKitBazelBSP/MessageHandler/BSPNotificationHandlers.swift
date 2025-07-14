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

// Registry of all BSP notifications that sourcekit-lsp expects (and that we can handle).

typealias BSPNotificationHandler<Notification: NotificationType> = (Notification) throws -> Void

typealias CancelRequestNotificationHandler = BSPNotificationHandler<CancelRequestNotification>
typealias OnBuildExitNotificationHandler = BSPNotificationHandler<OnBuildExitNotification>
typealias OnBuildInitializedNotificationHandler = BSPNotificationHandler<
    OnBuildInitializedNotification
>
typealias OnWatchedFilesDidChangeNotificationHandler = BSPNotificationHandler<
    OnWatchedFilesDidChangeNotification
>

extension BSPMessageHandler {
    final class NotificationHandlers {
        let cancelRequest: CancelRequestNotificationHandler?
        let onBuildExit: OnBuildExitNotificationHandler?
        let onBuildInitialized: OnBuildInitializedNotificationHandler?
        let onWatchedFilesDidChange: OnWatchedFilesDidChangeNotificationHandler?

        init(
            cancelRequest: CancelRequestNotificationHandler? = nil,
            onBuildExit: OnBuildExitNotificationHandler? = nil,
            onBuildInitialized: OnBuildInitializedNotificationHandler? = nil,
            onWatchedFilesDidChange: OnWatchedFilesDidChangeNotificationHandler? = nil
        ) {
            self.cancelRequest = cancelRequest
            self.onBuildExit = onBuildExit
            self.onBuildInitialized = onBuildInitialized
            self.onWatchedFilesDidChange = onWatchedFilesDidChange
        }
    }
}
