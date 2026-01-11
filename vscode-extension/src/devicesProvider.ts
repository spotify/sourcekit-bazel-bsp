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
import { promisify } from "util";
import { Device } from "./types";

const execFileAsync = promisify(execFile);

interface SimctlDevice {
    udid: string;
    name: string;
    state: string;
    isAvailable: boolean;
}

interface SimctlOutput {
    devices: Record<string, SimctlDevice[]>;
}

export class DevicesWebviewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = "bspDevices";
    private static readonly SELECTED_DEVICE_KEY = "selectedDeviceUdid";

    private _view?: vscode.WebviewView;
    private _devices: Device[] = [];
    private _selectedDeviceUdid: string | undefined;
    private _context: vscode.ExtensionContext;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        context: vscode.ExtensionContext
    ) {
        this._context = context;
        this._selectedDeviceUdid = context.workspaceState.get<string>(
            DevicesWebviewProvider.SELECTED_DEVICE_KEY
        );
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        _context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        this._view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this._extensionUri],
        };

        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case "ready":
                    await this._loadDevices();
                    break;
                case "selectDevice":
                    this._selectDevice(data.udid);
                    break;
                case "refresh":
                    await this._loadDevices();
                    break;
            }
        });
    }

    private async _loadDevices(): Promise<void> {
        this._devices = await this.fetchAvailableDevices();

        // Auto-select the first device if none is selected
        if (!this.getSelectedDevice() && this._devices.length > 0) {
            this._selectedDeviceUdid = this._devices[0].udid;
            this._context.workspaceState.update(
                DevicesWebviewProvider.SELECTED_DEVICE_KEY,
                this._selectedDeviceUdid
            );
        }

        this._updateDevicesList();
    }

    public async reloadDevices(): Promise<void> {
        await this._loadDevices();
    }

    public getSelectedDevice(): Device | undefined {
        return this._devices.find((d) => d.udid === this._selectedDeviceUdid);
    }

    public getAllDevices(): Device[] {
        return this._devices;
    }

    public setSelectedDeviceByUdid(udid: string): void {
        this._selectDevice(udid);
    }

    private _selectDevice(udid: string): void {
        this._selectedDeviceUdid = udid;
        this._context.workspaceState.update(
            DevicesWebviewProvider.SELECTED_DEVICE_KEY,
            udid
        );
        this._updateDevicesList();
    }

    private _updateDevicesList(): void {
        if (!this._view) {
            return;
        }

        const selectedDevice = this.getSelectedDevice();

        this._view.webview.postMessage({
            type: "updateDevices",
            devices: this._devices,
            selectedUdid: this._selectedDeviceUdid,
            selectedDevice: selectedDevice
                ? { name: selectedDevice.name, runtime: selectedDevice.runtime }
                : null,
        });
    }

    async fetchAvailableDevices(): Promise<Device[]> {
        const devices: Device[] = [];

        // Fetch simulators from simctl
        try {
            const { stdout } = await execFileAsync("xcrun", [
                "simctl",
                "list",
                "devices",
                "-j",
            ]);

            const output: SimctlOutput = JSON.parse(stdout);

            for (const [runtimeId, simDevices] of Object.entries(output.devices)) {
                // Extract runtime name from runtime ID
                // e.g., "com.apple.CoreSimulator.SimRuntime.iOS-17-2" -> "iOS 17.2"
                const runtimeMatch = runtimeId.match(
                    /SimRuntime\.(\w+)-(\d+)-(\d+)/
                );
                const runtime = runtimeMatch
                    ? `${runtimeMatch[1]} ${runtimeMatch[2]}.${runtimeMatch[3]}`
                    : runtimeId;

                for (const device of simDevices) {
                    if (device.isAvailable) {
                        devices.push({
                            udid: device.udid,
                            name: device.name,
                            runtime,
                            state: device.state,
                            isPhysical: false,
                        });
                    }
                }
            }
        } catch {
            // Ignore simctl errors
        }

        // Fetch physical devices from devicectl
        try {
            const { stdout } = await execFileAsync("xcrun", [
                "devicectl",
                "list",
                "devices",
                "-j",
            ]);

            const output = JSON.parse(stdout);
            const physicalDevices = output?.result?.devices ?? [];

            for (const device of physicalDevices) {
                devices.push({
                    udid: device.hardwareProperties?.udid ?? device.identifier,
                    name: device.deviceProperties?.name ?? "Unknown Device",
                    runtime: device.deviceProperties?.osVersionNumber ?? "Unknown",
                    state: device.connectionProperties?.transportType ?? "disconnected",
                    isPhysical: true,
                });
            }
        } catch {
            // devicectl may not be available on older Xcode versions
        }

        return devices;
    }

    private _getHtmlForWebview(_webview: vscode.Webview): string {
        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: var(--vscode-font-family);
            font-size: var(--vscode-font-size);
            color: var(--vscode-foreground);
            background: transparent;
        }
        .header-section {
            padding: 12px;
            border-bottom: 1px solid var(--vscode-widget-border);
            background: var(--vscode-sideBar-background);
        }
        .header-row {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .header-label {
            font-size: 11px;
            text-transform: uppercase;
            color: var(--vscode-descriptionForeground);
            letter-spacing: 0.5px;
        }
        .selected-device-name {
            font-size: 13px;
            font-weight: 500;
            margin-top: 4px;
        }
        .selected-device-name.none {
            color: var(--vscode-descriptionForeground);
            font-style: italic;
        }
        .selected-device-runtime {
            font-size: 12px;
            color: var(--vscode-descriptionForeground);
            margin-top: 2px;
        }
        .header-icon {
            width: 16px;
            height: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .header-icon.check {
            color: var(--vscode-charts-green, #4ec9b0);
        }
        .header-icon.none {
            color: var(--vscode-descriptionForeground);
        }
        .section-title {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 8px 12px;
            font-size: 11px;
            text-transform: uppercase;
            color: var(--vscode-descriptionForeground);
            letter-spacing: 0.5px;
            border-bottom: 1px solid var(--vscode-widget-border);
        }
        .refresh-button {
            background: none;
            border: none;
            color: var(--vscode-foreground);
            cursor: pointer;
            padding: 2px;
            border-radius: 3px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .refresh-button:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .devices-list {
            padding: 4px 0;
        }
        .device-item {
            display: flex;
            align-items: center;
            padding: 6px 12px;
            cursor: pointer;
            gap: 8px;
        }
        .device-item:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .device-item.selected {
            background: var(--vscode-list-activeSelectionBackground);
            color: var(--vscode-list-activeSelectionForeground);
        }
        .device-icon {
            width: 16px;
            height: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
        }
        .device-icon.selected {
            color: var(--vscode-charts-green, #4ec9b0);
        }
        .device-info {
            flex: 1;
            overflow: hidden;
        }
        .device-name {
            font-size: 13px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .device-runtime {
            font-size: 11px;
            color: var(--vscode-descriptionForeground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .device-item.selected .device-runtime {
            color: var(--vscode-list-activeSelectionForeground);
            opacity: 0.8;
        }
        .check-mark {
            width: 16px;
            height: 16px;
            color: var(--vscode-charts-green, #4ec9b0);
            flex-shrink: 0;
        }
        .empty-state {
            padding: 16px;
            text-align: center;
            color: var(--vscode-descriptionForeground);
        }
    </style>
</head>
<body>
    <div class="header-section">
        <div class="header-label">Selected Device</div>
        <div id="selectedDeviceInfo">
            <div class="selected-device-name none">None selected</div>
        </div>
    </div>
    <div class="section-title">
        <span>Available Devices</span>
        <button class="refresh-button" id="refreshButton" title="Refresh devices">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path fill-rule="evenodd" clip-rule="evenodd" d="M4.681 3H2V2h3.5l.5.5V6H5V4a5 5 0 1 0 4.53-.761l.302-.954A6 6 0 1 1 4.681 3z"/></svg>
        </button>
    </div>
    <div class="devices-list" id="devicesList">
        <div class="empty-state">Loading devices...</div>
    </div>

    <script>
        const vscode = acquireVsCodeApi();
        const devicesList = document.getElementById('devicesList');
        const selectedDeviceInfo = document.getElementById('selectedDeviceInfo');
        const refreshButton = document.getElementById('refreshButton');

        refreshButton.addEventListener('click', () => {
            devicesList.innerHTML = '<div class="empty-state">Loading devices...</div>';
            vscode.postMessage({ type: 'refresh' });
        });

        window.addEventListener('message', (event) => {
            const message = event.data;
            if (message.type === 'updateDevices') {
                renderDevices(message.devices, message.selectedUdid);
                renderSelectedDevice(message.selectedDevice);
            }
        });

        function renderSelectedDevice(device) {
            if (device) {
                selectedDeviceInfo.innerHTML = \`
                    <div class="selected-device-name">\${device.name}</div>
                    <div class="selected-device-runtime">\${device.runtime}</div>
                \`;
            } else {
                selectedDeviceInfo.innerHTML = \`
                    <div class="selected-device-name none">None selected</div>
                \`;
            }
        }

        function getDeviceIcon(isPhysical) {
            if (isPhysical) {
                return '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2H4zm0 1h8a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm4 11a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"/></svg>';
            }
            return '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M1 4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V4zm1 0v7h12V4H2zm2 9h8v1H4v-1z"/></svg>';
        }

        function renderDevices(devices, selectedUdid) {
            if (devices.length === 0) {
                devicesList.innerHTML = '<div class="empty-state">No devices found</div>';
                return;
            }

            devicesList.innerHTML = devices.map(device => {
                const isSelected = device.udid === selectedUdid;
                return \`
                    <div class="device-item\${isSelected ? ' selected' : ''}" data-udid="\${device.udid}" onclick="selectDevice('\${device.udid}')">
                        <span class="device-icon\${isSelected ? ' selected' : ''}">\${getDeviceIcon(device.isPhysical)}</span>
                        <div class="device-info">
                            <div class="device-name">\${device.name}</div>
                            <div class="device-runtime">\${device.runtime}</div>
                        </div>
                        \${isSelected ? '<svg class="check-mark" width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.75.75 0 0 1 1.06-1.06L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0z"/></svg>' : ''}
                    </div>
                \`;
            }).join('');
        }

        function selectDevice(udid) {
            vscode.postMessage({ type: 'selectDevice', udid });
        }

        // Signal that webview is ready to receive data
        vscode.postMessage({ type: 'ready' });
    </script>
</body>
</html>`;
    }
}
