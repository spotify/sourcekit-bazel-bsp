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
import { spawn, execFile, ChildProcess } from "child_process";

const POLL_INTERVAL_MS = 1000;

export class BspLogsViewer implements vscode.Disposable {
    private outputChannel: vscode.OutputChannel;
    private logProcess: ChildProcess | undefined;
    private processWatcher: ChildProcess | undefined;
    private pollTimer: ReturnType<typeof setInterval> | undefined;
    private drainTimer: ReturnType<typeof setTimeout> | undefined;
    private currentBspPid: number | undefined;

    constructor() {
        this.outputChannel = vscode.window.createOutputChannel("SourceKit-Bazel-BSP (Server)");
    }

    public start(): void {
        this.outputChannel.appendLine("Starting BSP log streamer, polling for BSP process...");
        this.startPolling();
    }

    // -- State: POLLING (looking for the BSP process) --

    private startPolling(): void {
        if (this.pollTimer !== undefined) {
            return;
        }
        this.pollForBspPid();
        this.pollTimer = setInterval(() => this.pollForBspPid(), POLL_INTERVAL_MS);
    }

    private stopPolling(): void {
        if (this.pollTimer !== undefined) {
            clearInterval(this.pollTimer);
            this.pollTimer = undefined;
        }
    }

    private pollForBspPid(): void {
        this.findBspPid().then((pid) => {
            if (pid === undefined) {
                return;
            }

            // Found it — stop polling and switch to watching
            this.stopPolling();
            this.outputChannel.appendLine(`Found BSP process with pid ${pid}`);
            this.currentBspPid = pid;
            this.startLogStream(pid);
            this.startProcessWatcher(pid);
        });
    }

    // -- State: WATCHING (BSP is alive, streaming logs) --

    private startProcessWatcher(pid: number): void {
        this.stopProcessWatcher();

        // Use macOS DispatchSource (backed by kqueue EVFILT_PROC / NOTE_EXIT) to
        // get a kernel-level notification when the BSP process exits — no polling.
        const swiftCode = [
            "import Foundation",
            `let source = DispatchSource.makeProcessSource(identifier: ${pid}, eventMask: .exit, queue: .main)`,
            "source.setEventHandler { exit(0) }",
            "source.resume()",
            "dispatchMain()",
        ].join("; ");

        const watcher = spawn("swift", ["-e", swiftCode], { stdio: "ignore" });
        this.processWatcher = watcher;

        watcher.on("close", () => {
            if (this.processWatcher !== watcher) {
                return; // Intentionally replaced by a newer watcher
            }
            this.processWatcher = undefined;
            if (this.currentBspPid === undefined) {
                return; // Already cleaned up (e.g. via dispose)
            }
            this.outputChannel.appendLine("BSP process exited, draining remaining logs...");
            this.currentBspPid = undefined;
            // The kernel notification fires instantly on process exit, but the
            // `log stream` command needs a moment to flush remaining entries
            // (especially error/fault lines). Give it time before tearing down.
            this.drainTimer = setTimeout(() => {
                this.drainTimer = undefined;
                this.stopLogStream();
                this.outputChannel.appendLine("Waiting for BSP to restart...");
                this.startPolling();
            }, 2000);
        });
    }

    private stopProcessWatcher(): void {
        if (this.processWatcher) {
            this.processWatcher.kill();
            this.processWatcher = undefined;
        }
    }

    // -- PID discovery --

    private async findBspPid(): Promise<number | undefined> {
        // Walk the process tree: extension-host -> children -> grandchildren
        // Looking for a process named sourcekit-bazel-bsp
        const extensionHostPid = process.pid;
        const children = await this.getChildPids(extensionHostPid);

        for (const childPid of children) {
            const childName = await this.getProcessName(childPid);
            if (childName === undefined || (!childName.endsWith("/sourcekit-lsp") && childName !== "sourcekit-lsp")) {
                continue;
            }
            const grandchildren = await this.getChildPids(childPid);
            for (const gcPid of grandchildren) {
                const name = await this.getProcessName(gcPid);
                if (name !== undefined && (name.endsWith("/sourcekit-bazel-bsp") || name == "sourcekit-bazel-bsp")) {
                    return gcPid;
                }
            }
        }
        return undefined;
    }

    private getChildPids(parentPid: number): Promise<number[]> {
        return new Promise((resolve) => {
            execFile("pgrep", ["-P", String(parentPid)], (error, stdout) => {
                if (error) {
                    resolve([]);
                    return;
                }
                const pids = stdout
                    .trim()
                    .split("\n")
                    .filter((line) => line.length > 0)
                    .map((line) => parseInt(line, 10))
                    .filter((pid) => !isNaN(pid));
                resolve(pids);
            });
        });
    }

