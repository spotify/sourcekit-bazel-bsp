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
import { ChildProcess, spawn } from "child_process";

const SUBSYSTEM = "com.spotify.sourcekit-bazel-bsp";
const CATEGORY = "extension";

export class LogStreamManager {
    private process: ChildProcess | undefined;
    private outputChannel: vscode.OutputChannel;

    constructor(outputChannel: vscode.OutputChannel) {
        this.outputChannel = outputChannel;
    }

    start(): void {
        if (this.process) {
            return; // Already running
        }

        const predicate = `subsystem == "${SUBSYSTEM}" AND category == "${CATEGORY}"`;
        const args = [
            "stream",
            "--predicate",
            predicate,
            "--style",
            "compact",
            "--level",
            "debug",
        ];

        this.process = spawn("log", args);

        this.process.stdout?.on("data", (data: Buffer) => {
            const lines = data.toString().split("\n");
            for (const line of lines) {
                const parsed = this.parseLine(line);
                if (parsed) {
                    this.outputChannel.appendLine(parsed);
                }
            }
        });

        this.process.stderr?.on("data", (data: Buffer) => {
            const message = data.toString().trim();
            if (message) {
                this.outputChannel.appendLine(`[log stream error] ${message}`);
            }
        });

        this.process.on("error", (err) => {
            this.outputChannel.appendLine(
                `[log stream] Failed to start: ${err.message}`
            );
            this.process = undefined;
        });

        this.process.on("close", (code) => {
            this.outputChannel.appendLine(
                `[log stream] Process exited with code ${code}`
            );
            this.process = undefined;
        });
    }

    stop(): void {
        if (this.process) {
            this.process.kill();
            this.process = undefined;
        }
    }

    private parseLine(line: string): string | undefined {
        const trimmed = line.trim();
        if (!trimmed) {
            return undefined;
        }

        // Skip log stream header lines
        if (
            trimmed.startsWith("Filtering the log data") ||
            trimmed.startsWith("Timestamp")
        ) {
            return undefined;
        }

        const match = trimmed.match(
            /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\S+\s+\S+\[.+?\]\s+\[.+?\]\s+(.+)$/
        );
        if (match) {
            return match[1];
        }

        return trimmed;
    }
}
