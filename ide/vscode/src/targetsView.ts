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
import { ProcessedTarget } from "./graphProcessor";
import * as fs from "fs";
import { getCurrentSimulatorInfo, SimulatorInfo, getSimulatorInfoPath, clearTestSimulatorInfo } from "./simulatorPicker";

interface FilterState {
    types: { app: boolean; test: boolean; library: boolean };
    paths: { [key: string]: boolean };
    textFilter: string;
    pinnedTargets: string[];
}

export const FILTER_STATE_KEY = "skbsp.filterStatev2";
export const FILTER_STATE_KEY_OLD = "skbsp.filterState";

export class TargetsViewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = "skbspTargets";

    private _view?: vscode.WebviewView;
    private targets: ProcessedTarget[] | undefined;
    private _settingsPinnedTargets: string[] = [];
    private _onBuildTarget?: (target: ProcessedTarget) => void;
    private _onLaunchTarget?: (target: ProcessedTarget) => void;
    private _onLaunchTargetWithoutDebugging?: (target: ProcessedTarget) => void;
    private _onTestTarget?: (target: ProcessedTarget) => void;
    private _onTestTargetWithoutDebugging?: (target: ProcessedTarget) => void;
    private _onSelectSimulator?: () => void;
    private _onSelectTestSimulator?: () => void;
    private _onClearTestSimulator?: () => void;
    private _onStopBuild?: () => void;
    private _runningState: { targetLabel: string; action: string; pending: boolean } | null = null;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _workspaceState: vscode.Memento
    ) {}

    onBuildTarget(callback: (target: ProcessedTarget) => void): void {
        this._onBuildTarget = callback;
    }

    onLaunchTarget(callback: (target: ProcessedTarget) => void): void {
        this._onLaunchTarget = callback;
    }

    onLaunchTargetWithoutDebugging(callback: (target: ProcessedTarget) => void): void {
        this._onLaunchTargetWithoutDebugging = callback;
    }

    onTestTarget(callback: (target: ProcessedTarget) => void): void {
        this._onTestTarget = callback;
    }

    onTestTargetWithoutDebugging(callback: (target: ProcessedTarget) => void): void {
        this._onTestTargetWithoutDebugging = callback;
    }

    onSelectSimulator(callback: () => void): void {
        this._onSelectSimulator = callback;
    }

    onSelectTestSimulator(callback: () => void): void {
        this._onSelectTestSimulator = callback;
    }

    onClearTestSimulator(callback: () => void): void {
        this._onClearTestSimulator = callback;
    }

    onStopBuild(callback: () => void): void {
        this._onStopBuild = callback;
    }

    /** Updates the webview with the currently running task state. */
    updateRunningState(targetLabel: string | null, action: string | null, pending: boolean = false): void {
        this._runningState = targetLabel && action ? { targetLabel, action, pending } : null;
        this._sendRunningStateToWebview();
    }

    setTargets(targets: ProcessedTarget[]): void {
        this.targets = targets;
        this._sendTargetsToWebview();
    }

    clearState(): void {
        this._view?.webview.postMessage({ type: "clearState" });
    }

    setSettingsPinnedTargets(pinnedTargets: string[]): void {
        this._settingsPinnedTargets = pinnedTargets;
        this._sendSettingsPinnedTargetsToWebview();
    }

    resolveWebviewView(
        webviewView: vscode.WebviewView,
        _context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ): void {
        this._view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this._extensionUri],
        };

        // Keep webview content when switching tabs
        webviewView.onDidChangeVisibility(() => {
            if (webviewView.visible) {
                this._sendTargetsToWebview();
                this._sendFilterStateToWebview();
                this._sendSettingsPinnedTargetsToWebview();
                this._sendSimulatorInfoToWebview();
                this._sendRunningStateToWebview();
            }
        });

        webviewView.webview.onDidReceiveMessage((message) => {
            if (message.type === "ready") {
                this._sendTargetsToWebview();
                this._sendFilterStateToWebview();
                this._sendSettingsPinnedTargetsToWebview();
                this._sendSimulatorInfoToWebview();
                this._sendRunningStateToWebview();
            } else if (message.type === "saveFilterState") {
                this._workspaceState.update(FILTER_STATE_KEY, message.state);
            } else if (message.type === "buildTarget") {
                const target = this.targets?.find(t => t.displayName === message.label);
                if (target && this._onBuildTarget) {
                    this._onBuildTarget(target);
                }
            } else if (message.type === "launchTarget") {
                const target = this.targets?.find(t => t.displayName === message.label);
                if (target) {
                    if (target.type === "test" && this._onTestTarget) {
                        this._onTestTarget(target);
                    } else if (this._onLaunchTarget) {
                        this._onLaunchTarget(target);
                    }
                }
            } else if (message.type === "launchTargetWithoutDebugging") {
                const target = this.targets?.find(t => t.displayName === message.label);
                if (target) {
                    if (target.type === "test" && this._onTestTargetWithoutDebugging) {
                        this._onTestTargetWithoutDebugging(target);
                    } else if (this._onLaunchTargetWithoutDebugging) {
                        this._onLaunchTargetWithoutDebugging(target);
                    }
                }
            } else if (message.type === "testTarget") {
                const target = this.targets?.find(t => t.displayName === message.label);
                if (target && this._onTestTarget) {
                    this._onTestTarget(target);
                }
            } else if (message.type === "testTargetWithoutDebugging") {
                const target = this.targets?.find(t => t.displayName === message.label);
                if (target && this._onTestTargetWithoutDebugging) {
                    this._onTestTargetWithoutDebugging(target);
                }
            } else if (message.type === "stopBuild") {
                if (this._onStopBuild) {
                    this._onStopBuild();
                }
            } else if (message.type === "selectSimulator") {
                if (this._onSelectSimulator) {
                    this._onSelectSimulator();
                }
            } else if (message.type === "selectTestSimulator") {
                if (this._onSelectTestSimulator) {
                    this._onSelectTestSimulator();
                }
            } else if (message.type === "clearTestSimulator") {
                if (this._onClearTestSimulator) {
                    this._onClearTestSimulator();
                }
            } else if (message.type === "togglePin") {
                this._workspaceState.update(FILTER_STATE_KEY, message.state);
            }
        });

        webviewView.webview.html = this._getHtmlContent();
    }

    private _sendTargetsToWebview(): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "updateTargets",
            targets: this.targets ?? null,
        });
    }

    private _sendSettingsPinnedTargetsToWebview(): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "updateSettingsPinnedTargets",
            targets: this._settingsPinnedTargets,
        });
    }

    private _sendFilterStateToWebview(): void {
        if (!this._view) {
            return;
        }
        const savedState = this._workspaceState.get<FilterState>(FILTER_STATE_KEY);
        if (savedState) {
            this._view.webview.postMessage({
                type: "restoreFilterState",
                state: savedState,
            });
        }
    }

    private async _sendSimulatorInfoToWebview(): Promise<void> {
        if (!this._view) {
            return;
        }
        const [info, testInfo] = await Promise.all([
            getCurrentSimulatorInfo(),
            getCurrentSimulatorInfo('test'),
        ]);
        this._view.webview.postMessage({
            type: "updateSimulatorInfo",
            simulator: info ?? null,
        });

        // If the test device file exists but the device is no longer available,
        // auto-clear the stale override so the UI and execution stay in sync.
        const testDevicePath = getSimulatorInfoPath('test');
        if (!testInfo && testDevicePath && fs.existsSync(testDevicePath)) {
            await clearTestSimulatorInfo();
        }
        this._view.webview.postMessage({
            type: "updateTestSimulatorInfo",
            simulator: testInfo ?? null,
        });
    }

    private _sendRunningStateToWebview(): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "updateRunningState",
            targetLabel: this._runningState?.targetLabel ?? null,
            action: this._runningState?.action ?? null,
            pending: this._runningState?.pending ?? false,
        });
    }

    updateSimulatorInfo(info: SimulatorInfo | undefined): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "updateSimulatorInfo",
            simulator: info ?? null,
        });
    }

    updateTestSimulatorInfo(info: SimulatorInfo | undefined): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "updateTestSimulatorInfo",
            simulator: info ?? null,
        });
    }

    setSimulatorLoading(loading: boolean): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "setSimulatorLoading",
            loading,
        });
    }

    setTestSimulatorLoading(loading: boolean): void {
        if (!this._view) {
            return;
        }
        this._view.webview.postMessage({
            type: "setTestSimulatorLoading",
            loading,
        });
    }

    private _getHtmlContent(): string {
        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://unpkg.com/@vscode/codicons/dist/codicon.css" rel="stylesheet" />
    <style>
        body {
            padding: 0;
            margin: 0;
            font-family: var(--vscode-font-family);
            font-size: var(--vscode-font-size);
            color: var(--vscode-foreground);
        }
        .filter-container {
            padding: 8px;
            position: sticky;
            top: 0;
            z-index: 10;
            background: var(--vscode-sideBar-background);
            border-bottom: 1px solid var(--vscode-widget-border);
        }
        .filter-row {
            display: flex;
            gap: 4px;
            align-items: center;
        }
        .filter-input-wrapper {
            flex: 1;
            position: relative;
        }
        .filter-input {
            width: 100%;
            box-sizing: border-box;
            padding: 4px 24px 4px 8px;
            border: 1px solid var(--vscode-input-border);
            background: var(--vscode-input-background);
            color: var(--vscode-input-foreground);
            border-radius: 2px;
            outline: none;
        }
        .filter-clear {
            display: none;
            position: absolute;
            right: 3px;
            top: 50%;
            transform: translateY(-50%);
            width: 18px;
            height: 18px;
            align-items: center;
            justify-content: center;
            border: none;
            background: transparent;
            color: var(--vscode-input-foreground);
            cursor: pointer;
            border-radius: 2px;
            padding: 0;
        }
        .filter-clear:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .filter-clear.visible {
            display: flex;
        }
        .filter-input:focus {
            border-color: var(--vscode-focusBorder);
        }
        .filter-input::placeholder {
            color: var(--vscode-input-placeholderForeground);
        }
        .filter-button {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 26px;
            height: 26px;
            border: 1px solid var(--vscode-input-border);
            background: var(--vscode-input-background);
            color: var(--vscode-foreground);
            border-radius: 2px;
            cursor: pointer;
            position: relative;
        }
        .filter-button:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .filter-button.active {
            color: var(--vscode-focusBorder);
        }
        .filter-dropdown {
            display: none;
            position: absolute;
            top: 100%;
            right: 0;
            margin-top: 4px;
            background: var(--vscode-dropdown-background);
            border: 1px solid var(--vscode-dropdown-border);
            border-radius: 2px;
            padding: 4px 0;
            z-index: 100;
            min-width: 120px;
        }
        .filter-dropdown.show {
            display: block;
        }
        .filter-option {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 4px 12px;
            cursor: pointer;
            white-space: nowrap;
        }
        .filter-option:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .filter-option input {
            margin: 0;
        }
        .filter-separator {
            height: 1px;
            background: var(--vscode-widget-border);
            margin: 4px 0;
        }
        .filter-section-label {
            padding: 4px 12px;
            font-size: 0.85em;
            color: var(--vscode-descriptionForeground);
            font-weight: 500;
        }
        .target-list {
            padding: 4px 0;
        }
        .target-item {
            display: flex;
            align-items: center;
            padding: 4px 12px;
            cursor: pointer;
            gap: 8px;
            position: relative;
        }
        .target-item:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .target-name {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .target-actions {
            display: flex;
            position: absolute;
            right: 4px;
            top: 0;
            bottom: 0;
            align-items: center;
            padding-left: 8px;
        }
        .target-actions.has-visible {
            background: var(--vscode-sideBar-background);
        }
        .target-item:hover .target-actions {
            background: var(--vscode-list-hoverBackground);
        }
        .action-button {
            display: none;
            align-items: center;
            justify-content: center;
            width: 22px;
            height: 22px;
            border: none;
            background: transparent;
            color: var(--vscode-foreground);
            border-radius: 2px;
            cursor: pointer;
        }
        .target-item:hover .action-button {
            display: flex;
        }
        .action-button:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .action-button.stop-button {
            display: flex;
            color: var(--vscode-testing-iconErrored);
        }
        .action-button.pending-button {
            display: flex;
            color: var(--vscode-descriptionForeground);
            cursor: default;
        }
        .target-actions.is-active .action-button {
            display: flex;
        }
        .pin-button.pinned {
            display: flex;
        }
        .pin-leading {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 16px;
            height: 16px;
        }
        .pin-leading .action-button {
            width: 16px;
            height: 16px;
        }
        .waiting {
            padding: 12px;
            color: var(--vscode-descriptionForeground);
            font-style: italic;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .spinner {
            width: 14px;
            height: 14px;
            border: 2px solid var(--vscode-descriptionForeground);
            border-top-color: transparent;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .codicon {
            font-size: 16px;
            color: var(--vscode-icon-foreground);
        }
        .simulator-row {
            display: flex;
            align-items: center;
            padding: 4px 12px;
            gap: 8px;
            border-bottom: 1px solid var(--vscode-widget-border);
            position: relative;
        }
        .simulator-row:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .simulator-row .simulator-label {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .simulator-row .simulator-runtime {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            color: var(--vscode-descriptionForeground);
            font-size: 0.9em;
        }
        .simulator-actions {
            display: flex;
            position: absolute;
            right: 4px;
            top: 0;
            bottom: 0;
            align-items: center;
            padding-left: 8px;
        }
        .simulator-row:hover .simulator-actions {
            background: var(--vscode-list-hoverBackground);
        }
        .simulator-row .action-button {
            display: none;
        }
        .simulator-row:hover .action-button {
            display: flex;
        }
        .tree-group {
            display: flex;
            flex-direction: column;
        }
        .tree-header {
            display: flex;
            align-items: center;
            padding: 4px 12px;
            cursor: pointer;
            gap: 8px;
            user-select: none;
        }
        .tree-header:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .tree-header .chevron {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 16px;
            height: 16px;
            transition: transform 0.15s ease;
        }
        .tree-header .chevron.expanded {
            transform: rotate(90deg);
        }
        .tree-header .folder-name {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .tree-children {
            display: none;
        }
        .tree-children.expanded {
            display: block;
        }
        .pinned-section-header {
            padding: 6px 12px 2px 12px;
            font-size: 0.85em;
            color: var(--vscode-descriptionForeground);
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .pinned-section-header .filter-query {
            text-transform: none;
        }
        .pinned-section-separator {
            height: 1px;
            background: var(--vscode-widget-border);
            margin: 4px 0;
        }
    </style>
</head>
<body>
    <div class="filter-container">
        <div class="filter-row">
            <div class="filter-input-wrapper">
                <input
                    type="text"
                    class="filter-input"
                    placeholder="Filter targets..."
                    id="filterInput"
                />
                <button class="filter-clear" id="filterClear" title="Clear filter">
                    <span class="codicon codicon-close"></span>
                </button>
            </div>
            <button class="filter-button" id="filterButton" title="Filter by type">
                <span class="codicon codicon-filter"></span>
                <div class="filter-dropdown" id="filterDropdown">
                    <div class="filter-section-label">Type</div>
                    <label class="filter-option">
                        <input type="checkbox" id="filterApp" checked />
                        <span class="codicon codicon-rocket"></span>
                        App
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterTest" checked />
                        <span class="codicon codicon-beaker"></span>
                        Test
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterLibrary" checked />
                        <span class="codicon codicon-library"></span>
                        Library
                    </label>
                    <div class="filter-separator"></div>
                    <div class="filter-section-label">Paths to hide</div>
                    <label class="filter-option">
                        <input type="checkbox" id="filterExternal" checked />
                        @
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterApple" />
                        //apple/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterBase" />
                        //base/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterOther" checked />
                        //other/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterShared" checked />
                        //shared/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterSrc" checked />
                        //src/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterSystems" />
                        //Systems/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterThirdParty" checked />
                        //third_party/
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" id="filterTools" checked />
                        //tools/
                    </label>
                </div>
            </button>
        </div>
    </div>
    <div class="simulator-row">
        <span class="codicon codicon-device-mobile"></span>
        <span class="simulator-label" id="simulatorLabel">Select Physical or Simulator Device</span>
        <span class="simulator-runtime" id="simulatorRuntime"></span>
        <div class="simulator-actions">
            <button class="action-button" id="simulatorButton" title="Select Physical or Simulator Device for Apple Development">
                <span class="codicon codicon-settings-gear"></span>
            </button>
        </div>
    </div>
    <div class="simulator-row" id="testSimulatorRow">
        <span class="codicon codicon-beaker"></span>
        <span class="simulator-label" id="testSimulatorLabel">Test Device: Using app device</span>
        <span class="simulator-runtime" id="testSimulatorRuntime"></span>
        <div class="simulator-actions">
            <button class="action-button" id="clearTestSimulatorButton" title="Reset to app device" style="display: none;">
                <span class="codicon codicon-close"></span>
            </button>
            <button class="action-button" id="testSimulatorButton" title="Select device for running tests">
                <span class="codicon codicon-settings-gear"></span>
            </button>
        </div>
    </div>
    <div class="target-list" id="targetList">
        <div class="waiting"><div class="spinner"></div>Waiting for the graph to be processed...</div>
    </div>
    <script>
        const filterInput = document.getElementById('filterInput');
        const filterClear = document.getElementById('filterClear');
        const targetList = document.getElementById('targetList');
        const filterButton = document.getElementById('filterButton');
        const filterDropdown = document.getElementById('filterDropdown');
        const filterApp = document.getElementById('filterApp');
        const filterTest = document.getElementById('filterTest');
        const filterLibrary = document.getElementById('filterLibrary');
        const filterShared = document.getElementById('filterShared');
        const filterTools = document.getElementById('filterTools');
        const filterOther = document.getElementById('filterOther');
        const filterSrc = document.getElementById('filterSrc');
        const filterThirdParty = document.getElementById('filterThirdParty');
        const filterApple = document.getElementById('filterApple');
        const filterBase = document.getElementById('filterBase');
        const filterSystems = document.getElementById('filterSystems');
        const filterExternal = document.getElementById('filterExternal');

        const typeCheckboxes = [filterApp, filterTest, filterLibrary];
        const pathFilters = [
            { checkbox: filterShared, pattern: '//shared/' },
            { checkbox: filterTools, pattern: '//tools/' },
            { checkbox: filterOther, pattern: '//other' },
            { checkbox: filterSrc, pattern: '//src/' },
            { checkbox: filterThirdParty, pattern: '//third_party/' },
            { checkbox: filterApple, pattern: '//apple/' },
            { checkbox: filterBase, pattern: '//base/' },
            { checkbox: filterSystems, pattern: '//Systems/' },
            { checkbox: filterExternal, pattern: '@' },
        ];

        let allTargets = null;
        let pinnedTargets = [];
        let settingsPinnedTargets = [];
        let runningState = null;
        let expandedPaths = [];
        let collapsedRootPaths = [];

        function iconForTargetType(type) {
            switch (type) {
                case 'app': return 'rocket';
                case 'test': return 'beaker';
                case 'library': return 'library';
                default: return 'file';
            }
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function getSelectedTypes() {
            const types = [];
            if (filterApp.checked) types.push('app');
            if (filterTest.checked) types.push('test');
            if (filterLibrary.checked) types.push('library');
            return types;
        }

        function matchesPathFilters(label) {
            for (const { checkbox, pattern } of pathFilters) {
                if (label.startsWith(pattern)) {
                    // Checked = hide, Unchecked = show
                    return !checkbox.checked;
                }
            }
            return true;
        }

        function updateFilterButtonState() {
            const allTypesSelected = filterApp.checked && filterTest.checked && filterLibrary.checked;
            const defaultPathsSelected = filterShared.checked && filterTools.checked &&
                filterOther.checked && filterSrc.checked && filterThirdParty.checked &&
                !filterApple.checked && !filterBase.checked && !filterSystems.checked && filterExternal.checked;
            filterButton.classList.toggle('active', !(allTypesSelected && defaultPathsSelected));
        }

        function buildTree(targets) {
            const root = { children: {}, targets: [] };
            for (const target of targets) {
                const label = target.underlyingLabel;
                let pathSegments, targetName;
                if (label.startsWith('@')) {
                    const withoutAt = label.substring(1);
                    const slashIdx = withoutAt.indexOf('//');
                    const repo = '@' + (slashIdx >= 0 ? withoutAt.substring(0, slashIdx) : withoutAt);
                    const rest = slashIdx >= 0 ? withoutAt.substring(slashIdx + 2) : '';
                    const colonIdx = rest.lastIndexOf(':');
                    if (colonIdx >= 0) {
                        pathSegments = [repo, ...rest.substring(0, colonIdx).split('/').filter(Boolean)];
                        targetName = rest.substring(colonIdx + 1);
                    } else {
                        pathSegments = [repo, ...rest.split('/').filter(Boolean)];
                        targetName = pathSegments[pathSegments.length - 1];
                    }
                } else {
                    const withoutSlashes = label.startsWith('//') ? label.substring(2) : label;
                    const colonIdx = withoutSlashes.lastIndexOf(':');
                    if (colonIdx >= 0) {
                        pathSegments = withoutSlashes.substring(0, colonIdx).split('/').filter(Boolean);
                        targetName = withoutSlashes.substring(colonIdx + 1);
                    } else {
                        pathSegments = withoutSlashes.split('/').filter(Boolean);
                        targetName = pathSegments[pathSegments.length - 1];
                    }
                }
                let node = root;
                for (const segment of pathSegments) {
                    if (!node.children[segment]) {
                        node.children[segment] = { children: {}, targets: [] };
                    }
                    node = node.children[segment];
                }
                node.targets.push({ ...target, shortName: targetName });
            }
            return root;
        }

        function compactTree(node) {
            for (const key of Object.keys(node.children)) {
                compactTree(node.children[key]);
            }
            const newChildren = {};
            for (const key of Object.keys(node.children)) {
                let compactedKey = key;
                let current = node.children[key];
                while (Object.keys(current.children).length === 1 && current.targets.length === 0) {
                    const [childKey] = Object.keys(current.children);
                    compactedKey = compactedKey + '/' + childKey;
                    current = current.children[childKey];
                }
                newChildren[compactedKey] = current;
            }
            node.children = newChildren;
        }

        function isExpanded(pathKey) {
            const filterText = filterInput.value.trim().toLowerCase();
            if (filterText) return true;
            // Pinned tree nodes are expanded by default
            if (pathKey.startsWith('pinned/')) return !collapsedRootPaths.includes(pathKey);
            // Unpinned nodes are collapsed by default
            return expandedPaths.includes(pathKey);
        }

        function toggleExpanded(pathKey) {
            // Pinned nodes default to expanded, so toggling uses collapsedRootPaths.
            if (pathKey.startsWith('pinned/')) {
                const index = collapsedRootPaths.indexOf(pathKey);
                if (index >= 0) {
                    collapsedRootPaths.splice(index, 1);
                } else {
                    collapsedRootPaths.push(pathKey);
                }
            } else {
                const index = expandedPaths.indexOf(pathKey);
                if (index >= 0) {
                    expandedPaths.splice(index, 1);
                } else {
                    expandedPaths.push(pathKey);
                }
            }
            renderTargets();
            saveFilterState();
        }

        function renderTargetItem(target, depth, isPinnedSection) {
            const displayName = target.displayName;
            const shortDisplayName = target.shortName + displayName.substring(target.underlyingLabel.length);
            const isSettingsPinned = settingsPinnedTargets.includes(target.displayName);
            const isUIPinned = pinnedTargets.includes(target.displayName);
            const isPinned = isSettingsPinned || isUIPinned;
            const pinIcon = isPinned ? 'pinned' : 'pin';
            const pinClass = (isPinned && !isPinnedSection) ? 'pin-button pinned' : 'pin-button';
            const pinTitle = isSettingsPinned ? 'Pinned via settings' : (isUIPinned ? 'Unpin target' : 'Pin target');
            const pinButton = '<button class="action-button ' + pinClass + '" data-action="pin" data-label="' + escapeHtml(target.displayName) + '"' + (isSettingsPinned ? ' data-settings-pinned="true"' : '') + ' title="' + pinTitle + '"><span class="codicon codicon-' + pinIcon + '"></span></button>';
            const isRunningCheck = (label, action) => runningState && runningState.targetLabel === displayName && runningState.action === action;
            const pendingBtn = '<button class="action-button pending-button" title="Starting..."><span class="codicon codicon-loading codicon-modifier-spin"></span></button>';
            const stopBtn = '<button class="action-button stop-button" data-action="stop" title="Stop"><span class="codicon codicon-debug-stop"></span></button>';
            const runningBtn = () => runningState && runningState.pending ? pendingBtn : stopBtn;
            const buildButton = isRunningCheck(target.displayName, 'build')
                ? runningBtn()
                : '<button class="action-button" data-action="build" data-label="' + escapeHtml(target.displayName) + '" title="Build target"><span class="codicon codicon-tools"></span></button>';
            const launchButton = target.canDebug
                ? (isRunningCheck(target.displayName, 'launch')
                    ? runningBtn()
                    : '<button class="action-button" data-action="launch" data-label="' + escapeHtml(target.displayName) + '" title="Run and debug"><span class="codicon codicon-debug-alt"></span></button>')
                : '';
            const launchWithoutDebuggingButton = target.canRun
                ? (isRunningCheck(target.displayName, 'launchWithoutDebugging')
                    ? runningBtn()
                    : '<button class="action-button" data-action="launchWithoutDebugging" data-label="' + escapeHtml(target.displayName) + '" title="Run without debugging"><span class="codicon codicon-run"></span></button>')
                : '';
            const isRunning = runningState && runningState.targetLabel === target.displayName;
            const hasVisible = (isPinned && !isPinnedSection) || isRunning;
            const actionsClass = 'target-actions' + (hasVisible ? ' has-visible' : '') + (isRunning ? ' is-active' : '');
            const indent = depth * 16;
            return '<div class="target-item" style="padding-left: ' + (12 + indent) + 'px">' +
                '<span class="pin-leading">' + pinButton + '</span>' +
                '<span class="codicon codicon-' + iconForTargetType(target.type) + '"></span>' +
                '<span class="target-name" title="' + escapeHtml(displayName) + '">' + escapeHtml(shortDisplayName) + '</span>' +
                '<span class="' + actionsClass + '">' +
                buildButton +
                launchWithoutDebuggingButton +
                launchButton +
                '</span>' +
                '</div>';
        }

        function renderTree(node, depth, pathPrefix, isPinnedSection) {
            let html = '';
            const childKeys = Object.keys(node.children).sort((a, b) => a.localeCompare(b));
            for (const key of childKeys) {
                const child = node.children[key];
                const pathKey = pathPrefix ? pathPrefix + '/' + key : key;
                const expanded = isExpanded(pathKey);
                const chevronClass = 'chevron' + (expanded ? ' expanded' : '');
                const childrenClass = 'tree-children' + (expanded ? ' expanded' : '');
                const indent = depth * 16;
                html += '<div class="tree-group">';
                html += '<div class="tree-header" data-path-key="' + escapeHtml(pathKey) + '" style="padding-left: ' + (12 + indent) + 'px">';
                html += '<span class="' + chevronClass + '"><span class="codicon codicon-chevron-right"></span></span>';
                html += '<span class="codicon codicon-folder"></span>';
                html += '<span class="folder-name">' + escapeHtml(key) + '</span>';
                html += '</div>';
                if (expanded) {
                    html += '<div class="' + childrenClass + '">';
                    html += renderTree(child, depth + 1, pathKey, isPinnedSection);
                    html += '</div>';
                }
                html += '</div>';
            }
            for (const target of node.targets) {
                html += renderTargetItem(target, depth, isPinnedSection || false);
            }
            return html;
        }

        function buildSectionHeader(label) {
            const text = filterInput.value.trim();
            const suffix = text ? ': <span class="filter-query">\u2018' + escapeHtml(text) + '\u2019</span>' : '';
            return '<div class="pinned-section-header">' + label + suffix + '</div>';
        }

        function renderPinnedSection(allFilteredTargets) {
            const allPinned = [...settingsPinnedTargets, ...pinnedTargets];
            const uniquePinned = [...new Set(allPinned)];
            const pinnedFiltered = allFilteredTargets.filter(t => t.underlyingLabel !== undefined && uniquePinned.includes(t.displayName));
            if (pinnedFiltered.length === 0) return '';
            let html = buildSectionHeader('Pinned');
            const tree = buildTree(pinnedFiltered);
            compactTree(tree);
            html += renderTree(tree, 0, 'pinned', true);
            html += '<div class="pinned-section-separator"></div>';
            return html;
        }

        function renderTargets() {
            if (!allTargets) {
                targetList.innerHTML = '<div class="waiting"><div class="spinner"></div>Waiting for the graph to be processed...</div>';
                return;
            }

            const filterText = filterInput.value.trim().toLowerCase();
            const selectedTypes = getSelectedTypes();

            const filteredTargets = allTargets.filter(t => {
                const matchesText = !filterText || t.displayName.toLowerCase().includes(filterText);
                const matchesType = selectedTypes.includes(t.type);
                const matchesPath = matchesPathFilters(t.displayName);
                return matchesText && matchesType && matchesPath;
            });

            if (filteredTargets.length === 0) {
                targetList.innerHTML = '<div class="waiting">No targets match the filter</div>';
                return;
            }

            const allPinned = new Set([...settingsPinnedTargets, ...pinnedTargets]);
            let html = '';
            const pinnedHtml = renderPinnedSection(filteredTargets);
            html += pinnedHtml;
            const unpinnedTargets = filteredTargets.filter(t => t.underlyingLabel !== undefined && !allPinned.has(t.displayName));
            if (unpinnedTargets.length > 0) {
                html += buildSectionHeader('Targets');
            }
            const tree = buildTree(unpinnedTargets);
            compactTree(tree);
            html += renderTree(tree, 0, '', false);
            targetList.innerHTML = html;
        }

        // Signal that the webview is ready to receive data
        const vscode = acquireVsCodeApi();

        function saveFilterState() {
            const state = {
                types: {
                    app: filterApp.checked,
                    test: filterTest.checked,
                    library: filterLibrary.checked,
                },
                paths: {},
                textFilter: filterInput.value,
                pinnedTargets: pinnedTargets,
            };
            pathFilters.forEach(({ checkbox, pattern }) => {
                state.paths[pattern] = checkbox.checked;
            });
            vscode.postMessage({ type: 'saveFilterState', state });
            saveWebviewState();
        }

        function restoreFilterState(state) {
            if (state.types) {
                filterApp.checked = state.types.app;
                filterTest.checked = state.types.test;
                filterLibrary.checked = state.types.library;
            }
            if (state.paths) {
                pathFilters.forEach(({ checkbox, pattern }) => {
                    if (pattern in state.paths) {
                        checkbox.checked = state.paths[pattern];
                    }
                });
            }
            if (state.textFilter) {
                filterInput.value = state.textFilter;
            }
            if (state.pinnedTargets) {
                pinnedTargets = state.pinnedTargets;
            }
            updateFilterButtonState();
            updateClearButton();
            renderTargets();
        }

        function updateClearButton() {
            filterClear.classList.toggle('visible', filterInput.value.length > 0);
        }

        filterInput.addEventListener('input', () => {
            updateClearButton();
            renderTargets();
            saveFilterState();
        });

        filterClear.addEventListener('click', () => {
            filterInput.value = '';
            updateClearButton();
            filterInput.focus();
            renderTargets();
            saveFilterState();
        });

        filterButton.addEventListener('click', (e) => {
            if (e.target.closest('.filter-option')) return;
            filterDropdown.classList.toggle('show');
        });

        filterDropdown.addEventListener('click', (e) => {
            e.stopPropagation();
        });

        [...typeCheckboxes, ...pathFilters.map(f => f.checkbox)].forEach(checkbox => {
            checkbox.addEventListener('change', () => {
                updateFilterButtonState();
                renderTargets();
                saveFilterState();
            });
        });

        document.addEventListener('click', (e) => {
            if (!filterButton.contains(e.target)) {
                filterDropdown.classList.remove('show');
            }
        });

        function saveWebviewState() {
            vscode.setState({
                targets: allTargets,
                filterState: {
                    types: {
                        app: filterApp.checked,
                        test: filterTest.checked,
                        library: filterLibrary.checked,
                    },
                    paths: pathFilters.reduce((acc, { checkbox, pattern }) => {
                        acc[pattern] = checkbox.checked;
                        return acc;
                    }, {}),
                    textFilter: filterInput.value,
                    pinnedTargets: pinnedTargets,
                }
            });
        }

        // Restore state immediately from webview state if available
        const previousState = vscode.getState();
        if (previousState) {
            allTargets = previousState.targets;
            if (previousState.filterState) {
                restoreFilterState(previousState.filterState);
            } else {
                renderTargets();
            }
        }

        const simulatorLabel = document.getElementById('simulatorLabel');
        const simulatorRuntime = document.getElementById('simulatorRuntime');
        const simulatorButton = document.getElementById('simulatorButton');
        let currentSimulator = null;

        function updateSimulatorDisplay(simulator) {
            currentSimulator = simulator;
            if (simulator) {
                simulatorLabel.textContent = simulator.name;
                simulatorRuntime.textContent = simulator.runtime;
            } else {
                simulatorLabel.textContent = 'Select Physical or Simulator Device';
                simulatorRuntime.textContent = '';
            }
        }

        function setSimulatorLoadingDisplay(loading) {
            simulatorButton.disabled = loading;
            if (loading) {
                simulatorLabel.textContent = 'Loading devices\u2026';
                simulatorRuntime.textContent = '';
            } else {
                updateSimulatorDisplay(currentSimulator);
            }
        }

        const testSimulatorLabel = document.getElementById('testSimulatorLabel');
        const testSimulatorRuntime = document.getElementById('testSimulatorRuntime');
        const clearTestSimulatorButton = document.getElementById('clearTestSimulatorButton');
        const testSimulatorButton = document.getElementById('testSimulatorButton');
        let currentTestSimulator = null;

        function updateTestSimulatorDisplay(simulator) {
            currentTestSimulator = simulator;
            if (simulator) {
                testSimulatorLabel.textContent = simulator.name;
                testSimulatorRuntime.textContent = simulator.runtime;
                clearTestSimulatorButton.style.display = '';
            } else {
                testSimulatorLabel.textContent = 'Test Device: Using app device';
                testSimulatorRuntime.textContent = '';
                clearTestSimulatorButton.style.display = 'none';
            }
        }

        function setTestSimulatorLoadingDisplay(loading) {
            testSimulatorButton.disabled = loading;
            clearTestSimulatorButton.disabled = loading;
            if (loading) {
                testSimulatorLabel.textContent = 'Loading devices\u2026';
                testSimulatorRuntime.textContent = '';
            } else {
                updateTestSimulatorDisplay(currentTestSimulator);
            }
        }

        window.addEventListener('message', event => {
            const message = event.data;
            if (message.type === 'updateTargets') {
                allTargets = message.targets;
                renderTargets();
                saveWebviewState();
            } else if (message.type === 'updateSettingsPinnedTargets') {
                settingsPinnedTargets = message.targets || [];
                renderTargets();
            } else if (message.type === 'restoreFilterState') {
                restoreFilterState(message.state);
            } else if (message.type === 'updateRunningState') {
                if (message.targetLabel && message.action) {
                    runningState = { targetLabel: message.targetLabel, action: message.action, pending: message.pending };
                } else {
                    runningState = null;
                }
                renderTargets();
            } else if (message.type === 'updateSimulatorInfo') {
                updateSimulatorDisplay(message.simulator);
            } else if (message.type === 'updateTestSimulatorInfo') {
                updateTestSimulatorDisplay(message.simulator);
            } else if (message.type === 'setSimulatorLoading') {
                setSimulatorLoadingDisplay(message.loading);
            } else if (message.type === 'setTestSimulatorLoading') {
                setTestSimulatorLoadingDisplay(message.loading);
            } else if (message.type === 'clearState') {
                pinnedTargets = [];
                vscode.setState(null);
                renderTargets();
            }
        });

        vscode.postMessage({ type: 'ready' });

        simulatorButton.addEventListener('click', () => {
            setSimulatorLoadingDisplay(true);
            vscode.postMessage({ type: 'selectSimulator' });
        });

        testSimulatorButton.addEventListener('click', () => {
            setTestSimulatorLoadingDisplay(true);
            vscode.postMessage({ type: 'selectTestSimulator' });
        });

        document.getElementById('clearTestSimulatorButton').addEventListener('click', () => {
            vscode.postMessage({ type: 'clearTestSimulator' });
        });

        targetList.addEventListener('click', (e) => {
            const treeHeader = e.target.closest('.tree-header');
            if (treeHeader) {
                const pathKey = treeHeader.dataset.pathKey;
                toggleExpanded(pathKey);
                return;
            }
            const button = e.target.closest('.action-button');
            if (button) {
                const action = button.dataset.action;
                const label = button.dataset.label;
                if (action === 'build') {
                    vscode.postMessage({ type: 'buildTarget', label });
                } else if (action === 'launch') {
                    vscode.postMessage({ type: 'launchTarget', label });
                } else if (action === 'launchWithoutDebugging') {
                    vscode.postMessage({ type: 'launchTargetWithoutDebugging', label });
                } else if (action === 'test') {
                    vscode.postMessage({ type: 'testTarget', label });
                } else if (action === 'testWithoutDebugging') {
                    vscode.postMessage({ type: 'testTargetWithoutDebugging', label });
                } else if (action === 'stop') {
                    vscode.postMessage({ type: 'stopBuild' });
                } else if (action === 'pin') {
                    // Don't allow toggling settings-pinned targets from UI
                    if (button.dataset.settingsPinned === 'true') {
                        return;
                    }
                    const index = pinnedTargets.indexOf(label);
                    if (index >= 0) {
                        pinnedTargets.splice(index, 1);
                    } else {
                        pinnedTargets.push(label);
                    }
                    renderTargets();
                    saveFilterState();
                }
            }
        });
    </script>
</body>
</html>`;
    }
}