    private getProcessName(pid: number): Promise<string | undefined> {
        return new Promise((resolve) => {
            execFile("ps", ["-p", String(pid), "-o", "comm="], (error, stdout) => {
                if (error) {
                    resolve(undefined);
                    return;
                }
                const name = stdout.trim();
                resolve(name.length > 0 ? name : undefined);
            });
        });
    }

    // -- Log stream --

    private startLogStream(pid: number): void {
        this.stopLogStream();

        const predicate = `processIdentifier==${pid} AND subsystem=='com.spotify.sourcekit-bazel-bsp'`;
        const child = spawn("log", [
            "stream",
            "--style",
            "compact",
            "--predicate",
            predicate,
            "--level",
            "debug"
        ]);

        let buffer = "";
        let pendingEntry = "";
        child.stdout?.on("data", (chunk: Buffer) => {
            buffer += chunk.toString();
            const lines = buffer.split("\n");
            // Keep the last (possibly incomplete) line in the buffer
            buffer = lines.pop() ?? "";
            for (const line of lines) {
                if (line.length === 0) {
                    continue;
                }
                // Compact log entries start with a timestamp (e.g. "2026-03-09 12:34:56.789").
                // Lines without one are continuations of a multi-line message.
                if (/^\d{4}-\d{2}-\d{2}\s/.test(line)) {
                    if (pendingEntry.length > 0) {
                        this.processLine(pendingEntry);
                    }
                    pendingEntry = line;
                } else {
                    pendingEntry += "\n" + line;
                }
            }
        });

        // Flush any remaining entry when the stream ends.
        child.stdout?.on("end", () => {
            if (pendingEntry.length > 0) {
                this.processLine(pendingEntry);
                pendingEntry = "";
            }
        });

        child.stderr?.on("data", (data: Buffer) => {
            this.outputChannel.appendLine(data.toString());
        });

        child.on("error", (error: Error) => {
            this.outputChannel.appendLine(`Error: ${error.message}`);
            vscode.window.showErrorMessage(`Log Stream Error: ${error.message}`);
        });

        child.on("close", (code: number | null) => {
            this.outputChannel.appendLine(`Log stream exited with code ${code}`);
            // If we didn't intentionally stop it and the BSP is still alive, restart.
            if (this.logProcess === child && this.currentBspPid !== undefined) {
                this.logProcess = undefined;
                this.outputChannel.appendLine(`Restarting log stream for BSP pid ${this.currentBspPid}`);
                this.startLogStream(this.currentBspPid);
            }
        });

        this.logProcess = child;
    }

    private processLine(entry: string): void {
        this.outputChannel.appendLine(entry);
        const firstLine = entry.split("\n", 1)[0];
        if (firstLine.includes(" F  sourcekit-bazel-bsp[") || firstLine.includes(" E  sourcekit-bazel-bsp[")) {
            const message = this.extractMessageFromLogEntry(entry);
            if (message.includes("Failed to build targets") || message.includes("Error while replying to buildTarget/prepare")) {
                return;
            }
            vscode.window.showErrorMessage(message);
        }
    }

    private extractMessageFromLogEntry(entry: string): string {
        const firstLine = entry.split("\n", 1)[0];
        const startIndex = firstLine.indexOf("[com.spotify.sourcekit-bazel-bsp:");
        const endIndex = firstLine.indexOf("]", startIndex);
        const headerMessage = firstLine.substring(endIndex + 1).trim();
        // Include continuation lines (the actual error details)
        const newlineIndex = entry.indexOf("\n");
        if (newlineIndex === -1) {
            return headerMessage;
        }
        const continuation = entry.substring(newlineIndex + 1).trim();
        return headerMessage + "\n" + continuation;
    }

    private stopLogStream(): void {
        if (this.logProcess) {
            this.logProcess.kill();
            this.logProcess = undefined;
        }
    }

    // -- Public API --

    public show(): void {
        this.outputChannel.show();
    }

    public dispose(): void {
        this.stopPolling();
        if (this.drainTimer !== undefined) {
            clearTimeout(this.drainTimer);
            this.drainTimer = undefined;
        }
        this.currentBspPid = undefined;
        this.stopProcessWatcher();
        this.stopLogStream();
        this.outputChannel.dispose();
    }
}
