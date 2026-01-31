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
import { getCurrentSimulatorInfo, SimulatorInfo } from "./simulatorPicker";

interface FilterState {
    types: { app: boolean; test: boolean; library: boolean };
    paths: { [key: string]: boolean };
    textFilter: string;
    pinnedTargets: string[];
}

const FILTER_STATE_KEY = "skbsp.filterState";

export class TargetsViewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = "skbspTargets";

    private _view?: vscode.WebviewView;
    private targets: ProcessedTarget[] | undefined;
    private _onBuildTarget?: (target: ProcessedTarget) => void;
    private _onLaunchTarget?: (target: ProcessedTarget) => void;
    private _onLaunchTargetWithoutDebugging?: (target: ProcessedTarget) => void;
    private _onTestTarget?: (target: ProcessedTarget) => void;
    private _onTestTargetWithoutDebugging?: (target: ProcessedTarget) => void;
    private _onSelectSimulator?: () => void;

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

    setTargets(targets: ProcessedTarget[]): void {
        this.targets = targets;
        this._sendTargetsToWebview();
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
                this._sendSimulatorInfoToWebview();
            }
        });

        webviewView.webview.onDidReceiveMessage((message) => {
            if (message.type === "ready") {
                this._sendTargetsToWebview();
                this._sendFilterStateToWebview();
                this._sendSimulatorInfoToWebview();
            } else if (message.type === "saveFilterState") {
                this._workspaceState.update(FILTER_STATE_KEY, message.state);
            } else if (message.type === "buildTarget") {
                const target = this.targets?.find(t => t.label === message.label);
                if (target && this._onBuildTarget) {
                    this._onBuildTarget(target);
                }
            } else if (message.type === "launchTarget") {
                const target = this.targets?.find(t => t.label === message.label);
                if (target) {
                    if (target.type === "test" && this._onTestTarget) {
                        this._onTestTarget(target);
                    } else if (this._onLaunchTarget) {
                        this._onLaunchTarget(target);
                    }
                }
            } else if (message.type === "launchTargetWithoutDebugging") {
                const target = this.targets?.find(t => t.label === message.label);
                if (target) {
                    if (target.type === "test" && this._onTestTargetWithoutDebugging) {
                        this._onTestTargetWithoutDebugging(target);
                    } else if (this._onLaunchTargetWithoutDebugging) {
                        this._onLaunchTargetWithoutDebugging(target);
                    }
                }
            } else if (message.type === "testTarget") {
                const target = this.targets?.find(t => t.label === message.label);
                if (target && this._onTestTarget) {
                    this._onTestTarget(target);
                }
            } else if (message.type === "testTargetWithoutDebugging") {
                const target = this.targets?.find(t => t.label === message.label);
                if (target && this._onTestTargetWithoutDebugging) {
                    this._onTestTargetWithoutDebugging(target);
                }
            } else if (message.type === "selectSimulator") {
                if (this._onSelectSimulator) {
                    this._onSelectSimulator();
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
        const info = await getCurrentSimulatorInfo();
        this._view.webview.postMessage({
            type: "updateSimulatorInfo",
            simulator: info ?? null,
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
            background: var(--vscode-sideBar-background);
            border-bottom: 1px solid var(--vscode-widget-border);
        }
        .filter-row {
            display: flex;
            gap: 4px;
            align-items: center;
        }
        .filter-input {
            flex: 1;
            box-sizing: border-box;
            padding: 4px 8px;
            border: 1px solid var(--vscode-input-border);
            background: var(--vscode-input-background);
            color: var(--vscode-input-foreground);
            border-radius: 2px;
            outline: none;
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
        .action-button {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 22px;
            height: 22px;
            border: none;
            background: transparent;
            color: var(--vscode-foreground);
            border-radius: 2px;
            cursor: pointer;
            opacity: 0;
        }
        .target-item:hover .action-button {
            opacity: 1;
        }
        .action-button:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .pin-button {
            opacity: 0;
        }
        .target-item:hover .pin-button {
            opacity: 1;
        }
        .pin-button.pinned {
            opacity: 1;
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
        .simulator-row .action-button {
            opacity: 0;
        }
        .simulator-row:hover .action-button {
            opacity: 1;
        }
    </style>
</head>
<body>
    <div class="filter-container">
        <div class="filter-row">
            <input
                type="text"
                class="filter-input"
                placeholder="Filter targets..."
                id="filterInput"
            />
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
        <span class="simulator-label" id="simulatorLabel">Select Simulator</span>
        <span class="simulator-runtime" id="simulatorRuntime"></span>
        <button class="action-button" id="simulatorButton" title="Select Simulator for Apple Development">
            <span class="codicon codicon-settings-gear"></span>
        </button>
    </div>
    <div class="target-list" id="targetList">
        <div class="waiting"><div class="spinner"></div>Waiting for the graph to be processed...</div>
    </div>
    <script>
        const filterInput = document.getElementById('filterInput');
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

        function renderTargets() {
            if (!allTargets) {
                targetList.innerHTML = '<div class="waiting"><div class="spinner"></div>Waiting for the graph to be processed...</div>';
                return;
            }

            const filterText = filterInput.value.toLowerCase();
            const selectedTypes = getSelectedTypes();

            const filteredTargets = allTargets.filter(t => {
                const matchesText = !filterText || t.displayName.toLowerCase().includes(filterText);
                const matchesType = selectedTypes.includes(t.type);
                const matchesPath = matchesPathFilters(t.label);
                return matchesText && matchesType && matchesPath;
            });

            // Sort so pinned targets appear first
            const sortedTargets = filteredTargets.sort((a, b) => {
                const aIsPinned = pinnedTargets.includes(a.label);
                const bIsPinned = pinnedTargets.includes(b.label);
                if (aIsPinned && !bIsPinned) return -1;
                if (!aIsPinned && bIsPinned) return 1;
                return 0;
            });

            if (sortedTargets.length === 0) {
                targetList.innerHTML = '<div class="waiting">No targets match the filter</div>';
                return;
            }

            targetList.innerHTML = sortedTargets.map(target => {
                const isPinned = pinnedTargets.includes(target.label);
                const pinIcon = isPinned ? 'pinned' : 'pin';
                const pinClass = isPinned ? 'pin-button pinned' : 'pin-button';
                const pinButton = '<button class="action-button ' + pinClass + '" data-action="pin" data-label="' + escapeHtml(target.label) + '" title="' + (isPinned ? 'Unpin' : 'Pin') + ' target"><span class="codicon codicon-' + pinIcon + '"></span></button>';
                const buildButton = '<button class="action-button" data-action="build" data-label="' + escapeHtml(target.label) + '" title="Build target"><span class="codicon codicon-tools"></span></button>';
                const launchButton = target.canDebug
                    ? '<button class="action-button" data-action="launch" data-label="' + escapeHtml(target.label) + '" title="Run and debug"><span class="codicon codicon-debug-alt"></span></button>'
                    : '';
                const launchWithoutDebuggingButton = target.canRun
                    ? '<button class="action-button" data-action="launchWithoutDebugging" data-label="' + escapeHtml(target.label) + '" title="Run without debugging"><span class="codicon codicon-run"></span></button>'
                    : '';
                return '<div class="target-item">' +
                    '<span class="codicon codicon-' + iconForTargetType(target.type) + '"></span>' +
                    '<span class="target-name">' + escapeHtml(target.displayName) + '</span>' +
                    pinButton +
                    buildButton +
                    launchWithoutDebuggingButton +
                    launchButton +
                '</div>';
            }).join('');
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
            renderTargets();
        }

        filterInput.addEventListener('input', () => {
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

        function updateSimulatorDisplay(simulator) {
            if (simulator) {
                simulatorLabel.textContent = simulator.name;
                simulatorRuntime.textContent = simulator.runtime;
            } else {
                simulatorLabel.textContent = 'Select Simulator';
                simulatorRuntime.textContent = '';
            }
        }

        window.addEventListener('message', event => {
            const message = event.data;
            if (message.type === 'updateTargets') {
                allTargets = message.targets;
                renderTargets();
                saveWebviewState();
            } else if (message.type === 'restoreFilterState') {
                restoreFilterState(message.state);
            } else if (message.type === 'updateSimulatorInfo') {
                updateSimulatorDisplay(message.simulator);
            }
        });

        vscode.postMessage({ type: 'ready' });

        document.getElementById('simulatorButton').addEventListener('click', () => {
            vscode.postMessage({ type: 'selectSimulator' });
        });

        targetList.addEventListener('click', (e) => {
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
                } else if (action === 'pin') {
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
