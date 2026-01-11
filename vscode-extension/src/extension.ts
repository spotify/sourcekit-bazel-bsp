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
import { initLogger, log } from "./logger";
import { LogStreamManager } from "./logStream";
import { TargetsWebviewProvider } from "./targetsWebviewProvider";
import { DevicesWebviewProvider } from "./devicesProvider";
import { BuildTaskProvider } from "./buildTaskProvider";
import { BspGraphWatcher } from "./bspGraphWatcher";
import { registerCommands } from "./commands";
import { Target } from "./types";

// Extension state
let logStreamManager: LogStreamManager | undefined;
let bspGraphWatcher: BspGraphWatcher | undefined;
let currentTargets: Target[] = [];

export function activate(context: vscode.ExtensionContext) {
    const channels = initLogger();
    log("Extension activated");

    // Initialize webview providers
    const targetsWebviewProvider = new TargetsWebviewProvider(context.extensionUri, context);
    const devicesWebviewProvider = new DevicesWebviewProvider(context.extensionUri, context);

    // Initialize task provider
    const buildTaskProvider = new BuildTaskProvider();

    // Register webview providers
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(
            TargetsWebviewProvider.viewType,
            targetsWebviewProvider
        ),
        vscode.window.registerWebviewViewProvider(
            DevicesWebviewProvider.viewType,
            devicesWebviewProvider
        )
    );

    // Register task provider
    context.subscriptions.push(
        vscode.tasks.registerTaskProvider("sourcekit-bazel-bsp", buildTaskProvider)
    );

    // Initialize and start BSP graph watcher
    bspGraphWatcher = new BspGraphWatcher((update) => {
        currentTargets = update.targets;
        targetsWebviewProvider.setTargets(update.targets, update.graphFileExists);
        buildTaskProvider.setTargets(update.targets);
    });
    bspGraphWatcher.start();

    // Register commands
    registerCommands(context, {
        getTargets: () => currentTargets,
        devicesProvider: devicesWebviewProvider,
        scriptsPath: vscode.Uri.joinPath(context.extensionUri, "scripts"),
    });

    // Start server log streaming
    logStreamManager = new LogStreamManager(channels.server);
    logStreamManager.start();

    // Register cleanup
    context.subscriptions.push({
        dispose: () => {
            logStreamManager?.stop();
            bspGraphWatcher?.stop();
        },
    });
}

export function deactivate() {
    logStreamManager?.stop();
    logStreamManager = undefined;
    bspGraphWatcher?.stop();
    bspGraphWatcher = undefined;
}
