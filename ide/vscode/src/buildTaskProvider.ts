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
import * as path from "path";
import { ProcessedTarget } from "./graphProcessor";
import { Configuration } from "./configuration";
import { selectSimulator } from "./simulatorPicker";

const BUILD_TASK_TYPE = "sourcekit-bazel-bsp-build";

function getScriptPath(extensionPath: string, scriptName: string): string {
    return path.join(extensionPath, "scripts", scriptName);
}

export function getLaunchTaskLabel(targetLabel: string, withoutDebugging: boolean = false): string {
    if (withoutDebugging) {
        return `Run without debugging ${targetLabel}`;
    } else {
        // There is no way to completely hide a task, so we need to name it accordingly
        return `z_IGNORE_DO_NOT_USE_DIRECTLY_prelaunch_${targetLabel}`;
    }
}

export function getTestLaunchTaskLabel(targetLabel: string, withoutDebugging: boolean = false): string {
    if (withoutDebugging) {
        return `Test without debugging ${targetLabel}`;
    } else {
        // There is no way to completely hide a task, so we need to name it accordingly
        return `z_IGNORE_DO_NOT_USE_DIRECTLY_test_prelaunch_${targetLabel}`;
    }
}

function getExtraFlags(config: Configuration, target: ProcessedTarget): string {
    let extraFlags = target.extraBuildArgs.join(" ");
    if (config.extraBuildFlags.length > 0) {
        extraFlags += " " + config.extraBuildFlags;
    }
    if (target.type === "test" && config.extraTestBuildFlags.length > 0) {
        extraFlags += " " + config.extraTestBuildFlags;
    }
    return extraFlags;
}


function getLaunchArgs(config: Configuration, target: ProcessedTarget): string {
    let launchArgs = "";
    if (target.type === "test" && config.testArgs.length > 0) {
        launchArgs = config.testArgs;
    } else if (target.type !== "test" && config.launchArgs.length > 0) {
        launchArgs = config.launchArgs;
    }
    return launchArgs;
}

function createBuildTask(extensionPath: string, config: Configuration, target: ProcessedTarget, bazelWrapper: string): vscode.Task {
    const extraFlags = getExtraFlags(config, target);
    const env: Record<string, string> = {
        BAZEL_LABEL_TO_RUN: target.label,
        BAZEL_EXTRA_BUILD_FLAGS: extraFlags,
        BAZEL_EXECUTABLE: bazelWrapper,
        BAZEL_RULES_APPLE_NAME: config.rulesAppleName,
    };
    if (target.platform) {
        env.BAZEL_PLATFORM_TYPE = target.platform;
    }
    if (target.sdkName) {
        env.BAZEL_SDK_NAME = target.sdkName;
    }
    const task = new vscode.Task(
        { type: BUILD_TASK_TYPE, target: target.label },
        vscode.TaskScope.Workspace,
        `Build ${target.label}`,
        "sourcekit-bazel-bsp",
        new vscode.ShellExecution(getScriptPath(extensionPath, "lldb_build.sh"), { env })
    );
    task.group = vscode.TaskGroup.Build;
    task.problemMatchers = ["$sourcekit-bazel-bsp-bazelisk"];
    return task;
}

function createLaunchTask(extensionPath: string, config: Configuration, target: ProcessedTarget, bazelWrapper: string, withoutDebugging: boolean = false): vscode.Task {
    const taskLabel = getLaunchTaskLabel(target.label, withoutDebugging);
    const env: Record<string, string> = {
        BAZEL_LABEL_TO_RUN: target.label,
        BAZEL_LAUNCH_ARGS: getLaunchArgs(config, target),
        BAZEL_EXTRA_BUILD_FLAGS: getExtraFlags(config, target),
        BAZEL_RUN_MODE: "run",
        BAZEL_EXECUTABLE: bazelWrapper,
        BAZEL_RULES_APPLE_NAME: config.rulesAppleName,
    };
    if (target.platform) {
        env.BAZEL_PLATFORM_TYPE = target.platform;
    }
    if (target.sdkName) {
        env.BAZEL_SDK_NAME = target.sdkName;
    }
    if (withoutDebugging) {
        env.BAZEL_APPLE_RUN_WITHOUT_DEBUGGING = "1";
    }
    const task = new vscode.Task(
        { type: BUILD_TASK_TYPE, target: taskLabel, hide: !withoutDebugging },
        vscode.TaskScope.Workspace,
        taskLabel,
        "sourcekit-bazel-bsp",
        new vscode.ShellExecution(getScriptPath(extensionPath, "lldb_launch_and_debug.sh"), { env })
    );
    task.isBackground = true;
    task.presentationOptions = { reveal: vscode.TaskRevealKind.Always };
    task.problemMatchers = ["$sourcekit-bazel-bsp-launcher", "$sourcekit-bazel-bsp-launcher-bazelisk"];
    return task;
}

