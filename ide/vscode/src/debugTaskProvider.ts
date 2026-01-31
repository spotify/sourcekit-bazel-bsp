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
import { getLaunchTaskLabel, stopExistingLaunchTasksIfNeeded } from "./buildTaskProvider";

function getScriptPath(extensionPath: string, scriptName: string): string {
    return path.join(extensionPath, "scripts", scriptName);
}

function createDebugConfig(extensionPath: string, targetLabel: string): vscode.DebugConfiguration {
    const attachScriptPath = getScriptPath(extensionPath, "lldb_attach.py");
    const killScriptPath = getScriptPath(extensionPath, "lldb_kill_app.py");
    return {
        name: `Debug ${targetLabel}`,
        type: "lldb-dap",
        request: "attach",
        preLaunchTask: `sourcekit-bazel-bsp: ${getLaunchTaskLabel(targetLabel)}`,
        debuggerRoot: "${workspaceFolder}",
        attachCommands: [
            `command script import "${attachScriptPath}"`
        ],
        terminateCommands: [
            `command script import "${killScriptPath}"`
        ],
        internalConsoleOptions: "openOnSessionStart",
        timeout: 9999
    };
}

// function createTestDebugConfig(extensionPath: string, targetLabel: string): vscode.DebugConfiguration {
//     const attachScriptPath = getScriptPath(extensionPath, "lldb_attach.py");
//     const killScriptPath = getScriptPath(extensionPath, "lldb_kill_app.py");
//     return {
//         name: `Test ${targetLabel}`,
//         type: "lldb-dap",
//         request: "attach",
//         preLaunchTask: `sourcekit-bazel-bsp: ${getTestLaunchTaskLabel(targetLabel)}`,
//         debuggerRoot: "${workspaceFolder}",
//         attachCommands: [
//             `command script import "${attachScriptPath}"`
//         ],
//         terminateCommands: [
//             `command script import "${killScriptPath}"`
//         ],
//         internalConsoleOptions: "openOnSessionStart",
//         timeout: 9999
//     };
// }

export class DebugConfigurationProvider implements vscode.DebugConfigurationProvider {
    private configsByLabel = new Map<string, vscode.DebugConfiguration>();
    // private testConfigsByLabel = new Map<string, vscode.DebugConfiguration>();
    private extensionPath: string;

    constructor(extensionPath: string) {
        this.extensionPath = extensionPath;
    }

    setTargets(targets: ProcessedTarget[]): void {
        this.configsByLabel.clear();
        // this.testConfigsByLabel.clear();
        for (const target of targets) {
            if (target.canDebug) {
                this.configsByLabel.set(target.label, createDebugConfig(this.extensionPath, target.label));
            }
            // if (target.type === "test" && target.canRun) {
            //     this.testConfigsByLabel.set(target.label, createTestDebugConfig(this.extensionPath, target.label));
            // }
        }
    }

    getConfig(label: string): vscode.DebugConfiguration | undefined {
        return this.configsByLabel.get(label);
    }

    // getTestConfig(label: string): vscode.DebugConfiguration | undefined {
    //     return this.testConfigsByLabel.get(label);
    // }

    provideDebugConfigurations(): vscode.DebugConfiguration[] {
        const allConfigs = [
            ...this.configsByLabel.values(),
            // ...this.testConfigsByLabel.values()
        ];
        return allConfigs.sort((a, b) => a.name.localeCompare(b.name));
    }

    resolveDebugConfiguration(
        _folder: vscode.WorkspaceFolder | undefined,
        config: vscode.DebugConfiguration
    ): vscode.DebugConfiguration | undefined {
        return config;
    }
}

export async function launchTarget(target: ProcessedTarget, debugConfigProvider: DebugConfigurationProvider): Promise<void> {
    if (!await stopExistingLaunchTasksIfNeeded(target.label)) {
        return;
    }

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        vscode.window.showErrorMessage("No workspace folder found");
        return;
    }

    const debugConfig = debugConfigProvider.getConfig(target.label);
    if (!debugConfig) {
        vscode.window.showErrorMessage(`Debug configuration not found for ${target.label}`);
        return;
    }

    await vscode.debug.startDebugging(workspaceFolder, debugConfig);
}

// export async function launchTestTarget(target: ProcessedTarget, debugConfigProvider: DebugConfigurationProvider): Promise<void> {
//     if (!await stopExistingLaunchTasksIfNeeded(target.label)) {
//         return;
//     }

//     const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
//     if (!workspaceFolder) {
//         vscode.window.showErrorMessage("No workspace folder found");
//         return;
//     }

//     const debugConfig = debugConfigProvider.getTestConfig(target.label);
//     if (!debugConfig) {
//         vscode.window.showErrorMessage(`Test debug configuration not found for ${target.label}`);
//         return;
//     }

//     await vscode.debug.startDebugging(workspaceFolder, debugConfig);
// }
