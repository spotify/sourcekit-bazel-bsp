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

export interface TargetCompletedEvent {
    label: string;
    success: boolean;
}

export interface TestSummaryEvent {
    label: string;
    status: string;
    success: boolean;
}

interface BepBuildEvent {
    id: {
        targetCompleted?: { label: string };
        testSummary?: { label: string };
    };
    completed?: { success: boolean };
    testSummary?: { overallStatus: string };
}

/**
 * Watches a Bazel BEP JSON file (one JSON object per line, written via
 * `--build_event_json_file`) and emits VS Code events for target completion
 * and test summary.
 */
export class BepWatcher implements vscode.Disposable {
    private readonly outputChannel: vscode.OutputChannel;
    private readonly _onTargetCompleted = new vscode.EventEmitter<TargetCompletedEvent>();
    private readonly _onTestSummary = new vscode.EventEmitter<TestSummaryEvent>();

    private fileWatcher: fs.FSWatcher | undefined;
    private currentFilePath: string | undefined;
    private positionRead = 0;
    private lineBuf = "";
    private readPending = false;

    readonly onTargetCompleted = this._onTargetCompleted.event;
    readonly onTestSummary = this._onTestSummary.event;

    constructor(outputChannel: vscode.OutputChannel) {
        this.outputChannel = outputChannel;
    }

    async startWatching(filePath: string): Promise<void> {
        await this.stopWatching();
        this.currentFilePath = filePath;
        this.positionRead = 0;
        this.lineBuf = "";

        try {
            await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
            await fs.promises.writeFile(filePath, "");
        } catch (err) {
            this.outputChannel.appendLine(`[bep] Failed to prepare BEP file: ${err}`);
            this.currentFilePath = undefined;
            return;
        }

        try {
            this.fileWatcher = fs.watch(filePath, { persistent: false }, () => this.scheduleRead());
            this.fileWatcher.on("error", (err) => {
                this.outputChannel.appendLine(`[bep] Watcher error: ${err}`);
            });
        } catch (err) {
            this.outputChannel.appendLine(`[bep] Failed to watch BEP file: ${err}`);
            this.currentFilePath = undefined;
        }
    }

    async stopWatching(): Promise<void> {
        if (this.fileWatcher) {
            this.fileWatcher.close();
            this.fileWatcher = undefined;
        }
        await this.readNew();
        this.currentFilePath = undefined;
        this.positionRead = 0;
        this.lineBuf = "";
    }

    dispose(): void {
        void this.stopWatching();
        this._onTargetCompleted.dispose();
        this._onTestSummary.dispose();
    }

    private scheduleRead(): void {
        if (this.readPending) {
            return;
        }
        this.readPending = true;
        setImmediate(async () => {
            this.readPending = false;
            try {
                await this.readNew();
            } catch (err) {
                this.outputChannel.appendLine(`[bep] Read failed: ${err}`);
            }
        });
    }

    private async readNew(): Promise<void> {
        const filePath = this.currentFilePath;
        if (!filePath) {
            return;
        }
        let stat: fs.Stats;
        try {
            stat = await fs.promises.stat(filePath);
        } catch {
            return;
        }
        if (stat.size < this.positionRead) {
            this.positionRead = 0;
            this.lineBuf = "";
        }
        if (stat.size <= this.positionRead) {
            return;
        }

        const fd = await fs.promises.open(filePath, "r");
        try {
            const length = stat.size - this.positionRead;
            const buf = Buffer.alloc(length);
            const { bytesRead } = await fd.read(buf, 0, length, this.positionRead);
            this.positionRead += bytesRead;
            this.lineBuf += buf.subarray(0, bytesRead).toString("utf8");
        } finally {
            await fd.close();
        }
        this.processLines();
    }

    private processLines(): void {
        const lines = this.lineBuf.split("\n");
        this.lineBuf = lines.pop()!;
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) {
                continue;
            }
            try {
                const parsed: unknown = JSON.parse(trimmed);
                if (isBepBuildEvent(parsed)) {
                    this.handleEvent(parsed);
                }
            } catch (err) {
                this.outputChannel.appendLine(`[bep] Skipping malformed event: ${err}`);
            }
        }
    }

    private handleEvent(event: BepBuildEvent): void {
        const { id } = event;

        if (id.targetCompleted && event.completed) {
            this._onTargetCompleted.fire({
                label: id.targetCompleted.label,
                success: event.completed.success === true,
            });
        } else if (id.testSummary && event.testSummary) {
            const status = event.testSummary.overallStatus ?? "UNKNOWN";
            this._onTestSummary.fire({
                label: id.testSummary.label,
                status,
                success: status === "PASSED" || status === "FLAKY",
            });
        }
    }
}

function isBepBuildEvent(value: unknown): value is BepBuildEvent {
    return typeof value === "object" && value !== null && "id" in value
        && typeof (value as Record<string, unknown>).id === "object";
}
