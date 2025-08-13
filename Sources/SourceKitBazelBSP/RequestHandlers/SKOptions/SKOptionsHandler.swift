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

private let logger = makeFileLevelBSPLogger()

/// Handles the `textDocument/sourceKitOptions` request.
///
/// Returns the compiler arguments for the provided target based on previously gathered information.
final class SKOptionsHandler: InvalidatedTargetObserver {

    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let extractor: BazelTargetCompilerArgsExtractor

    private weak var connection: LSPConnection?

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
        let taskId = TaskId(id: "getSKOptions-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "Indexing: Getting compiler arguments")
        do {
            let result = try handle(request: request)
            connection?.finishTask(id: taskId, status: .ok)
            return result
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func handle(request: TextDocumentSourceKitOptionsRequest) throws -> TextDocumentSourceKitOptionsResponse? {
        let targetUri = request.target.uri
        let bazelTarget = try targetStore.platformBuildLabel(forBSPURI: targetUri)
        let underlyingLibrary = try targetStore.bazelTargetLabel(forBSPURI: targetUri)

        logger.info(
            "Fetching SKOptions for \(targetUri.stringValue), target: \(bazelTarget), language: \(request.language)"
        )

        let args =
            try extractor.compilerArgs(
                forDoc: request.textDocument.uri,
                inTarget: bazelTarget,
                underlyingLibrary: underlyingLibrary,
                language: request.language
            ) ?? []

        // If no compiler arguments are found, return nil to avoid sourcekit indexing with no input files
        guard !args.isEmpty else {
            return nil
        }
        return TextDocumentSourceKitOptionsResponse(
            compilerArguments: args,
            workingDirectory: initializedConfig.rootUri
        )
    }

    // MARK: - InvalidatedTargetObserver

    func invalidate(targets: Set<AffectedTarget>) throws {
        // Only clear cache if at least one file was created or deleted
        if targets.contains(where: { $0.kind == .created || $0.kind == .deleted }) {
            extractor.clearCache()
        }
    }
}
