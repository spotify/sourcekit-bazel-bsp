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
import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import { processGraph } from "./graphProcessor";
import { generateTasks } from "./taskGenerator";
import { Configuration } from "./configuration";
import { BuildTaskProvider, TASK_SOURCE, ACTION_BUILD, ACTION_LAUNCH, ACTION_LAUNCH_WITHOUT_DEBUGGING, buildTarget, launchTargetWithoutDebugging, launchTestTargetWithoutDebugging, stopAllRunningBuildTasks, parseTaskName } from "./buildTaskProvider";
import { selectSimulator } from "./simulatorPicker";
import { DebugConfigurationProvider, launchTarget } from "./debugTaskProvider";
import { TargetsViewProvider } from "./targetsView";
import { BspLogsViewer } from "./bspLogsViewer";
import { TestController } from "./testController";
import { LSPTestDiscovery } from "./lspTestDiscovery";

export const outputChannel = vscode.window.createOutputChannel("SourceKit-Bazel-BSP (Extension)");

const originalGraphPath = ".bsp/skbsp_generated/graph.json"
const LAST_BUILT_TARGET_KEY = "skbsp.lastBuiltTarget";
const LAST_RUN_TARGET_KEY = "skbsp.lastRunTarget";
const LAST_TESTED_TARGET_KEY = "skbsp.lastTestedTarget";

let lastGraphHash: string | undefined;
let origFileWatcher: vscode.FileSystemWatcher | undefined;
let bspBinaryWatcher: vscode.FileSystemWatcher | undefined;
let bspConfigWatcher: vscode.FileSystemWatcher | undefined;
// let processedFileWatcher: vscode.FileSystemWatcher | undefined;
let configuration: Configuration;
let targetsViewProvider: TargetsViewProvider;
let buildTaskProvider: BuildTaskProvider;
let debugConfigProvider: DebugConfigurationProvider;
let bspLogsViewer: BspLogsViewer | undefined;
let testController: TestController;
let activeRunningState: { targetLabel: string; action: string; isDebugSession: boolean; pending: boolean } | null = null;

async function onGraphFileChanged(alreadyExisted: boolean = false) {
    if (alreadyExisted) {
        outputChannel.appendLine("Generating processed file from a previously generated graph");
    } else {
        outputChannel.appendLine("Graph file change detected");
    }
    const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const inputUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        originalGraphPath
    );

    const rawBytes = await vscode.workspace.fs.readFile(inputUri);
    const hash = crypto.createHash("sha256").update(rawBytes).digest("hex");
    if (hash === lastGraphHash) {
        outputChannel.appendLine("Graph file content unchanged, skipping processing");
        return;
    }
    lastGraphHash = hash;
    const outputUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        configuration.processedGraphPath
    );
    const result = await processGraph(inputUri, configuration.appsToAlwaysInclude, alreadyExisted);
    const contents = Buffer.from(JSON.stringify(result, null, 2));
    await vscode.workspace.fs.writeFile(outputUri, contents);
    outputChannel?.appendLine("Processed graph file change detected");
    // const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const processedGraphUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        configuration.processedGraphPath
    );
    await generateTasks(processedGraphUri, targetsViewProvider, buildTaskProvider, debugConfigProvider, testController);
}

async function fileExists(uri: vscode.Uri): Promise<boolean> {
    try {
        await vscode.workspace.fs.stat(uri);
        return true;
    } catch {
        return false;
    }
}

async function writeAdditionalLLDBCommands(config: Configuration): Promise<void> {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        return;
    }
    const outputDir = path.join(workspaceFolder.uri.fsPath, ".bsp", "skbsp_generated");
    const outputPath = path.join(outputDir, "lldb_additional_commands.json");
    await fs.promises.mkdir(outputDir, { recursive: true });
    await fs.promises.writeFile(outputPath, JSON.stringify(config.additionalLLDBCommands, null, 2));
}

async function buildTargetAndTrack(target: any, provider: BuildTaskProvider, context: vscode.ExtensionContext) {
    await buildTarget(target, provider);
    await context.workspaceState.update(LAST_BUILT_TARGET_KEY, target.label);
}

