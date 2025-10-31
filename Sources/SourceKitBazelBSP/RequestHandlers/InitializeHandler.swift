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

package let sourcekitBazelBSPVersion = "0.2.0"
private let logger = makeFileLevelBSPLogger()

enum InitializeHandlerError: Error, LocalizedError {
    case toolchainNotFound(String)

    var errorDescription: String? {
        switch self {
        case .toolchainNotFound(let path): return "Could not determine Xcode toolchain location from path: \(path)"
        }
    }
}

/// Handles the `initialize` request.
///
/// This is the first request that the LSP sends, and it contains the initial configuration
/// for the server. We gather all information needed to operate the server, return it to the LSP,
/// and then register the other handlers that will handle the rest of the requests.
final class InitializeHandler {

    private let baseConfig: BaseServerConfig
    private let commandRunner: CommandRunner

    private weak var connection: LSPConnection?

    init(
        baseConfig: BaseServerConfig,
        commandRunner: CommandRunner = ShellCommandRunner(),
        connection: LSPConnection? = nil,
    ) {
        self.baseConfig = baseConfig
        self.commandRunner = commandRunner
        self.connection = connection
    }

    func initializeBuild(
        _ request: InitializeBuildRequest,
        _ id: RequestID,
    ) throws -> (InitializeBuildResponse, InitializedServerConfig) {
        let taskId = TaskId(id: "initializeBuild-\(id.description)")
        connection?.startWorkTask(id: taskId, title: "sourcekit-bazel-bsp: Initializing...")
        do {
            let initializedConfig = try makeInitializedConfig(fromRequest: request, baseConfig: baseConfig)
            let result = buildResponse(fromRequest: request, and: initializedConfig)
            connection?.finishTask(id: taskId, status: .ok)
            return (result, initializedConfig)
        } catch {
            connection?.finishTask(id: taskId, status: .error)
            throw error
        }
    }

    func makeInitializedConfig(
        fromRequest request: InitializeBuildRequest,
        baseConfig: BaseServerConfig,
    ) throws -> InitializedServerConfig {
        let rootUri = request.rootUri.arbitrarySchemeURL.path
        logger.debug("rootUri: \(rootUri, privacy: .public)")
        let regularOutputBase = URL(
            fileURLWithPath: try commandRunner.bazel(baseConfig: baseConfig, rootUri: rootUri, cmd: "info output_base")
        )
        logger.debug("regularOutputBase: \(regularOutputBase, privacy: .public)")

        // Setup the special output base path where we will run indexing commands from.
        let regularOutputBaseLastPath = regularOutputBase.lastPathComponent
        let outputBase = regularOutputBase.deletingLastPathComponent().appendingPathComponent(
            "\(regularOutputBaseLastPath)-sourcekit-bazel-bsp"
        ).path
        logger.debug("outputBase: \(outputBase, privacy: .public)")

        // Now, get the full output path based on the above output base.
        let outputPath: String = try commandRunner.bazelIndexAction(
            baseConfig: baseConfig,
            outputBase: outputBase,
            cmd: "info output_path",
            rootUri: rootUri
        )
        logger.debug("outputPath: \(outputPath, privacy: .public)")

        // Get the execution root based on the above output base.
        let executionRoot: String = try commandRunner.bazelIndexAction(
            baseConfig: baseConfig,
            outputBase: outputBase,
            cmd: "info execution_root",
            rootUri: rootUri
        )
        logger.debug("executionRoot: \(executionRoot, privacy: .public)")

        // Collecting the rest of the env's details
        let devDir: String = try commandRunner.run("xcode-select --print-path")
        let toolchain = try getToolchainPath(with: commandRunner)
        let sdkRootPaths: [String: String] = getSDKRootPaths(with: commandRunner)

        logger.debug("devDir: \(devDir, privacy: .public)")
        logger.debug("toolchain: \(toolchain, privacy: .public)")
        logger.debug("sdkRootPaths: \(sdkRootPaths, privacy: .public)")

        return InitializedServerConfig(
            baseConfig: baseConfig,
            rootUri: rootUri,
            outputBase: outputBase,
            outputPath: outputPath,
            devDir: devDir,
            devToolchainPath: toolchain,
            executionRoot: executionRoot,
            sdkRootPaths: sdkRootPaths
        )
    }

