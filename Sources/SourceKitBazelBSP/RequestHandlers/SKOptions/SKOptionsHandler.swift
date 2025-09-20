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
    case noTargetsToRequest

    var errorDescription: String? {
        switch self {
        case .noTargetsToRequest:
            return "Request to query compiler arguments, but no top level labels are available!"
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
    private var didPreloadAllCompilerArgs = false

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

    func preloadAllCompilerArgs() {
        guard !didPreloadAllCompilerArgs else {
            return
        }
        logger.info("Will preload compiler arguments")
        let taskId = TaskId(id: "getSKOptions-preload")
        connection?.startWorkTask(id: taskId, title: "sourcekit-bazel-bsp: Preloading compiler arguments...")
        let allTopLevelLabels = targetStore.stateLock.withLockUnchecked {
            return targetStore.topLevelLabelsData()
        }.map { $0.0 }
        extractor.runAqueryForArgsExtraction(withTargets: allTopLevelLabels)
        connection?.finishTask(id: taskId, status: .ok)
        didPreloadAllCompilerArgs = true
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
        preloadAllCompilerArgs()

        let targetUri = request.target.uri
        let (bazelTarget, platformInfo) = try targetStore.stateLock.withLockUnchecked {
            let bazelTarget = try targetStore.bazelTargetLabel(forBSPURI: targetUri)
            let platformInfo = try targetStore.platformBuildLabelInfo(forBSPURI: targetUri)
            return (bazelTarget, platformInfo)
        }

        logger.info(
            "Fetching SKOptions for \(targetUri.stringValue), target: \(bazelTarget), language: \(request.language)"
        )

        let args =
            try extractor.compilerArgs(
                forDoc: request.textDocument.uri,
                inTarget: bazelTarget,
                buildingUnder: platformInfo,
                language: request.language,
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
            preloadAllCompilerArgs()
        }
    }
}

extension SKOptionsHandler: DidInitializeObserver {
    func didInitializeHandlerFinishedPreparations() {
        // Get a headstart by immediately running all the aqueries we need.
        stateLock.withLockUnchecked {
            preloadAllCompilerArgs()
        }
    }
}
