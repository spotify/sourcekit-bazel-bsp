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

import struct os.OSAllocatedUnfairLock

private let logger = makeFileLevelBSPLogger()

enum SKOptionsHandlerError: Error, LocalizedError {
    case noTargetsToRequest(String)

    var errorDescription: String? {
        switch self {
        case .noTargetsToRequest(let platform): return "Request to query \(platform), but no targets of that platform are available!"
        }
    }
}

/// Handles the `textDocument/sourceKitOptions` request.
///
/// Returns the compiler arguments for the provided target based on previously gathered information.
final class SKOptionsHandler {

    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let extractor: BazelTargetCompilerArgsExtractor

    private weak var connection: LSPConnection?

    // This request needs synchronization because we might be requested to wipe the cache
    // in the middle of the request.
    private let stateLock = OSAllocatedUnfairLock()

    init(
        initializedConfig: InitializedServerConfig,
        targetStore: BazelTargetStore,
        extractor: BazelTargetCompilerArgsExtractor? = nil,
        connection: LSPConnection? = nil,
    ) {
        self.initializedConfig = initializedConfig
        self.targetStore = targetStore
        self.extractor = extractor ?? BazelTargetCompilerArgsExtractor(config: initializedConfig)
        self.connection = connection
    }

    func preloadAllCompilerArgs() throws {
        let platformsToTargets = targetStore.stateLock.withLockUnchecked {
            return targetStore.platformsToTopLevelLabelsMap
        }
        // Run one query per platform+targets combo.
        // We need the queries to be separated by platform to account for
        // libraries shared across platforms.
        for (_, targets) in platformsToTargets {
            _ = try extractor.runAqueryForArgsExtraction(withTargets: targets)
        }
    }

    func textDocumentSourceKitOptions(
        _ request: TextDocumentSourceKitOptionsRequest,
        _ id: RequestID
    ) throws -> TextDocumentSourceKitOptionsResponse? {
        let taskId = TaskId(id: "getSKOptions-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "sourcekit-bazel-bsp: Fetching compiler arguments...")
        do {
            let result = try stateLock.withLockUnchecked {
                let result = try handle(request: request)
                connection?.finishTask(id: taskId, status: .ok)
                return result
            }
            return result
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func handle(request: TextDocumentSourceKitOptionsRequest) throws -> TextDocumentSourceKitOptionsResponse? {
        let (targetUri, bazelTarget, topLevelRuleType, underlyingLibrary, targetsToQuery) = try targetStore.stateLock.withLockUnchecked {
            let targetUri = request.target.uri
            let (bazelTarget, topLevelRule) = try targetStore.platformBuildLabel(forBSPURI: targetUri)
            let platform = topLevelRule.platform
            let underlyingLibrary = try targetStore.bazelTargetLabel(forBSPURI: targetUri)
            // We will request all top-level targets of this platform at once to maximize cache hits.
            let targetsToQuery = targetStore.platformsToTopLevelLabelsMap[platform] ?? []
            return (targetUri, bazelTarget, topLevelRule, underlyingLibrary, targetsToQuery)
        }

        guard !targetsToQuery.isEmpty else {
            // This should in theory never happen, but we should handle it just in case.
            throw SKOptionsHandlerError.noTargetsToRequest(topLevelRuleType.platform)
        }

        logger.info(
            "Fetching SKOptions for \(targetUri.stringValue), target: \(bazelTarget), language: \(request.language)"
        )

        let args =
            try extractor.compilerArgs(
                forDoc: request.textDocument.uri,
                inTarget: bazelTarget,
                underlyingLibrary: underlyingLibrary,
                language: request.language,
                topLevelRuleType: topLevelRuleType,
                targetsToQuery: targetsToQuery
            ) ?? []

        // If no compiler arguments are found, return nil to avoid sourcekit indexing with no input files
        guard !args.isEmpty else {
            return nil
        }
        return TextDocumentSourceKitOptionsResponse(
            compilerArguments: args,
            workingDirectory: initializedConfig.executionRoot
        )
    }
}

extension SKOptionsHandler: InvalidatedTargetObserver {
    func invalidate(targets: [InvalidatedTarget]) throws {
        // Only clear the cache if at least one file was created or deleted.
        // Otherwise, the compiler args are bound to be the same.
        guard targets.contains(where: { $0.kind == .created || $0.kind == .deleted }) else {
            return
        }
        stateLock.withLockUnchecked {
            extractor.clearCache()
            try? preloadAllCompilerArgs()
        }
    }
}

extension SKOptionsHandler: DidInitializeObserver {
    func didInitializeHandlerFinishedPreparations() {
        // Get a headstart by immediately running all the aqueries we need.
        stateLock.withLockUnchecked {
            try? preloadAllCompilerArgs()
        }
    }
}
