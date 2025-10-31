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

enum PrepareHandlerError: Error, LocalizedError {
    case unexpectedBatching([String])

    var errorDescription: String? {
        switch self {
        case .unexpectedBatching(let labels): return "Unexpected batching of targets: \(labels.joined(separator: ", "))"
        }
    }
}

/// Handles the `buildTarget/prepare` request.
///
/// Builds the provided list of targets upon request.
final class PrepareHandler {
    private let initializedConfig: InitializedServerConfig
    private let targetStore: BazelTargetStore
    private let commandRunner: CommandRunner
    private weak var connection: LSPConnection?

    // When using remote caching, we need certain types of files to always be available locally
    // so that sourcekit-lsp's manual index builds can work.
    // Original list was inherited from rules_xcodeproj.
    static let additionalBuildFlags: [String] = [
        "--remote_download_regex='.*\\.indexstore/.*|.*\\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$'"
    ]

    // Allow prepare requests to be overridden if needed.
    static let additionalStartupFlags: [String] = [
        "--preemptible"
    ]

    // The current Bazel build is always stored so that we can cancel it if requested by the LSP.
    private var currentTaskLock = OSAllocatedUnfairLock<(RunningProcess, RequestID)?>(initialState: nil)

    init(
        initializedConfig: InitializedServerConfig,
        targetStore: BazelTargetStore,
        commandRunner: CommandRunner = ShellCommandRunner(),
        connection: LSPConnection? = nil,
    ) {
        self.initializedConfig = initializedConfig
        self.targetStore = targetStore
        self.commandRunner = commandRunner
        self.connection = connection
    }

    func prepareTarget(
        _ request: BuildTargetPrepareRequest,
        _ id: RequestID,
        _ reply: @escaping (Result<VoidResponse, Error>) -> Void
    ) {
        let targetsToBuild = request.targets
        guard !targetsToBuild.isEmpty else {
            logger.info("No targets to build.")
            reply(.success(VoidResponse()))
            return
        }
        let taskId = TaskId(id: "buildPrepare-\(id.description)")
        var didStartTask = false
        do {
            let platformInfo = try targetStore.stateLock.withLockUnchecked {
                return try targetsToBuild.map {
                    try targetStore.platformBuildLabelInfo(forBSPURI: $0.uri)
                }
            }
            let taskTitle: String = makeTaskTitle(
                for: platformInfo,
                compileTopLevel: initializedConfig.baseConfig.compileTopLevel
            )
            connection?.startWorkTask(
                id: taskId,
                title: taskTitle
            )
            didStartTask = true
            let labelsToBuild: [String]
            let extraArgs: [String]
            if initializedConfig.baseConfig.compileTopLevel {
                labelsToBuild = platformInfo.map { $0.topLevelParentLabel }
                extraArgs = []  // Not applicable in this case
            } else {
                guard platformInfo.count == 1 else {
                    // Should not happen as we force the batch size to 1 in this case,
                    // but catching it just in case.
                    throw PrepareHandlerError.unexpectedBatching(platformInfo.map { $0.label })
                }
                let infoToBuild = platformInfo[0]
                labelsToBuild = [infoToBuild.label]
                extraArgs = buildArgs(
                    topLevelParentRuleType: infoToBuild.topLevelParentRuleType,
                    minimumOsVersion: infoToBuild.topLevelParentConfig.minimumOsVersion
                )
            }
            nonisolated(unsafe) let reply = reply
            try build(
                bazelLabels: labelsToBuild,
                extraArgs: extraArgs,
                id: id
            ) { [connection] error in
                if let error = error {
                    connection?.finishTask(id: taskId, status: .error)
                    reply(.failure(error))
                }
                connection?.finishTask(id: taskId, status: .ok)
                reply(.success(VoidResponse()))
            }
        } catch {
            if didStartTask {
                connection?.finishTask(id: taskId, status: .error)
            }
            reply(.failure(error))
        }
    }

