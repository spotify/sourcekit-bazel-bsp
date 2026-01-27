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
import * as fs from "fs";
import * as cp from "child_process";

interface SimulatorDevice {
    name: string;
    udid: string;
    state: string;
    isAvailable: boolean;
}

interface SimctlOutput {
    devices: Record<string, SimulatorDevice[]>;
}

interface SimulatorQuickPickItem extends vscode.QuickPickItem {
    udid: string;
}

export interface SimulatorInfo {
    name: string;
    runtime: string;
    udid: string;
}

async function getSimctlDevices(): Promise<SimctlOutput> {
    const output = await new Promise<string>((resolve, reject) => {
        cp.exec("xcrun simctl list devices available -j", (error, stdout) => {
            if (error) {
                reject(error);
            } else {
                resolve(stdout);
            }
        });
    });
    return JSON.parse(output);
}

function getSimulatorInfoPath(): string | undefined {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        return undefined;
    }
    return path.join(workspaceFolder.uri.fsPath, ".bsp", "skbsp_generated", "simulator_info.txt");
}

export async function getCurrentSimulatorInfo(): Promise<SimulatorInfo | undefined> {
    const infoPath = getSimulatorInfoPath();
    if (!infoPath) {
        return undefined;
    }

    try {
        const savedUdid = (await fs.promises.readFile(infoPath, "utf-8")).trim();
        if (!savedUdid) {
            return undefined;
        }

        const simctlData = await getSimctlDevices();

        for (const [runtime, devices] of Object.entries(simctlData.devices)) {
            const runtimeMatch = runtime.match(/SimRuntime\.(\w+)-(\d+)-(\d+)/);
            const runtimeLabel = runtimeMatch
                ? `${runtimeMatch[1]} ${runtimeMatch[2]}.${runtimeMatch[3]}`
                : runtime;

            for (const device of devices) {
                if (device.udid === savedUdid) {
                    return {
                        name: device.name,
                        runtime: runtimeLabel,
                        udid: device.udid,
                    };
                }
            }
        }

        return undefined;
    } catch {
        return undefined;
    }
}

export async function selectSimulator(): Promise<SimulatorInfo | undefined> {
    const infoPath = getSimulatorInfoPath();
    if (!infoPath) {
        vscode.window.showErrorMessage("No workspace folder found");
        return undefined;
    }

    try {
        const simctlData = await getSimctlDevices();
        const items: SimulatorQuickPickItem[] = [];

        for (const [runtime, devices] of Object.entries(simctlData.devices)) {
            const runtimeMatch = runtime.match(/SimRuntime\.(\w+)-(\d+)-(\d+)/);
            const runtimeLabel = runtimeMatch
                ? `${runtimeMatch[1]} ${runtimeMatch[2]}.${runtimeMatch[3]}`
                : runtime;

            for (const device of devices) {
                items.push({
                    label: device.name,
                    description: runtimeLabel,
                    udid: device.udid,
                });
            }
        }

        if (items.length === 0) {
            vscode.window.showErrorMessage("No available simulators found");
            return undefined;
        }

        items.sort((a, b) => {
            const descCompare = (b.description ?? "").localeCompare(a.description ?? "");
            if (descCompare !== 0) { return descCompare; }
            return a.label.localeCompare(b.label);
        });

        const selected = await vscode.window.showQuickPick(items, {
            placeHolder: "Select the simulator you'd like to use",
            matchOnDescription: true,
        });

        if (!selected) {
            return undefined;
        }

        const outputDir = path.dirname(infoPath);
        await fs.promises.mkdir(outputDir, { recursive: true });
        await fs.promises.writeFile(infoPath, selected.udid);

        const result: SimulatorInfo = {
            name: selected.label,
            runtime: selected.description ?? "",
            udid: selected.udid,
        };

        vscode.window.showInformationMessage(
            `Selected simulator: ${result.name} (${result.runtime})`
        );

        return result;
    } catch (error) {
        vscode.window.showErrorMessage(`Failed to list simulators: ${error}`);
        return undefined;
    }
}
