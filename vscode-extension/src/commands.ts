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
import * as fs from "fs";
import * as path from "path";
import { log } from "./logger";
import { DevicesWebviewProvider } from "./devicesProvider";
import { Target, Device } from "./types";
import {
    isDeviceCompatible,
    getCompatibleDevices,
    showCompatibleDevicePicker,
} from "./deviceCompatibility";

export interface CommandDependencies {
    getTargets: () => Target[];
    devicesProvider: DevicesWebviewProvider;
    scriptsPath: vscode.Uri;
}

function writeSimulatorInfo(device: Device): void {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        return;
    }
    const skbspGeneratedPath = path.join(workspaceFolder.uri.fsPath, ".bsp", "skbsp_generated");
    const simulatorInfoPath = path.join(skbspGeneratedPath, "simulator_info.txt");

    try {
        fs.mkdirSync(skbspGeneratedPath, { recursive: true });
        fs.writeFileSync(simulatorInfoPath, device.udid);
        log(`Wrote simulator info to ${simulatorInfoPath}`);
    } catch (error) {
        log(`Failed to write simulator info: ${error}`);
    }
}

async function getCompatibleDevice(
    deps: CommandDependencies,
    targetUri: string
): Promise<Device | undefined> {
    const target = deps.getTargets().find((t) => t.uri === targetUri);
    if (!target) {
        vscode.window.showErrorMessage(`Target not found: ${targetUri}`);
        return undefined;
    }

    // Ensure devices are loaded
    const allDevices = deps.devicesProvider.getAllDevices();
    if (allDevices.length === 0) {
        await deps.devicesProvider.reloadDevices();
    }

    const devices = deps.devicesProvider.getAllDevices();
    const selectedDevice = deps.devicesProvider.getSelectedDevice();

    // Check if selected device is compatible
    if (selectedDevice && isDeviceCompatible(selectedDevice, target)) {
        return selectedDevice;
    }

    // Get compatible devices
    const compatibleDevices = getCompatibleDevices(devices, target);

    // If no device selected or selected device is incompatible, show picker
    if (!selectedDevice) {
        const device = await showCompatibleDevicePicker(compatibleDevices, target);
        if (device) {
            deps.devicesProvider.setSelectedDeviceByUdid(device.udid);
            log(`Selected device: ${device.name}`);
        }
        return device;
    }

    // Selected device is incompatible, show picker with explanation
    const platformInfo = target.platform ? ` (${target.platform})` : "";
    const minOsInfo = target.minimumOsVersion
        ? `, min OS ${target.minimumOsVersion}`
        : "";

    vscode.window.showWarningMessage(
        `The selected device "${selectedDevice.name}" is not compatible with ` +
            `target${platformInfo}${minOsInfo}. Please select a compatible device.`
    );

    const device = await showCompatibleDevicePicker(compatibleDevices, target);
    if (device) {
        deps.devicesProvider.setSelectedDeviceByUdid(device.udid);
        log(`Selected device: ${device.name}`);
    }
    return device;
}