    func build(
        bazelLabels labelsToBuild: [String],
        extraArgs: [String],
        id: RequestID,
        completion: @escaping ((ResponseError?) -> Void)
    ) throws {
        logger.info("Will build \(labelsToBuild.joined(separator: ", "), privacy: .public)")

        let extraArgsSuffix: String = {
            if extraArgs.isEmpty {
                return ""
            } else {
                return " \(extraArgs.joined(separator: " "))"
            }
        }()

        nonisolated(unsafe) let completion = completion
        try currentTaskLock.withLock { [commandRunner, initializedConfig] currentTask in
            let process = try commandRunner.bazelIndexAction(
                baseConfig: initializedConfig.baseConfig,
                outputBase: initializedConfig.outputBase,
                cmd: "build \(labelsToBuild.joined(separator: " "))\(extraArgsSuffix)",
                rootUri: initializedConfig.rootUri,
                additionalFlags: Self.additionalBuildFlags,
                additionalStartupFlags: Self.additionalStartupFlags
            )
            process.setTerminationHandler { code, stderr in
                if code == 0 {
                    logger.info("Finished building! (Request ID: \(id.description, privacy: .public))")
                    completion(nil)
                } else {
                    if code == 8 {
                        logger.info("Build (Request ID: \(id.description, privacy: .public)) was cancelled.")
                        completion(ResponseError.cancelled)
                    } else {
                        logger.logFullObjectInMultipleLogMessages(
                            level: .error,
                            header: "Failed to build targets.",
                            stderr
                        )
                        completion(ResponseError(code: .internalError, message: "The bazel build failed."))
                    }
                }
            }
            currentTask = (process, id)
        }
    }

    func buildArgs(
        topLevelParentRuleType: TopLevelRuleType,
        minimumOsVersion: String
    ) -> [String] {
        // As of writing, Bazel does not provides a "build X as if it were a child of Y" flag.
        // This means that to compile individual libraries accurately, we need to replicate
        // all the transitions that are applied by ios_application rules and friends.
        // https://github.com/bazelbuild/rules_apple/blob/716568e34b158d67adf83b64d2cea5ea142b641f/apple/internal/transition_support.bzl#L30
        let platform = topLevelParentRuleType.platform
        let cpuPrefix = topLevelParentRuleType.cpuPrefix
        let cpu = topLevelParentRuleType.cpu
        let cpuFlag = topLevelParentRuleType.cpuFlagName
        let minimumOsVersion = minimumOsVersion
        return [
            "--platforms=@build_bazel_apple_support//platforms:\(platform)_\(cpu)",
            "--\(platform)_\(cpuFlag)=\(cpu)",
            "--apple_platform_type=\(platform)",
            "--apple_split_cpu=\(cpu)",
            "--\(platform)_minimum_os=\"\(minimumOsVersion)\"",
            "--cpu=\(cpuPrefix)_\(cpu)",
            "--minimum_os_version=\"\(minimumOsVersion)\"",
        ]
    }

    func makeTaskTitle(
        for platformInfo: [BazelTargetPlatformInfo],
        compileTopLevel: Bool
    ) -> String {
        if compileTopLevel {
            let targetLabels = Set(platformInfo.map { $0.topLevelParentLabel }).sorted()
            let targetNames = targetLabels.joined(separator: ", ")
            return "sourcekit-bazel-bsp: Building \(targetLabels.count) target(s): \(targetNames)"
        } else {
            let targetLabels = platformInfo.map { $0.label }
            let targetNames = targetLabels.joined(separator: ", ")
            return "sourcekit-bazel-bsp: Building \(targetLabels.count) target(s): \(targetNames)"
        }
    }
}

// When the user changes targets in the IDE in the middle of a background index request,
// the LSP asks us to cancel the background one to be able to prioritize the IDE one.
extension PrepareHandler: CancelRequestObserver {
    func cancel(request: RequestID) throws {
        currentTaskLock.withLock { currentTaskData in
            guard let data = currentTaskData else {
                return
            }
            guard data.1 == request else {
                return
            }
            data.0.terminate()
            currentTaskData = nil
        }
    }
}