    func getToolchainPath(with commandRunner: CommandRunner) throws -> String {
        // Trick to get the Xcode toolchain path, since there's no dedicated command for it
        // In theory this should be just devDir + Toolchains/XcodeDefault.xctoolchain,
        // but I think we should make it dynamic just in case
        let swiftPath: String = try commandRunner.run("xcrun --find swift")
        let expectedSwiftPathSuffix = "usr/bin/swift"
        guard swiftPath.hasSuffix(expectedSwiftPathSuffix) else {
            throw InitializeHandlerError.toolchainNotFound(swiftPath)
        }
        let toolchain = swiftPath.dropLast(expectedSwiftPathSuffix.count)
        return String(toolchain)
    }

    func getSDKRootPaths(with commandRunner: CommandRunner) -> [String: String] {
        let supportedSDKTypes = Set(TopLevelRuleType.allCases.map { $0.sdkName }).sorted()
        let sdkRootPaths: [String: String] = supportedSDKTypes.reduce(into: [:]) { result, sdkType in
            // This will fail if the user doesn't have the SDK installed, which is fine.
            guard let sdkRootPath: String? = try? commandRunner.run("xcrun --sdk \(sdkType) --show-sdk-path") else {
                return
            }
            result[sdkType] = sdkRootPath
        }
        return sdkRootPaths
    }

    func buildResponse(
        fromRequest request: InitializeBuildRequest,
        and initializedConfig: InitializedServerConfig,
    ) -> InitializeBuildResponse {
        let capabilities = request.capabilities
        let watchers: [FileSystemWatcher]?
        let rootUri = initializedConfig.rootUri
        if let filesToWatch = initializedConfig.baseConfig.filesToWatch {
            watchers = filesToWatch.components(separatedBy: ",").map {
                FileSystemWatcher(
                    globPattern: rootUri + "/" + $0,
                    kind: [.change, .create, .delete]
                )
            }
        } else {
            watchers = nil
        }
        let batchSize: Int? = {
            let compileTopLevel = initializedConfig.baseConfig.compileTopLevel
            let indexBuildBatchSize = initializedConfig.baseConfig.indexBuildBatchSize
            if compileTopLevel == false && indexBuildBatchSize != nil {
                // FIXME: It's possible to support this, just doing one thing at a time for simplicity.
                logger.warning("Ignoring indexBuildBatchSize: Currently only supported for --compile-top-level.")
            }
            if compileTopLevel == false {
                return 1
            } else {
                return indexBuildBatchSize
            }
        }()
        return InitializeBuildResponse(
            displayName: "sourcekit-bazel-bsp",
            version: sourcekitBazelBSPVersion,
            bspVersion: "2.2.0",
            capabilities: BuildServerCapabilities(
                compileProvider: .init(languageIds: capabilities.languageIds),
                testProvider: .init(languageIds: capabilities.languageIds),
                runProvider: .init(languageIds: capabilities.languageIds),
                debugProvider: .init(languageIds: capabilities.languageIds),
                inverseSourcesProvider: true,
                dependencySourcesProvider: true,
                resourcesProvider: true,
                outputPathsProvider: false,
                buildTargetChangedProvider: true,
                canReload: true,
            ),
            dataKind: InitializeBuildResponseDataKind.sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: initializedConfig.indexDatabasePath,
                indexStorePath: initializedConfig.indexStorePath,
                multiTargetPreparation: MultiTargetPreparationSupport(
                    supported: true,
                    batchSize: batchSize
                ),
                outputPathsProvider: nil,
                prepareProvider: true,
                sourceKitOptionsProvider: true,
                watchers: watchers,
            ).encodeToLSPAny()
        )
    }
}
