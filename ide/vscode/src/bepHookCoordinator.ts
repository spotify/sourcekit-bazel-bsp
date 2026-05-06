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

import * as vscode from "vscode";
import { execFile } from "child_process";
import { BepWatcher, TargetCompletedEvent, TestSummaryEvent } from "./bepWatcher";
import { Configuration } from "./configuration";

export class BepHookCoordinator implements vscode.Disposable {
    private readonly disposables: vscode.Disposable[] = [];

    constructor(
        bepWatcher: BepWatcher,
        private readonly config: Configuration,
        private readonly outputChannel: vscode.OutputChannel,
    ) {
        this.disposables.push(
            bepWatcher.onTargetCompleted((e) => this.handleTargetCompleted(e)),
            bepWatcher.onTestSummary((e) => this.handleTestSummary(e)),
        );
    }

    private handleTargetCompleted(event: TargetCompletedEvent): void {
        const command = event.success
            ? this.config.hookBuildSuccess
            : this.config.hookBuildFailure;

        this.runHook(command, {
            SKBSP_LABEL: event.label,
        });
    }

    private handleTestSummary(event: TestSummaryEvent): void {
        const command = event.success
            ? this.config.hookTestSuccess
            : this.config.hookTestFailed;

        this.runHook(command, {
            SKBSP_LABEL: event.label,
            SKBSP_TEST_STATUS: event.status,
        });
    }

    private runHook(command: string, extraEnv: Record<string, string>): void {
        if (!command || !vscode.workspace.isTrusted) {
            return;
        }

        const [program, ...args] = command.split(/\s+/);
        if (!program) {
            return;
        }

        this.outputChannel.appendLine(`[hook] Running hook for ${extraEnv.SKBSP_LABEL}`);

        execFile(program, args, {
            env: { ...process.env, ...extraEnv },
        }, (error) => {
            if (error) {
                this.outputChannel.appendLine(`[hook] Hook failed: ${error.message}`);
            }
        });
    }

    dispose(): void {
        for (const d of this.disposables) {
            d.dispose();
        }
    }
}
