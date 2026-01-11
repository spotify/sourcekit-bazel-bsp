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

import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { Target } from "./types";
import { log } from "./logger";

const DEFAULT_BSP_GRAPH_PATH = ".bsp/skbsp_generated/graph.json";

function getBspGraphPath(): string {
    const config = vscode.workspace.getConfiguration("sourcekit-bazel-bsp");
    return config.get<string>("bspGraphPath", DEFAULT_BSP_GRAPH_PATH);
}

interface TopLevelTarget {
    configId: number;
    label: string;
    launchType: "app" | "test";
}

interface Configuration {
    id: number;
    platform: string;
    minimumOsVersion: string;
    cpuArch: string;
}

interface BspGraphJson {
    topLevelTargets?: TopLevelTarget[];
    dependencyTargets?: { configId: number; label: string }[];
    configurations?: Configuration[];
}

export function parseTargetsFromGraph(json: BspGraphJson): Target[] {
    const targets: Target[] = [];

    // Build a map of configId to configuration
    const configMap = new Map<number, Configuration>();
    for (const config of json.configurations ?? []) {
        configMap.set(config.id, config);
    }

    // Add top-level targets (apps and tests)
    for (const target of json.topLevelTargets ?? []) {
        const config = configMap.get(target.configId);
        if (config?.platform === "darwin") {
            continue;
        }
        targets.push({
            label: target.label,
            uri: target.label,
            kind: target.launchType,
            platform: config?.platform,
            minimumOsVersion: config?.minimumOsVersion,
        });
    }

    // Add dependency targets (libraries)
    for (const target of json.dependencyTargets ?? []) {
        const config = configMap.get(target.configId);
        if (config?.platform === "darwin") {
            continue;
        }
        targets.push({
            label: target.label,
            uri: target.label,
            kind: "library",
            platform: config?.platform,
            minimumOsVersion: config?.minimumOsVersion,
        });
    }

    return targets;
}

export interface TargetsUpdate {
    targets: Target[];
    graphFileExists: boolean;
}

export type TargetsChangedCallback = (update: TargetsUpdate) => void;

export class BspGraphWatcher {
    private watcher: fs.FSWatcher | undefined;
    private dirWatcher: fs.FSWatcher | undefined;
    private configWatcher: vscode.Disposable | undefined;
    private callback: TargetsChangedCallback;
    private currentTargets: Target[] = [];
    private currentPath: string = "";

    constructor(callback: TargetsChangedCallback) {
        this.callback = callback;
    }

    start(): void {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            log("No workspace folder found");
            return;
        }

        const relativePath = getBspGraphPath();
        this.currentPath = path.join(workspaceFolder.uri.fsPath, relativePath);
        this.loadAndNotify();
        this.watchFile();

        // Watch for configuration changes
        this.configWatcher = vscode.workspace.onDidChangeConfiguration(async (e) => {
            if (e.affectsConfiguration("sourcekit-bazel-bsp.bspGraphPath")) {
                const newRelativePath = getBspGraphPath();
                const newPath = path.join(workspaceFolder.uri.fsPath, newRelativePath);
                if (newPath !== this.currentPath) {
                    const reload = await vscode.window.showInformationMessage(
                        "BSP graph path has changed. Reload window to apply?",
                        "Reload"
                    );
                    if (reload === "Reload") {
                        vscode.commands.executeCommand("workbench.action.reloadWindow");
                    }
                }
            }
        });
    }

    stop(): void {
        this.stopFileWatchers();
        if (this.configWatcher) {
            this.configWatcher.dispose();
            this.configWatcher = undefined;
        }
    }

    private stopFileWatchers(): void {
        if (this.watcher) {
            this.watcher.close();
            this.watcher = undefined;
        }
        if (this.dirWatcher) {
            this.dirWatcher.close();
            this.dirWatcher = undefined;
        }
    }

    private loadAndNotify(): void {
        const result = this.loadTargets();
        if (this.hasTargetsChanged(result.targets)) {
            this.currentTargets = result.targets;
            this.callback(result);
        }
    }

    private hasTargetsChanged(newTargets: Target[]): boolean {
        if (newTargets.length !== this.currentTargets.length) {
            return true;
        }
        for (let i = 0; i < newTargets.length; i++) {
            if (
                newTargets[i].uri !== this.currentTargets[i].uri ||
                newTargets[i].kind !== this.currentTargets[i].kind
            ) {
                return true;
            }
        }
        return false;
    }

    private loadTargets(): TargetsUpdate {
        try {
            if (!this.currentPath || !fs.existsSync(this.currentPath)) {
                log("BSP graph file does not exist yet");
                return { targets: [], graphFileExists: false };
            }

            const content = fs.readFileSync(this.currentPath, "utf-8");
            const json: BspGraphJson = JSON.parse(content);
            const targets = parseTargetsFromGraph(json);
            log(`Loaded ${targets.length} targets from BSP graph`);
            return { targets, graphFileExists: true };
        } catch (error) {
            log(`Error loading BSP graph: ${error}`);
            return { targets: [], graphFileExists: false };
        }
    }

    private watchFile(): void {
        if (!this.currentPath) {
            return;
        }

        const dir = path.dirname(this.currentPath);
        const filename = path.basename(this.currentPath);

        // Watch the directory for file creation/deletion
        try {
            if (fs.existsSync(dir)) {
                this.dirWatcher = fs.watch(dir, (eventType, changedFile) => {
                    if (changedFile === filename) {
                        log(`BSP graph file ${eventType}`);
                        this.loadAndNotify();
                        // Re-establish file watcher if file was created
                        if (eventType === "rename" && fs.existsSync(this.currentPath)) {
                            this.watchFileDirectly();
                        }
                    }
                });
            }
        } catch (error) {
            log(`Could not watch BSP graph directory: ${error}`);
        }

        // Also watch the file directly for content changes
        this.watchFileDirectly();
    }

    private watchFileDirectly(): void {
        if (this.watcher) {
            this.watcher.close();
        }

        if (!this.currentPath) {
            return;
        }

        try {
            if (fs.existsSync(this.currentPath)) {
                this.watcher = fs.watch(this.currentPath, (eventType) => {
                    if (eventType === "change") {
                        log("BSP graph file changed");
                        this.loadAndNotify();
                    }
                });
            }
        } catch (error) {
            log(`Could not watch BSP graph file: ${error}`);
        }
    }
}
