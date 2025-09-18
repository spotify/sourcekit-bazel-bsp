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

/// Handles the `build/initialized` notification.
///
/// This is called right after returning from the `initialize` request.
/// We use this to warm-up the bazel cache for our special output bases.
final class DidInitializeHandler: @unchecked Sendable {

    private let initializedConfig: InitializedServerConfig
    private let commandRunner: CommandRunner

    private var buildWarmupJob: RunningProcess?
    private var aqueryWarmupJob: RunningProcess?

    init(
        initializedConfig: InitializedServerConfig,
        commandRunner: CommandRunner = ShellCommandRunner(),
    ) {
        self.initializedConfig = initializedConfig
        self.commandRunner = commandRunner
    }

    func onDidInitialize(_ notification: OnBuildInitializedNotification) throws {
        // Warm-up our special output bases.
        guard let targetToUse = initializedConfig.baseConfig.targets.first else {
            return
        }
        logger.info("Warming up output bases with \(targetToUse)")
        buildWarmupJob = try? commandRunner.bazelIndexAction(
            baseConfig: initializedConfig.baseConfig,
            outputBase: initializedConfig.outputBase,
            cmd: "query \(targetToUse)",
            rootUri: initializedConfig.rootUri
        )
        buildWarmupJob?.setTerminationHandler { [weak self, initializedConfig] code, stderr in
            if code == 0 {
                logger.info("Finished warming up the build output base!")
            } else {
                logger.logFullObjectInMultipleLogMessages(
                    level: .error,
                    header: "Failed to warm up the build output base.",
                    stderr
                )
            }
            self?.buildWarmupJob = nil
            guard initializedConfig.aqueryOutputBase != initializedConfig.outputBase else {
                return
            }
            // FIXME: We have to warm up the aqueries *after* the build, otherwise we can run
            // into some weird race condition with rules_swift I'm not sure about.
            self?.aqueryWarmupJob = try? self?.commandRunner.bazelIndexAction(
                baseConfig: initializedConfig.baseConfig,
                outputBase: initializedConfig.aqueryOutputBase,
                cmd: "query \(targetToUse)",
                rootUri: initializedConfig.rootUri
            )
            self?.aqueryWarmupJob?.setTerminationHandler { [weak self] code, stderr in
                if code == 0 {
                    logger.info("Finished warming up the aquery output base!")
                } else {
                    logger.logFullObjectInMultipleLogMessages(
                        level: .error,
                        header: "Failed to warm up the aquery output base.",
                        stderr
                    )
                }
                self?.aqueryWarmupJob = nil
            }
        }
    }
}
