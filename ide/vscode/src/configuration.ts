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

const DEFAULT_PROCESSED_GRAPH_PATH = ".bsp/skbsp_generated/graph-processed.json";

export class Configuration {
    private _extraBuildFlags: string;
    private _extraTestBuildFlags: string;
    private _launchArgs: string;
    private _testArgs: string;
    private _processedGraphPath: string;
    private _appsToAlwaysInclude: string[];
    private _enableTestDiscovery: boolean;
    private _rulesAppleName: string;
    private _testDiscoveryConcurrency: number;
    private _disposable: vscode.Disposable;
    private _onDidChange = new vscode.EventEmitter<void>();

    readonly onDidChange = this._onDidChange.event;

    constructor() {
        this._extraBuildFlags = "";
        this._extraTestBuildFlags = "";
        this._launchArgs = "";
        this._testArgs = "";
        this._processedGraphPath = DEFAULT_PROCESSED_GRAPH_PATH;
        this._appsToAlwaysInclude = [];
        this._enableTestDiscovery = true;
        this._rulesAppleName = "rules_apple";
        this._testDiscoveryConcurrency = 10;
        this.reload();

        this._disposable = vscode.workspace.onDidChangeConfiguration((e) => {
            if (e.affectsConfiguration("sourcekit-bazel-bsp")) {
                this.reload();
                this._onDidChange.fire();
            }
        });
    }

    private reload(): void {
        const config = vscode.workspace.getConfiguration("sourcekit-bazel-bsp");
        this._extraBuildFlags = config.get<string>("extraBuildFlags", "");
        this._extraTestBuildFlags = config.get<string>("extraTestBuildFlags", "");
        this._launchArgs = config.get<string>("launchArgs", "");
        this._testArgs = config.get<string>("testArgs", "");
        this._processedGraphPath = config.get<string>("processedGraphPath", DEFAULT_PROCESSED_GRAPH_PATH);
        this._appsToAlwaysInclude = config.get<string[]>("appsToAlwaysInclude", []);
        this._enableTestDiscovery = config.get<boolean>("enableTestDiscovery", true);
        this._rulesAppleName = config.get<string>("rulesAppleName", "rules_apple");
        this._testDiscoveryConcurrency = config.get<number>("testDiscoveryConcurrency", 10);
    }

    get extraBuildFlags(): string {
        return this._extraBuildFlags;
    }

    get extraTestBuildFlags(): string {
        return this._extraTestBuildFlags;
    }

    get launchArgs(): string {
        return this._launchArgs;
    }

    get testArgs(): string {
        return this._testArgs;
    }

    get processedGraphPath(): string {
        return this._processedGraphPath;
    }

    get appsToAlwaysInclude(): string[] {
        return this._appsToAlwaysInclude;
    }

    get enableTestDiscovery(): boolean {
        return this._enableTestDiscovery;
    }

    get rulesAppleName(): string {
        return this._rulesAppleName;
    }

    get testDiscoveryConcurrency(): number {
        return this._testDiscoveryConcurrency;
    }

    dispose(): void {
        this._disposable.dispose();
        this._onDidChange.dispose();
    }
}
