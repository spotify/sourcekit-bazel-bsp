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

type LogLevel = "error" | "info" | "debug";

function getLogLevel(): LogLevel {
    const config = vscode.workspace.getConfiguration("sourcekit-bazel-bsp");
    return config.get<LogLevel>("logLevel", "error");
}

interface ParsedLogLine {
    message: string;
    level: "fault" | "error" | "info" | "debug";
}

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

        const logLevel = getLogLevel();
        const args = [
            "stream",
            "--process",
            "sourcekit-bazel-bsp",
            "--style",
            "compact",
        ];

        // Add log level flag based on configuration
        if (logLevel === "debug") {
            args.push("--debug");
        } else if (logLevel === "info") {
            args.push("--info");
        }
        // For "error" level, we don't add any flag (default behavior)

        this.process = spawn("log", args);

        this.process.stdout?.on("data", (data: Buffer) => {
            const lines = data.toString().split("\n");
            for (const line of lines) {
                const parsed = this.parseLine(line);
                if (parsed) {
                    this.outputChannel.appendLine(parsed.message);
                    // Show error messages on the IDE
                    if (parsed.level === "error" || parsed.level == "fault") {
                        vscode.window.showErrorMessage(
                            `${parsed.message}`
                        );
                    }
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

    private parseLine(line: string): ParsedLogLine | undefined {
        const trimmed = line.trim();
        if (!trimmed) {
            return undefined;
        }

        // Parse log format: "2026-01-11 12:00:05.651 I  sourcekit-bazel-bsp[...] [...] Message"
        // Group 1: Log level (I, D, Db, E, F)
        // Group 2: Message
        const match = trimmed.match(
            /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+(\w+)\s+\S+\[.+?\]\s+\[.+?\]\s+(.+)$/
        );

        if (!match) {
            return undefined;
        }

        const levelCode = match[1];
        const message = match[2];

        let level: ParsedLogLine["level"] = "info";
        if (levelCode === "E") {
            level = "error";
        } else if (levelCode === "F") {
            level = "fault";
        } else if (levelCode === "D" || levelCode === "Db") {
            level = "debug";
        }

        return { message, level };
    }
}
