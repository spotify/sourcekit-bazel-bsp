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
import LanguageServerProtocolJSONRPC
import os

protocol BSPServerMessageHandler: MessageHandler {
    // FIXME: Should work without locking
    var lock: OSAllocatedUnfairLock<Void> { get }

    // Requests
    func initializeBuild(_ request: InitializeBuildRequest, _ id: RequestID) throws
        -> InitializeBuildResponse
    func waitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest, _ id: RequestID
    ) -> VoidResponse
    func buildShutdown(_ request: BuildShutdownRequest, _ id: RequestID) throws
        -> VoidResponse
    func workspaceBuildTargets(
        _ request: WorkspaceBuildTargetsRequest, _ id: RequestID
    ) throws -> WorkspaceBuildTargetsResponse
    func buildTargetSources(_ request: BuildTargetSourcesRequest, _ id: RequestID) throws
        -> BuildTargetSourcesResponse
    func textDocumentSourceKitOptions(
        _ request: TextDocumentSourceKitOptionsRequest, _ id: RequestID
    ) throws -> TextDocumentSourceKitOptionsResponse?
    func prepareTarget(_ request: BuildTargetPrepareRequest, _ id: RequestID) throws
        -> VoidResponse

    // Notifications
    func onBuildInitialized(_ notification: OnBuildInitializedNotification) throws
    func onBuildExit(_ notification: OnBuildExitNotification) throws
    func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws
    func cancelRequest(_ notification: CancelRequestNotification) throws
}

extension BSPServerMessageHandler {
    func handle(_ notification: some NotificationType) {
        // FIXME: Should work without locking
        lock.lock()
        defer { lock.unlock() }
        logger.info("Handling notification: \(type(of: notification).method, privacy: .public)")
        do {
            switch notification {
            case let notification as CancelRequestNotification:
                try self.cancelRequest(notification)
            case let notification as OnBuildExitNotification:
                try self.onBuildExit(notification)
            case let notification as OnBuildInitializedNotification:
                try self.onBuildInitialized(notification)
            case let notification as OnWatchedFilesDidChangeNotification:
                try self.onWatchedFilesDidChange(notification)
            default:
                throw ResponseError.methodNotFound(type(of: notification).method)
            }
        } catch {
            logger.error("Error while handling BSP notification: \(error)")
        }
    }

    func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping (LSPResult<Request.Response>) -> Void
    ) {
        // FIXME: Should work without locking
        lock.lock()
        defer { lock.unlock() }
        let method = type(of: request).method
        func handle<R: RequestType>(
            _ request: R, using handler: @escaping (R, RequestID) throws -> R.Response
        ) {
            do {
                let response = try handler(request, id) as! Request.Response
                logger.info("Responding to \(method, privacy: .public)")
                reply(.success(response))
            } catch {
                let msg = "Error while responding to \(method): \(error.localizedDescription)"
                logger.error("\(msg, privacy: .public)")
                reply(.failure(ResponseError(code: .internalError, message: msg)))  // FIX ME
            }
        }
        let requestType = String(describing: type(of: request))
        logger.info(
            "Handling request: \(method, privacy: .public) (\(requestType, privacy: .public))"
        )
        switch request {
        case let request as BuildShutdownRequest:
            handle(request, using: self.buildShutdown)
        case let request as BuildTargetSourcesRequest:
            handle(request, using: self.buildTargetSources)
        case let request as InitializeBuildRequest:
            handle(request, using: self.initializeBuild)
        case let request as TextDocumentSourceKitOptionsRequest:
            handle(request, using: self.textDocumentSourceKitOptions)
        case let request as WorkspaceBuildTargetsRequest:
            handle(request, using: self.workspaceBuildTargets)
        case let request as WorkspaceWaitForBuildSystemUpdatesRequest:
            handle(request, using: self.waitForBuildSystemUpdates)
        case let request as BuildTargetPrepareRequest:
            handle(request, using: self.prepareTarget)
        default:
            logger.error("Unexpected request: \(method, privacy: .public)")
            reply(.failure(ResponseError.methodNotFound(type(of: request).method)))
        }
    }
}