export function registerCommands(
    context: vscode.ExtensionContext,
    deps: CommandDependencies
): void {
    // Register the refresh devices command
    context.subscriptions.push(
        vscode.commands.registerCommand(
            "sourcekit-bazel-bsp.refreshDevices",
            async () => {
                await deps.devicesProvider.reloadDevices();
                log("Devices refreshed");
            }
        )
    );

    // Register the build target by URI command
    context.subscriptions.push(
        vscode.commands.registerCommand(
            "sourcekit-bazel-bsp.buildTargetByUri",
            async (targetUri: string) => {
                if (!targetUri) {
                    return;
                }

                const device = await getCompatibleDevice(deps, targetUri);
                if (!device) {
                    return;
                }

                writeSimulatorInfo(device);

                const buildScript = vscode.Uri.joinPath(deps.scriptsPath, "lldb_build.sh").fsPath;
                const shellExec = new vscode.ShellExecution(buildScript, [], {
                    env: {
                        BAZEL_LABEL_TO_RUN: targetUri,
                        BAZEL_EXTRA_BUILD_FLAGS: "",
                    },
                });

                const task = new vscode.Task(
                    { type: "sourcekit-bazel-bsp", target: targetUri },
                    vscode.TaskScope.Workspace,
                    `Build ${targetUri}`,
                    "SourceKit Bazel BSP",
                    shellExec,
                    "$gcc"
                );
                task.group = vscode.TaskGroup.Build;

                await vscode.tasks.executeTask(task);
                log(`Building target: ${targetUri} on ${device.name}`);
            }
        )
    );

    // Register the launch target by URI command
    context.subscriptions.push(
        vscode.commands.registerCommand(
            "sourcekit-bazel-bsp.launchTargetByUri",
            async (targetUri: string) => {
                if (!targetUri) {
                    return;
                }

                const device = await getCompatibleDevice(deps, targetUri);
                if (!device) {
                    return;
                }

                writeSimulatorInfo(device);

                const launchScript = vscode.Uri.joinPath(deps.scriptsPath, "lldb_launch_and_debug.sh").fsPath;
                const attachScript = vscode.Uri.joinPath(deps.scriptsPath, "lldb_attach.py").fsPath;
                const killScript = vscode.Uri.joinPath(deps.scriptsPath, "lldb_kill_app.py").fsPath;

                // Create the launch task as a background task
                const shellExec = new vscode.ShellExecution(launchScript, [], {
                    env: {
                        BAZEL_LABEL_TO_RUN: targetUri,
                        BAZEL_EXTRA_BUILD_FLAGS: "",
                        BAZEL_LAUNCH_ARGS: "",
                    },
                });

                const launchTaskName = `_launch_${targetUri}`;
                const launchTask = new vscode.Task(
                    { type: "sourcekit-bazel-bsp", target: targetUri, isLaunchTask: true },
                    vscode.TaskScope.Workspace,
                    launchTaskName,
                    "SourceKit Bazel BSP",
                    shellExec
                );
                launchTask.isBackground = true;
                launchTask.problemMatchers = ["$sourcekit-bazel-bsp-launch"];

                log(`Launching target: ${targetUri} on ${device.name}`);

                // Start the debug session with the launch task as preLaunchTask
                const debugConfig: vscode.DebugConfiguration = {
                    name: `Debug ${targetUri}`,
                    type: "lldb-dap",
                    request: "attach",
                    preLaunchTask: {
                        type: "sourcekit-bazel-bsp",
                        target: targetUri,
                        isLaunchTask: true,
                    },
                    debuggerRoot: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
                    attachCommands: [
                        `command script import '${attachScript}'`,
                    ],
                    terminateCommands: [
                        `command script import '${killScript}'`,
                    ],
                    internalConsoleOptions: "openOnSessionStart",
                    timeout: 9999,
                };

                // Register a one-time task provider for the launch task
                const disposable = vscode.tasks.registerTaskProvider("sourcekit-bazel-bsp", {
                    provideTasks: () => [launchTask],
                    resolveTask: (task) => {
                        if (task.definition.isLaunchTask && task.definition.target === targetUri) {
                            return launchTask;
                        }
                        return undefined;
                    },
                });

                try {
                    await vscode.debug.startDebugging(
                        vscode.workspace.workspaceFolders?.[0],
                        debugConfig
                    );
                } finally {
                    // Clean up the temporary task provider after a delay
                    setTimeout(() => disposable.dispose(), 5000);
                }
            }
        )
    );

    // Register the test target by URI command
    context.subscriptions.push(
        vscode.commands.registerCommand(
            "sourcekit-bazel-bsp.testTargetByUri",
            async (targetUri: string) => {
                if (!targetUri) {
                    return;
                }

                const device = await getCompatibleDevice(deps, targetUri);
                if (!device) {
                    return;
                }

                writeSimulatorInfo(device);

                const testScript = vscode.Uri.joinPath(deps.scriptsPath, "lldb_test.sh").fsPath;
                const shellExec = new vscode.ShellExecution(testScript, [], {
                    env: {
                        BAZEL_LABEL_TO_RUN: targetUri,
                        BAZEL_EXTRA_BUILD_FLAGS: "",
                    },
                });

                const task = new vscode.Task(
                    { type: "sourcekit-bazel-bsp", target: targetUri },
                    vscode.TaskScope.Workspace,
                    `Test ${targetUri}`,
                    "SourceKit Bazel BSP",
                    shellExec
                );
                task.group = vscode.TaskGroup.Test;

                await vscode.tasks.executeTask(task);
                log(`Testing target: ${targetUri} on ${device.name}`);
            }
        )
    );
}
