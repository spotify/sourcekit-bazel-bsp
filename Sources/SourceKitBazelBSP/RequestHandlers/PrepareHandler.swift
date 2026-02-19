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
            logger.debug("No targets to build.")
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

            var labelsToBuild: [[String]] = []
            var extraArgs: [[String]] = []
            if initializedConfig.baseConfig.compileTopLevel {
                // Build entire top-level targets
                let topLevelLabelsToBuild = Set(platformInfo.map { $0.topLevelParentLabel })
                labelsToBuild = [topLevelLabelsToBuild.sorted()]
                extraArgs = [[]]
            } else {
                // Separate top-level targets (build directly) from libraries (use aspect)
                var topLevelTargets: Set<String> = []
                var parentToLibraryLabelsMap: [String: [String]] = [:]

                for info in platformInfo {
                    if info.label == info.topLevelParentLabel {
                        // This is a top-level target (app, extension, test) - build directly
                        topLevelTargets.insert(info.label)
                    } else {
                        // This is a library - use aspect approach
                        parentToLibraryLabelsMap[info.topLevelParentLabel, default: []].append(info.label)
                    }
                }

                // Add direct builds for top-level targets (no aspects needed)
                if !topLevelTargets.isEmpty {
                    labelsToBuild.append(topLevelTargets.sorted())
                    extraArgs.append([])
                }

                // Add aspect builds for libraries
                for (parent, libraries) in parentToLibraryLabelsMap {
                    let outputGroups = libraries.map { Self.sanitizeLabel($0) }.joined(separator: ",")
                    labelsToBuild.append([parent])
                    extraArgs.append([
                        "--aspects=//.bsp/skbsp_generated:aspect.bzl%platform_deps_aspect",
                        "--output_groups=\(outputGroups)",
                    ])
                }
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
        bazelLabels labelsToBuild: [[String]],
        extraArgs: [[String]],
        id: RequestID,
        completion: @escaping ((ResponseError?) -> Void)
    ) throws {
        if labelsToBuild.count == 1 {
            logger.debug("Will build \(labelsToBuild[0].joined(separator: ", "), privacy: .public)")
        } else {
            logger.debug(
                "Will build \(labelsToBuild.flatMap { $0 }.joined(separator: ", "), privacy: .public) over \(labelsToBuild.count, privacy: .public) invocations"
            )
        }

        nonisolated(unsafe) var cmds = [String]()
        for i in 0..<labelsToBuild.count {
            let labels = labelsToBuild[i]
            let args = extraArgs[i]
            let extraArgsSuffix: String = {
                guard args.isEmpty else {
                    return " \(args.joined(separator: " "))"
                }
                return ""
            }()
            cmds.append("build \(labels.joined(separator: " "))\(extraArgsSuffix)")
        }

        nonisolated(unsafe) let completion = completion
        try currentTaskLock.withLock { [commandRunner, initializedConfig] currentTask in
            let process = try commandRunner.chainedBazelIndexActions(
                baseConfig: initializedConfig.baseConfig,
                outputBase: initializedConfig.outputBase,
                cmds: cmds,
                rootUri: initializedConfig.rootUri,
                additionalFlags: Self.additionalBuildFlags,
                additionalStartupFlags: Self.additionalStartupFlags
            )
            process.setTerminationHandler { code, stderr in
                if code == 0 {
                    logger.debug("Finished building! (Request ID: \(id.description, privacy: .public))")
                    completion(nil)
                } else {
                    if code == 8 {
                        logger.debug("Build (Request ID: \(id.description, privacy: .public)) was cancelled.")
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

    /// Converts a Bazel label to a safe output group name with aspect prefix.
    /// Example: //path/to/library:LibraryName -> aspect_path_to_library_LibraryName
    static func sanitizeLabel(_ label: String) -> String {
        var sanitized = label
        if sanitized.hasPrefix("//") {
            sanitized = String(sanitized.dropFirst(2))
        }
        return "aspect_"
            + sanitized
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    func makeTaskTitle(
        for platformInfo: [BazelTargetPlatformInfo],
        compileTopLevel: Bool
    ) -> String {
        guard !compileTopLevel else {
            let topLevelLabels = Set(platformInfo.map { $0.topLevelParentLabel }).sorted()
            let topLevelNames = topLevelLabels.joined(separator: ", ")
            return "sourcekit-bazel-bsp: Building \(topLevelLabels.count) top-level target(s): \(topLevelNames)"
        }
        let targetLabels = platformInfo.map { $0.label }
        let targetNames = targetLabels.joined(separator: ", ")
        return "sourcekit-bazel-bsp: Building \(targetLabels.count) target(s): \(targetNames)"
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
