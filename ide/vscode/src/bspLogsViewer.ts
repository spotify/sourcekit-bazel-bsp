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
import { spawn, ChildProcess } from "child_process";

export class BspLogsViewer implements vscode.Disposable {
    private outputChannel: vscode.OutputChannel;
    private logProcess: ChildProcess | undefined;

    constructor() {
        this.outputChannel = vscode.window.createOutputChannel("SourceKit-Bazel-BSP (Server)");
    }

    public start(): void {
        if (this.logProcess) {
            this.outputChannel.appendLine("Log stream already running");
            return;
        }

        this.outputChannel.appendLine("Starting log stream for sourcekit-bazel-bsp...");

        // make senderImagePAth with is the workspace root
        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
        const senderImagePath = `${workspaceRoot}/.bsp/sourcekit-bazel-bsp`;
        this.logProcess = spawn("log", [
            "stream",
            "--process",
            "sourcekit-bazel-bsp",
            "--style",
            "compact",
            "--predicate",
            `subsystem='com.spotify.sourcekit-bazel-bsp' AND senderImagePath='${senderImagePath}'`,
            "--debug"
        ]);

        this.logProcess.stdout?.on("data", (data: Buffer) => {
            this.process(data);
        });

        this.logProcess.stderr?.on("data", (data: Buffer) => {
            this.process(data);
        });

        this.logProcess.on("error", (error: Error) => {
            this.outputChannel.appendLine(`Error: ${error.message}`);
            vscode.window.showErrorMessage(`Log Stream Error: ${error.message}`);
        });

        this.logProcess.on("close", (code: number | null) => {
            this.outputChannel.appendLine(`Log stream exited with code ${code}`);
            this.logProcess = undefined;
        });
    }

    private process(data: Buffer): void {
        const text = data.toString();
        this.outputChannel.appendLine(text);
        if (text.includes(" F  sourcekit-bazel-bsp[") || text.includes(" E  sourcekit-bazel-bsp[")) {
            const message = this.extractMessageFromLogLine(text);
            // if contains
            if (message.includes("Failed to build targets") || message.includes("Error while replying to buildTarget/prepare")) {
                return;
            }
            vscode.window.showErrorMessage(message);
        }
    }

    private extractMessageFromLogLine(line: string): string {
        const startIndex = line.indexOf("[com.spotify.sourcekit-bazel-bsp:");
        const endIndex = line.indexOf("]", startIndex);
        return line.substring(endIndex + 1);
    }

    public stop(): void {
        if (this.logProcess) {
            this.logProcess.kill();
            this.logProcess = undefined;
            this.outputChannel.appendLine("Log stream stopped");
        }
    }

    public show(): void {
        this.outputChannel.show();
    }

    public dispose(): void {
        this.stop();
        this.outputChannel.dispose();
    }
}
