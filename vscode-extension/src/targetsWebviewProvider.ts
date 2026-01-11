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
import { Target } from "./types";

interface FilterState {
    typeFilters: { app: boolean; test: boolean; library: boolean };
    showExternal: boolean;
}

export class TargetsWebviewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = "bspTargets";
    private static readonly FILTER_STATE_KEY = "targetsFilterState";

    private _view?: vscode.WebviewView;
    private _targets: Target[] = [];
    private _filterText: string = "";
    private _typeFilters = { app: true, test: true, library: true };
    private _showExternal: boolean = true;
    private _graphFileExists: boolean = false;
    private _context: vscode.ExtensionContext;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        context: vscode.ExtensionContext
    ) {
        this._context = context;
        this._loadFilterState();
    }

    private _loadFilterState(): void {
        const state = this._context.workspaceState.get<FilterState>(
            TargetsWebviewProvider.FILTER_STATE_KEY
        );
        if (state) {
            this._typeFilters = state.typeFilters;
            this._showExternal = state.showExternal;
        }
    }

    private _saveFilterState(): void {
        const state: FilterState = {
            typeFilters: this._typeFilters,
            showExternal: this._showExternal,
        };
        this._context.workspaceState.update(
            TargetsWebviewProvider.FILTER_STATE_KEY,
            state
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

        webviewView.webview.onDidReceiveMessage((data) => {
            switch (data.type) {
                case "ready":
                    // Webview is ready, send current targets and filter state
                    this._updateTargetsList();
                    this._view?.webview.postMessage({
                        type: "updateFilterState",
                        typeFilters: this._typeFilters,
                        showExternal: this._showExternal,
                    });
                    break;
                case "filter":
                    this._filterText = data.value.toLowerCase();
                    this._updateTargetsList();
                    break;
                case "typeFilter":
                    this._typeFilters = data.typeFilters;
                    this._showExternal = data.showExternal;
                    this._saveFilterState();
                    this._updateTargetsList();
                    break;
                case "build":
                    vscode.commands.executeCommand(
                        "sourcekit-bazel-bsp.buildTargetByUri",
                        data.uri
                    );
                    break;
                case "launch":
                    vscode.commands.executeCommand(
                        "sourcekit-bazel-bsp.launchTargetByUri",
                        data.uri
                    );
                    break;
            }
        });
    }

    public setTargets(targets: Target[], graphFileExists: boolean = true) {
        // Sort targets alphabetically
        this._targets = [...targets].sort((a, b) =>
            a.label.localeCompare(b.label)
        );
        this._graphFileExists = graphFileExists;
        this._updateTargetsList();
    }

    private _updateTargetsList() {
        if (!this._view) {
            return;
        }

        let filteredTargets = this._targets;

        // Apply text filter
        if (this._filterText) {
            filteredTargets = filteredTargets.filter((t) =>
                t.label.toLowerCase().includes(this._filterText)
            );
        }

        // Apply type filters
        filteredTargets = filteredTargets.filter((t) => this._typeFilters[t.kind]);

        // Apply external filter
        if (!this._showExternal) {
            filteredTargets = filteredTargets.filter((t) => !t.label.startsWith("@"));
        }

        this._view.webview.postMessage({
            type: "updateTargets",
            targets: filteredTargets,
            graphFileExists: this._graphFileExists,
        });
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
        .search-container {
            padding: 8px;
            position: sticky;
            top: 0;
            background: var(--vscode-sideBar-background);
            border-bottom: 1px solid var(--vscode-widget-border);
            display: flex;
            gap: 4px;
            align-items: center;
        }
        .search-input {
            flex: 1;
            padding: 4px 8px;
            border: 1px solid var(--vscode-input-border);
            background: var(--vscode-input-background);
            color: var(--vscode-input-foreground);
            border-radius: 2px;
            outline: none;
        }
        .search-input:focus {
            border-color: var(--vscode-focusBorder);
        }
        .search-input::placeholder {
            color: var(--vscode-input-placeholderForeground);
        }
        .filter-button {
            background: none;
            border: 1px solid transparent;
            color: var(--vscode-foreground);
            cursor: pointer;
            padding: 4px;
            border-radius: 3px;
            display: flex;
            align-items: center;
            justify-content: center;
            position: relative;
        }
        .filter-button:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .filter-button.active {
            color: var(--vscode-textLink-foreground);
        }
        .filter-dropdown {
            display: none;
            position: absolute;
            top: 100%;
            right: 0;
            margin-top: 4px;
            background: var(--vscode-dropdown-background);
            border: 1px solid var(--vscode-dropdown-border);
            border-radius: 3px;
            padding: 8px;
            min-width: 160px;
            z-index: 100;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        .filter-dropdown.show {
            display: block;
        }
        .filter-section {
            margin-bottom: 8px;
        }
        .filter-section:last-child {
            margin-bottom: 0;
        }
        .filter-section-title {
            font-size: 11px;
            text-transform: uppercase;
            color: var(--vscode-descriptionForeground);
            margin-bottom: 4px;
        }
        .filter-option {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 4px 0;
            cursor: pointer;
        }
        .filter-option:hover {
            color: var(--vscode-textLink-foreground);
        }
        .filter-checkbox {
            width: 14px;
            height: 14px;
            accent-color: var(--vscode-textLink-foreground);
        }
        .targets-list {
            padding: 4px 0;
        }
        .target-item {
            display: flex;
            align-items: center;
            padding: 4px 8px;
            cursor: pointer;
            gap: 6px;
        }
        .target-item:hover {
            background: var(--vscode-list-hoverBackground);
        }
        .target-icon {
            width: 16px;
            height: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
        }
        .target-label {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-size: 13px;
        }
        .target-actions {
            display: flex;
            gap: 4px;
            visibility: hidden;
            min-width: 44px;
            justify-content: flex-end;
        }
        .target-item:hover .target-actions {
            visibility: visible;
        }
        .action-button {
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
        .action-button:hover {
            background: var(--vscode-toolbar-hoverBackground);
        }
        .empty-state {
            padding: 16px;
            text-align: center;
            color: var(--vscode-descriptionForeground);
        }
    </style>
</head>
<body>
    <div class="search-container">
        <input type="text" class="search-input" placeholder="Filter targets..." id="searchInput">
        <button class="filter-button" id="filterButton" title="Filter by type">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M1.5 1.5A.5.5 0 0 1 2 1h12a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-.128.334L10 8.692V13.5a.5.5 0 0 1-.342.474l-3 1A.5.5 0 0 1 6 14.5V8.692L1.628 3.834A.5.5 0 0 1 1.5 3.5v-2z"/></svg>
            <div class="filter-dropdown" id="filterDropdown">
                <div class="filter-section">
                    <div class="filter-section-title">Target Type</div>
                    <label class="filter-option">
                        <input type="checkbox" class="filter-checkbox" id="filterApp" checked>
                        <span>Apps</span>
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" class="filter-checkbox" id="filterTest" checked>
                        <span>Tests</span>
                    </label>
                    <label class="filter-option">
                        <input type="checkbox" class="filter-checkbox" id="filterLibrary" checked>
                        <span>Libraries</span>
                    </label>
                </div>
                <div class="filter-section">
                    <div class="filter-section-title">Visibility</div>
                    <label class="filter-option">
                        <input type="checkbox" class="filter-checkbox" id="filterShowExternal" checked>
                        <span>Include external dependencies</span>
                    </label>
                </div>
            </div>
        </button>
    </div>
    <div class="targets-list" id="targetsList"></div>

    <script>
        const vscode = acquireVsCodeApi();
        const searchInput = document.getElementById('searchInput');
        const targetsList = document.getElementById('targetsList');
        const filterButton = document.getElementById('filterButton');
        const filterDropdown = document.getElementById('filterDropdown');
        const filterApp = document.getElementById('filterApp');
        const filterTest = document.getElementById('filterTest');
        const filterLibrary = document.getElementById('filterLibrary');
        const filterShowExternal = document.getElementById('filterShowExternal');

        let allTargets = [];

        searchInput.addEventListener('input', (e) => {
            vscode.postMessage({ type: 'filter', value: e.target.value });
        });

        // Toggle dropdown
        filterButton.addEventListener('click', (e) => {
            if (e.target.closest('.filter-dropdown')) return; // Don't toggle if clicking inside dropdown
            filterDropdown.classList.toggle('show');
        });

        // Close dropdown when clicking outside
        document.addEventListener('click', (e) => {
            if (!filterButton.contains(e.target)) {
                filterDropdown.classList.remove('show');
            }
        });

        // Handle filter changes
        function sendFilterUpdate() {
            const typeFilters = {
                app: filterApp.checked,
                test: filterTest.checked,
                library: filterLibrary.checked
            };
            const showExternal = filterShowExternal.checked;

            // Update button appearance
            const hasActiveFilter = !typeFilters.app || !typeFilters.test || !typeFilters.library || !showExternal;
            filterButton.classList.toggle('active', hasActiveFilter);

            vscode.postMessage({ type: 'typeFilter', typeFilters, showExternal });
        }

        filterApp.addEventListener('change', sendFilterUpdate);
        filterTest.addEventListener('change', sendFilterUpdate);
        filterLibrary.addEventListener('change', sendFilterUpdate);
        filterShowExternal.addEventListener('change', sendFilterUpdate);

        window.addEventListener('message', (event) => {
            const message = event.data;
            if (message.type === 'updateTargets') {
                renderTargets(message.targets, message.graphFileExists);
            } else if (message.type === 'updateFilterState') {
                filterApp.checked = message.typeFilters.app;
                filterTest.checked = message.typeFilters.test;
                filterLibrary.checked = message.typeFilters.library;
                filterShowExternal.checked = message.showExternal;
                const hasActiveFilter = !message.typeFilters.app || !message.typeFilters.test || !message.typeFilters.library || !message.showExternal;
                filterButton.classList.toggle('active', hasActiveFilter);
            }
        });

        function getIcon(kind) {
            switch (kind) {
                case 'app':
                    return '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M5 1H3.5A1.5 1.5 0 0 0 2 2.5v11A1.5 1.5 0 0 0 3.5 15h9a1.5 1.5 0 0 0 1.5-1.5v-11A1.5 1.5 0 0 0 12.5 1H11v1h1.5a.5.5 0 0 1 .5.5v11a.5.5 0 0 1-.5.5h-9a.5.5 0 0 1-.5-.5v-11a.5.5 0 0 1 .5-.5H5V1z"/><path d="M6 1h4v2H6V1z"/></svg>';
                case 'test':
                    return '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M5 1.5A1.5 1.5 0 0 1 6.5 0h3A1.5 1.5 0 0 1 11 1.5v1A1.5 1.5 0 0 1 9.5 4h-3A1.5 1.5 0 0 1 5 2.5v-1zm3 10a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9z"/></svg>';
                default:
                    return '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a2 2 0 0 0-2 2v2H4a2 2 0 0 0-2 2v5a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2V3a2 2 0 0 0-2-2zM7 3a1 1 0 0 1 2 0v2H7V3z"/></svg>';
            }
        }

        function renderTargets(targets, graphFileExists) {
            if (targets.length === 0) {
                if (!graphFileExists) {
                    targetsList.innerHTML = '<div class="empty-state">Waiting for graph report...</div>';
                } else {
                    targetsList.innerHTML = '<div class="empty-state">No targets found</div>';
                }
                return;
            }

            targetsList.innerHTML = targets.map(target => {
                const showLaunch = target.kind === 'app';

                return \`
                    <div class="target-item" data-uri="\${target.uri}">
                        <span class="target-icon">\${getIcon(target.kind)}</span>
                        <span class="target-label" title="\${target.label}">\${target.label}</span>
                        <div class="target-actions">
                            <button class="action-button" onclick="buildTarget('\${target.uri}')" title="Build">
                                <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M0 4.5A1.5 1.5 0 0 1 1.5 3h13A1.5 1.5 0 0 1 16 4.5v7a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 0 11.5v-7zM1.5 4a.5.5 0 0 0-.5.5v7a.5.5 0 0 0 .5.5h13a.5.5 0 0 0 .5-.5v-7a.5.5 0 0 0-.5-.5h-13z"/><path d="M2 5.5a.5.5 0 0 1 .5-.5h2a.5.5 0 0 1 0 1h-2a.5.5 0 0 1-.5-.5z"/></svg>
                            </button>
                            \${showLaunch ? \`
                                <button class="action-button" onclick="launchTarget('\${target.uri}')" title="Launch">
                                    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2v12l10-6-10-6z"/></svg>
                                </button>
                            \` : ''}
                        </div>
                    </div>
                \`;
            }).join('');
        }

        function buildTarget(uri) {
            vscode.postMessage({ type: 'build', uri });
        }

        function launchTarget(uri) {
            vscode.postMessage({ type: 'launch', uri });
        }

        // Signal that webview is ready to receive data
        vscode.postMessage({ type: 'ready' });
    </script>
</body>
</html>`;
    }
}