async function launchTargetWithoutDebuggingAndTrack(target: any, provider: BuildTaskProvider, context: vscode.ExtensionContext) {
    await launchTargetWithoutDebugging(target, provider);
    await context.workspaceState.update(LAST_RUN_TARGET_KEY, target.label);
}

async function launchTestTargetWithoutDebuggingAndTrack(target: any, provider: BuildTaskProvider, context: vscode.ExtensionContext) {
    await launchTestTargetWithoutDebugging(target, provider);
    await context.workspaceState.update(LAST_TESTED_TARGET_KEY, target.label);
}

export async function activate(context: vscode.ExtensionContext) {
    if (vscode.workspace.workspaceFile) {
        vscode.window.showErrorMessage(
            "The Swift extension doesn't work correctly with workspaces. We recommend closing this window and opening the IDE directly against the repository to ensure things work correctly."
        );
    }

    outputChannel?.appendLine("Extension activated");

    bspLogsViewer = new BspLogsViewer();
    bspLogsViewer?.start();

    configuration = new Configuration();
    context.subscriptions.push(configuration);

    // Write additional LLDB commands to file for the Python scripts to read
    await writeAdditionalLLDBCommands(configuration);

    const extensionPath = context.extensionUri.fsPath;

    buildTaskProvider = new BuildTaskProvider(configuration, extensionPath);
    context.subscriptions.push(
        vscode.tasks.registerTaskProvider(BuildTaskProvider.taskType, buildTaskProvider)
    );

    // Initialize LSP test discovery (uses Swift extension's sourcekit-lsp)
    const lspTestDiscovery = new LSPTestDiscovery(outputChannel);
    context.subscriptions.push(lspTestDiscovery);

    testController = new TestController(context, buildTaskProvider, lspTestDiscovery, outputChannel, configuration, extensionPath);
    context.subscriptions.push(testController);

    debugConfigProvider = new DebugConfigurationProvider(extensionPath);

    targetsViewProvider = new TargetsViewProvider(context.extensionUri, context.workspaceState);
    targetsViewProvider.setSettingsPinnedTargets(configuration.pinnedTargets);
    targetsViewProvider.onStopBuild(async () => {
        await stopAllRunningBuildTasks();
        activeRunningState = null;
        targetsViewProvider.updateRunningState(null, null);
    });
    targetsViewProvider.onBuildTarget(async (target) => {
        await stopAllRunningBuildTasks();
        activeRunningState = { targetLabel: target.label, action: ACTION_BUILD, isDebugSession: false, pending: true };
        targetsViewProvider.updateRunningState(target.label, ACTION_BUILD, true);
        buildTargetAndTrack(target, buildTaskProvider, context);
    });
    targetsViewProvider.onLaunchTarget(async (target) => {
        await stopAllRunningBuildTasks();
        activeRunningState = { targetLabel: target.label, action: ACTION_LAUNCH, isDebugSession: true, pending: true };
        targetsViewProvider.updateRunningState(target.label, ACTION_LAUNCH, true);
        launchTarget(target, debugConfigProvider);
    });
    targetsViewProvider.onLaunchTargetWithoutDebugging(async (target) => {
        await stopAllRunningBuildTasks();
        activeRunningState = { targetLabel: target.label, action: ACTION_LAUNCH_WITHOUT_DEBUGGING, isDebugSession: false, pending: true };
        targetsViewProvider.updateRunningState(target.label, ACTION_LAUNCH_WITHOUT_DEBUGGING, true);
        launchTargetWithoutDebuggingAndTrack(target, buildTaskProvider, context);
    });
    // targetsViewProvider.onTestTarget((target) => launchTestTarget(target, debugConfigProvider));
    targetsViewProvider.onTestTargetWithoutDebugging(async (target) => {
        await stopAllRunningBuildTasks();
        activeRunningState = { targetLabel: target.label, action: ACTION_LAUNCH_WITHOUT_DEBUGGING, isDebugSession: false, pending: true };
        targetsViewProvider.updateRunningState(target.label, ACTION_LAUNCH_WITHOUT_DEBUGGING, true);
        launchTestTargetWithoutDebuggingAndTrack(target, buildTaskProvider, context);
    });
    targetsViewProvider.onSelectSimulator(async () => {
        const selected = await selectSimulator();
        if (selected) {
            targetsViewProvider.updateSimulatorInfo(selected);
        }
    });
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(TargetsViewProvider.viewType, targetsViewProvider, {
            webviewOptions: { retainContextWhenHidden: true }
        })
    );

    // Task lifecycle tracking for stop button state.
    // Webview-initiated actions set state eagerly with pending=true (shows a spinner).
    // onDidStartTask flips pending to false (shows the stop button) once a task is actually running.
    // onDidStartTask also sets state when no state exists (e.g. task started from command palette).
    // PreLaunchTasks (action "launch") are excluded from setting NEW state because they are started
    // by VS Code's debug infrastructure, not directly by user action. A stale debug session can
    // restart its preLaunchTask after we've cancelled it, which would incorrectly re-show the
    // stop button.
    context.subscriptions.push(
        vscode.tasks.onDidStartTask((event) => {
            if (event.execution.task.source !== TASK_SOURCE) {
                return;
            }
            // If we have a pending state, confirm it now that a task is actually running
            if (activeRunningState?.pending) {
                activeRunningState.pending = false;
                targetsViewProvider.updateRunningState(activeRunningState.targetLabel, activeRunningState.action, false);
                return;
            }
            if (activeRunningState) {
                return;
            }
            const parsed = parseTaskName(event.execution.task.name);
            if (parsed && parsed.action !== ACTION_LAUNCH) {
                activeRunningState = {
                    targetLabel: parsed.targetLabel,
                    action: parsed.action,
                    isDebugSession: false,
                    pending: false,
                };
                targetsViewProvider.updateRunningState(parsed.targetLabel, parsed.action, false);
            }
        }),
    );
    context.subscriptions.push(
        vscode.tasks.onDidEndTask((event) => {
            if (event.execution.task.source !== TASK_SOURCE || !activeRunningState) {
                return;
            }
            // Don't clear state if this is a preLaunchTask ending while the debug session is still active
            if (activeRunningState.isDebugSession) {
                return;
            }
            // Don't clear state if another of our tasks is still running (handles same-target restart race)
            const stillRunning = vscode.tasks.taskExecutions.some(
                e => e.task.source === TASK_SOURCE,
            );
            if (stillRunning) {
                return;
            }
            activeRunningState = null;
            targetsViewProvider.updateRunningState(null, null);
        }),
    );
    context.subscriptions.push(
        vscode.debug.onDidTerminateDebugSession(() => {
            if (activeRunningState?.isDebugSession) {
                activeRunningState = null;
                targetsViewProvider.updateRunningState(null, null);
            }
        }),
    );

    // Update pinned targets and LLDB commands when configuration changes
    context.subscriptions.push(
        configuration.onDidChange(async () => {
            targetsViewProvider.setSettingsPinnedTargets(configuration.pinnedTargets);
            await writeAdditionalLLDBCommands(configuration);
        })
    );

    const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const originalGraphPattern = new vscode.RelativePattern(
        workspaceFolder,
        originalGraphPath
    );
    // const processedGraphPattern = new vscode.RelativePattern(
    //     workspaceFolder,
    //     configuration.processedGraphPath
    // );
    origFileWatcher = vscode.workspace.createFileSystemWatcher(originalGraphPattern);
    // processedFileWatcher = vscode.workspace.createFileSystemWatcher(processedGraphPattern);
    outputChannel?.appendLine("Configuring file watchers...");
    origFileWatcher.onDidCreate((_e) => onGraphFileChanged(false));
    origFileWatcher.onDidChange((_e) => onGraphFileChanged(false));
    // processedFileWatcher.onDidCreate(onProcessedGraphFileChanged);
    // processedFileWatcher.onDidChange(onProcessedGraphFileChanged);
    outputChannel?.appendLine("File watchers configured successfully");

    const bspBinaryPattern = new vscode.RelativePattern(
        workspaceFolder,
        ".bsp/sourcekit-bazel-bsp"
    );
    bspBinaryWatcher = vscode.workspace.createFileSystemWatcher(bspBinaryPattern);
    const promptReloadForBspChange = async () => {
        const selection = await vscode.window.showInformationMessage(
            "The BSP configuration has changed. You should reload this window to apply the changes.",
            "Reload Window"
        );
        if (selection === "Reload Window") {
            await vscode.commands.executeCommand("workbench.action.reloadWindow");
        }
    };
    bspBinaryWatcher.onDidChange(promptReloadForBspChange);
    bspBinaryWatcher.onDidCreate(promptReloadForBspChange);
    bspBinaryWatcher.onDidDelete(promptReloadForBspChange);
    context.subscriptions.push(bspBinaryWatcher);

    const bspConfigPattern = new vscode.RelativePattern(
        workspaceFolder,
        ".bsp/skbsp.json"
    );
    bspConfigWatcher = vscode.workspace.createFileSystemWatcher(bspConfigPattern);
    bspConfigWatcher.onDidChange(promptReloadForBspChange);
    bspConfigWatcher.onDidCreate(promptReloadForBspChange);
    bspConfigWatcher.onDidDelete(promptReloadForBspChange);
    context.subscriptions.push(bspConfigWatcher);

    const originalGraphUri = vscode.Uri.joinPath(workspaceFolder.uri, originalGraphPath);
    if (await fileExists(originalGraphUri)) {
        await onGraphFileChanged(true);
    }

    // Discover tests when documents are opened
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument((doc) => {
            testController.discoverTestsInFile(doc.uri);
        }),
    );

    // Discover tests when documents are saved (more reliable than file watcher)
    context.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument((doc) => {
            testController.discoverTestsInFile(doc.uri);
        }),
    );

    // Discover tests in already open documents
    vscode.workspace.textDocuments.forEach((doc) => {
        testController.discoverTestsInFile(doc.uri);
    });

    // Build Last Target Command
    context.subscriptions.push(
        vscode.commands.registerCommand("sourcekit-bazel-bsp.buildLastTarget", async () => {
            const lastTargetLabel = context.workspaceState.get<string>(LAST_BUILT_TARGET_KEY);

            if (!lastTargetLabel) {
                vscode.window.showInformationMessage("No target has been built yet. Build a target first to use this command.");
                return;
            }

            const target = buildTaskProvider.targets.find(t => t.label === lastTargetLabel);

            if (!target) {
                vscode.window.showErrorMessage(`Last built target '${lastTargetLabel}' not found. The workspace may have changed.`);
                return;
            }

            await buildTarget(target, buildTaskProvider);
        })
    );

    // Run Last Target Command
    context.subscriptions.push(
        vscode.commands.registerCommand("sourcekit-bazel-bsp.runLastTarget", async () => {
            const lastTargetLabel = context.workspaceState.get<string>(LAST_RUN_TARGET_KEY);

            if (!lastTargetLabel) {
                vscode.window.showInformationMessage("No target has been run yet. Run a target first to use this command.");
                return;
            }

            const target = buildTaskProvider.targets.find(t => t.label === lastTargetLabel);

            if (!target) {
                vscode.window.showErrorMessage(`Last run target '${lastTargetLabel}' not found. The workspace may have changed.`);
                return;
            }

            await launchTargetWithoutDebugging(target, buildTaskProvider);
        })
    );

    // Test Last Target Command
    context.subscriptions.push(
        vscode.commands.registerCommand("sourcekit-bazel-bsp.testLastTarget", async () => {
            const lastTargetLabel = context.workspaceState.get<string>(LAST_TESTED_TARGET_KEY);

            if (!lastTargetLabel) {
                vscode.window.showInformationMessage("No target has been tested yet. Test a target first to use this command.");
                return;
            }

            const target = buildTaskProvider.targets.find(t => t.label === lastTargetLabel);

            if (!target) {
                vscode.window.showErrorMessage(`Last tested target '${lastTargetLabel}' not found. The workspace may have changed.`);
                return;
            }

            await launchTestTargetWithoutDebugging(target, buildTaskProvider);
        })
    );
}

export function deactivate() {
    outputChannel?.appendLine("Deactivating...");
    origFileWatcher?.dispose();
    bspBinaryWatcher?.dispose();
    bspConfigWatcher?.dispose();
    // processedFileWatcher?.dispose();
    outputChannel?.dispose();
    bspLogsViewer?.dispose();
}
