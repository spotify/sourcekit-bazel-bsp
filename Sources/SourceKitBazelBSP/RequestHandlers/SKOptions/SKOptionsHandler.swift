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

    func textDocumentSourceKitOptions(
        _ request: TextDocumentSourceKitOptionsRequest,
        _ id: RequestID
    ) throws -> TextDocumentSourceKitOptionsResponse? {
        // This request doesn't publish a task progress report to the IDE because it's very spammy.
        do {
            let result = try stateLock.withLockUnchecked {
                let result = try handle(request: request)
                return result
            }
            return result
        } catch {
            throw error
        }
    }

    func handle(request: TextDocumentSourceKitOptionsRequest) throws -> TextDocumentSourceKitOptionsResponse? {
        let targetUri = request.target.uri
        let (platformInfo, aqueryResult) = try targetStore.stateLock.withLockUnchecked {
            let platformInfo = try targetStore.platformBuildLabelInfo(forBSPURI: targetUri)
            let aqueryResult = try targetStore.targetsAqueryForArgsExtraction()
            return (platformInfo, aqueryResult)
        }

        let strategy = try extractor.getParsingStrategy(
            for: request.textDocument.uri,
            language: request.language,
            targetUri: request.target.uri
        )

        let args = try extractor.extractCompilerArgs(
            fromAquery: aqueryResult,
            forTarget: platformInfo,
            withStrategy: strategy,
        )

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
        }
    }
}
