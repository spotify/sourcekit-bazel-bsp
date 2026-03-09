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

interface PhysicalDevice {
    name: string;
    udid: string;
    identifier: string;
    osVersion: string;
    platform: string;
    connectionState: string;
}

interface DevicectlOutput {
    result: {
        devices: Array<{
            identifier: string;
            hardwareProperties: {
                udid: string;
                platform: string;
                reality?: string;
            };
            deviceProperties: {
                name: string;
                osVersionNumber: string;
            };
            connectionProperties: {
                tunnelState?: string;
            };
        }>;
    };
}

interface SimulatorQuickPickItem extends vscode.QuickPickItem {
    udid: string;
    identifier?: string;
    deviceType: 'simulator' | 'physical';
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

async function getPhysicalDevices(): Promise<PhysicalDevice[]> {
    const tmpFile = path.join(require('os').tmpdir(), `devicectl-${Date.now()}.json`);

    try {
        await new Promise<void>((resolve, reject) => {
            cp.exec(`xcrun devicectl list devices --json-output "${tmpFile}"`, (error) => {
                if (error) {
                    reject(error);
                } else {
                    resolve();
                }
            });
        });

        const output = await fs.promises.readFile(tmpFile, 'utf-8');
        const data: DevicectlOutput = JSON.parse(output);

        await fs.promises.unlink(tmpFile).catch(() => {});

        const devices: PhysicalDevice[] = [];

        for (const device of data.result.devices) {
            if (device.hardwareProperties.reality === 'physical') {
                devices.push({
                    name: device.deviceProperties.name,
                    udid: device.hardwareProperties.udid,
                    identifier: device.identifier,
                    osVersion: device.deviceProperties.osVersionNumber,
                    platform: device.hardwareProperties.platform,
                    connectionState: device.connectionProperties.tunnelState || 'disconnected',
                });
            }
        }

        return devices;
    } catch (error) {
        await fs.promises.unlink(tmpFile).catch(() => {});
        return [];
    }
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
        const savedContent = (await fs.promises.readFile(infoPath, "utf-8")).trim();
        if (!savedContent) {
            return undefined;
        }
        // Format: UDID:deviceType (e.g., "12345678-...:physical")
        const savedUdid = savedContent.split(":")[0];

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

        const physicalDevices = await getPhysicalDevices();
        for (const device of physicalDevices) {
            if (device.udid === savedUdid) {
                return {
                    name: device.name,
                    runtime: `${device.platform} ${device.osVersion}`,
                    udid: device.udid,
                };
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
        const items: SimulatorQuickPickItem[] = [];

        const physicalDevices = await getPhysicalDevices();
        for (const device of physicalDevices) {
            const connectionIndicator = device.connectionState === 'connected' ? '●' : '○';
            items.push({
                label: `${connectionIndicator} ${device.name}`,
                description: `${device.platform} ${device.osVersion}`,
                detail: 'Physical Device',
                udid: device.udid,
                identifier: device.identifier,
                deviceType: 'physical',
            });
        }

        if (items.length > 0) {
            items.push({
                label: '',
                kind: vscode.QuickPickItemKind.Separator,
                udid: '',
                deviceType: 'simulator',
            } as SimulatorQuickPickItem);
        }

        const simctlData = await getSimctlDevices();
        for (const [runtime, devices] of Object.entries(simctlData.devices)) {
            const runtimeMatch = runtime.match(/SimRuntime\.(\w+)-(\d+)-(\d+)/);
            const runtimeLabel = runtimeMatch
                ? `${runtimeMatch[1]} ${runtimeMatch[2]}.${runtimeMatch[3]}`
                : runtime;

            for (const device of devices) {
                items.push({
                    label: device.name,
                    description: runtimeLabel,
                    detail: 'Simulator',
                    udid: device.udid,
                    deviceType: 'simulator',
                });
            }
        }

        if (items.length === 0) {
            vscode.window.showErrorMessage("No available devices or simulators found");
            return undefined;
        }

        items.sort((a, b) => {
            if (a.deviceType !== b.deviceType) {
                return a.deviceType === 'physical' ? -1 : 1;
            }
            const descCompare = (b.description ?? "").localeCompare(a.description ?? "");
            if (descCompare !== 0) { return descCompare; }
            return a.label.localeCompare(b.label);
        });

        const selected = await vscode.window.showQuickPick(items, {
            placeHolder: "Select the device you'd like to use",
            matchOnDescription: true,
        });

        if (!selected || !selected.udid) {
            return undefined;
        }

        const outputDir = path.dirname(infoPath);
        await fs.promises.mkdir(outputDir, { recursive: true });

        await fs.promises.writeFile(infoPath, `${selected.udid}:${selected.deviceType}`);

        const result: SimulatorInfo = {
            name: selected.label.replace(/^[●○] /, ''),
            runtime: selected.description ?? "",
            udid: selected.udid,
        };

        const deviceTypeLabel = selected.deviceType === 'physical' ? 'device' : 'simulator';
        vscode.window.showInformationMessage(
            `Selected ${deviceTypeLabel}: ${result.name} (${result.runtime})`
        );

        return result;
    } catch (error) {
        vscode.window.showErrorMessage(`Failed to list devices: ${error}`);
        return undefined;
    }
}