function createTestTask(extensionPath: string, config: Configuration, target: ProcessedTarget, bazelWrapper: string, withoutDebugging: boolean = false): vscode.Task {
    const taskLabel = getTestLaunchTaskLabel(target.label, withoutDebugging);
    const extraFlags = getExtraFlags(config, target);
    const launchArgs = getLaunchArgs(config, target);
    const env: Record<string, string> = {
        BAZEL_LABEL_TO_RUN: target.label,
        BAZEL_LAUNCH_ARGS: launchArgs,
        BAZEL_EXTRA_BUILD_FLAGS: extraFlags,
        BAZEL_RUN_MODE: "test",
        BAZEL_EXECUTABLE: bazelWrapper,
        BAZEL_RULES_APPLE_NAME: config.rulesAppleName,
    };
    if (target.platform) {
        env.BAZEL_PLATFORM_TYPE = target.platform;
    }
    if (target.sdkName) {
        env.BAZEL_SDK_NAME = target.sdkName;
    }
    if (withoutDebugging) {
        env.BAZEL_APPLE_RUN_WITHOUT_DEBUGGING = "1";
    }
    const task = new vscode.Task(
        { type: BUILD_TASK_TYPE, target: taskLabel, hide: !withoutDebugging },
        vscode.TaskScope.Workspace,
        taskLabel,
        "sourcekit-bazel-bsp",
        new vscode.ShellExecution(getScriptPath(extensionPath, "lldb_launch_and_debug.sh"), {
            env,
        })
    );
    if (withoutDebugging) {
        task.group = vscode.TaskGroup.Test;
    }
    task.problemMatchers = ["$sourcekit-bazel-bsp-launcher", "$sourcekit-bazel-bsp-launcher-bazelisk"];
    return task;
}

function createSimulatorTask(name: string): vscode.Task {
    const task = new vscode.Task(
        { type: BUILD_TASK_TYPE, target: name },
        vscode.TaskScope.Workspace,
        name,
        "sourcekit-bazel-bsp",
        new vscode.CustomExecution(async () => {
            return new (class implements vscode.Pseudoterminal {
                private writeEmitter = new vscode.EventEmitter<string>();
                private closeEmitter = new vscode.EventEmitter<number>();
                onDidWrite = this.writeEmitter.event;
                onDidClose = this.closeEmitter.event;

                async open(): Promise<void> {
                    this.writeEmitter.fire("Opening simulator picker...\r\n");
                    try {
                        await selectSimulator();
                        this.writeEmitter.fire("Done.\r\n");
                        this.closeEmitter.fire(0);
                    } catch (error) {
                        this.writeEmitter.fire(`Error: ${error}\r\n`);
                        this.closeEmitter.fire(1);
                    }
                }

                close(): void {}
            })();
        })
    );
    task.problemMatchers = [];
    return task;
}

export async function stopExistingLaunchTasksIfNeeded(targetLabel: string): Promise<boolean> {
    const taskNamesToCheck = [
        getLaunchTaskLabel(targetLabel, false),
        getLaunchTaskLabel(targetLabel, true),
        getTestLaunchTaskLabel(targetLabel, false),
        getTestLaunchTaskLabel(targetLabel, true),
    ];

    const runningTasks = vscode.tasks.taskExecutions.filter(
        execution => taskNamesToCheck.includes(execution.task.name)
    );

    if (runningTasks.length === 0) {
        return true;
    }

    const result = await vscode.window.showWarningMessage(
        `${targetLabel} is already running. Stop the current session?`,
        { modal: true },
        "Stop and Restart",
    );

    if (result === "Stop and Restart") {
        for (const task of runningTasks) {
            task.terminate();
        }
        if (vscode.debug.activeDebugConsole) {
            await vscode.debug.stopDebugging();
        }
        return true;
    }
    return false;
}

export class BuildTaskProvider implements vscode.TaskProvider {
    static readonly taskType = BUILD_TASK_TYPE;

    private config: Configuration;
    private extensionPath: string;
    private targets: ProcessedTarget[] = [];
    private bazelWrapper: string = "bazel";
    private tasksByLabel = new Map<string, vscode.Task>();
    private launchTasksByLabel = new Map<string, vscode.Task>();
    private launchWithoutDebuggingTasksByLabel = new Map<string, vscode.Task>();
    private testTasksByLabel = new Map<string, vscode.Task>();
    private testWithoutDebuggingTasksByLabel = new Map<string, vscode.Task>();

    constructor(config: Configuration, extensionPath: string) {
        this.config = config;
        this.extensionPath = extensionPath;
        config.onDidChange(() => this.rebuildTasks());
        this.rebuildTasks();
    }

    setTargets(targets: ProcessedTarget[], bazelWrapper: string): void {
        this.targets = targets;
        this.bazelWrapper = bazelWrapper;
        this.rebuildTasks();
    }

    private rebuildTasks(): void {
        this.tasksByLabel.clear();
        this.launchTasksByLabel.clear();
        this.launchWithoutDebuggingTasksByLabel.clear();
        this.testTasksByLabel.clear();
        this.testWithoutDebuggingTasksByLabel.clear();
        for (const target of this.targets) {
            this.tasksByLabel.set(target.label, createBuildTask(this.extensionPath, this.config, target, this.bazelWrapper));
            if (target.type === "app") {
                if (target.canDebug) {
                    this.launchTasksByLabel.set(getLaunchTaskLabel(target.label), createLaunchTask(this.extensionPath, this.config, target, this.bazelWrapper));
                }
                if (target.canRun) {
                    this.launchWithoutDebuggingTasksByLabel.set(getLaunchTaskLabel(target.label, true), createLaunchTask(this.extensionPath, this.config, target, this.bazelWrapper, true));
                }
            }
            if (target.type === "test") {
                if (target.canDebug) {
                    this.testTasksByLabel.set(getTestLaunchTaskLabel(target.label), createTestTask(this.extensionPath, this.config, target, this.bazelWrapper));
                }
                if (target.canRun) {
                    this.testWithoutDebuggingTasksByLabel.set(getTestLaunchTaskLabel(target.label, true), createTestTask(this.extensionPath, this.config, target, this.bazelWrapper, true));
                }
            }
        }
        const simulatorTaskName = "Select Simulator for Apple Development";
        this.testTasksByLabel.set(simulatorTaskName, createSimulatorTask(simulatorTaskName));
    }

    getTask(label: string): vscode.Task | undefined {
        return this.tasksByLabel.get(label) || this.launchTasksByLabel.get(label) || this.launchWithoutDebuggingTasksByLabel.get(label) || this.testTasksByLabel.get(label) || this.testWithoutDebuggingTasksByLabel.get(label);
    }

    provideTasks(): vscode.Task[] {
        const tasks = [
            ...this.tasksByLabel.values(),
            ...this.launchTasksByLabel.values(),
            ...this.launchWithoutDebuggingTasksByLabel.values(),
            ...this.testTasksByLabel.values(),
            ...this.testWithoutDebuggingTasksByLabel.values(),
        ];
        return tasks.sort((a, b) => a.name.localeCompare(b.name));
    }

    resolveTask(task: vscode.Task): vscode.Task | undefined {
        const targetLabel = task.definition.target;
        if (!targetLabel) {
            return undefined;
        }
        return this.tasksByLabel.get(targetLabel) || this.launchTasksByLabel.get(targetLabel) || this.launchWithoutDebuggingTasksByLabel.get(targetLabel) || this.testTasksByLabel.get(targetLabel) || this.testWithoutDebuggingTasksByLabel.get(targetLabel);
    }
}

export async function buildTarget(target: ProcessedTarget, provider: BuildTaskProvider): Promise<void> {
    const task = provider.getTask(target.label);
    if (task) {
        await vscode.tasks.executeTask(task);
    } else {
        vscode.window.showErrorMessage(`Build task not found for ${target.label}`);
    }
}

export async function launchTestTargetWithoutDebugging(target: ProcessedTarget, provider: BuildTaskProvider): Promise<void> {
    if (!await stopExistingLaunchTasksIfNeeded(target.label)) {
        return;
    }

    const task = provider.getTask(getTestLaunchTaskLabel(target.label, true));
    if (task) {
        await vscode.tasks.executeTask(task);
    } else {
        vscode.window.showErrorMessage(`Test without debugging task not found for ${target.label}`);
    }
}

export async function launchTargetWithoutDebugging(target: ProcessedTarget, provider: BuildTaskProvider): Promise<void> {
    if (!await stopExistingLaunchTasksIfNeeded(target.label)) {
        return;
    }

    const task = provider.getTask(getLaunchTaskLabel(target.label, true));
    if (task) {
        await vscode.tasks.executeTask(task);
    } else {
        vscode.window.showErrorMessage(`Run without debugging task not found for ${target.label}`);
    }
}
