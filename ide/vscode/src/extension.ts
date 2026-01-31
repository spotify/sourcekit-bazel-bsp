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
import { processGraph } from "./graphProcessor";
import { generateTasks } from "./taskGenerator";
import { Configuration } from "./configuration";
import { BuildTaskProvider, buildTarget, launchTargetWithoutDebugging, launchTestTargetWithoutDebugging } from "./buildTaskProvider";
import { selectSimulator } from "./simulatorPicker";
import { DebugConfigurationProvider, launchTarget } from "./debugTaskProvider";
import { TargetsViewProvider } from "./targetsView";
import { BspLogsViewer } from "./bspLogsViewer";
import { TestController } from "./testController";
import { LSPTestDiscovery } from "./lspTestDiscovery";

export const outputChannel = vscode.window.createOutputChannel("SourceKit-Bazel-BSP (Extension)");

const originalGraphPath = ".bsp/skbsp_generated/graph.json"

let origFileWatcher: vscode.FileSystemWatcher | undefined;
// let processedFileWatcher: vscode.FileSystemWatcher | undefined;
let configuration: Configuration;
let targetsViewProvider: TargetsViewProvider;
let buildTaskProvider: BuildTaskProvider;
let debugConfigProvider: DebugConfigurationProvider;
let bspLogsViewer: BspLogsViewer | undefined;
let testController: TestController;

async function onGraphFileChanged(alreadyExisted: boolean = false) {
    if (alreadyExisted) {
        outputChannel.appendLine("Generating processed file from a previously generated graph");
    } else {
        outputChannel.appendLine("Graph file change detected");
    }
    const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const inputUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        originalGraphPath
    );
    const outputUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        configuration.processedGraphPath
    );
    const result = await processGraph(inputUri, configuration.appsToAlwaysInclude, alreadyExisted);
    const contents = Buffer.from(JSON.stringify(result, null, 2));
    await vscode.workspace.fs.writeFile(outputUri, contents);
    outputChannel?.appendLine("Processed graph file change detected");
    // const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const processedGraphUri = vscode.Uri.joinPath(
        workspaceFolder.uri,
        configuration.processedGraphPath
    );
    await generateTasks(processedGraphUri, targetsViewProvider, buildTaskProvider, debugConfigProvider, testController);
}

async function fileExists(uri: vscode.Uri): Promise<boolean> {
    try {
        await vscode.workspace.fs.stat(uri);
        return true;
    } catch {
        return false;
    }
}

export async function activate(context: vscode.ExtensionContext) {
    outputChannel?.appendLine("Extension activated");

    bspLogsViewer = new BspLogsViewer();
    bspLogsViewer?.start();

    configuration = new Configuration();
    context.subscriptions.push(configuration);

    const extensionPath = context.extensionUri.fsPath;

    buildTaskProvider = new BuildTaskProvider(configuration, extensionPath);
    context.subscriptions.push(
        vscode.tasks.registerTaskProvider(BuildTaskProvider.taskType, buildTaskProvider)
    );

    // Initialize LSP test discovery (uses Swift extension's sourcekit-lsp)
    const lspTestDiscovery = new LSPTestDiscovery(outputChannel);
    context.subscriptions.push(lspTestDiscovery);

    testController = new TestController(context, buildTaskProvider, lspTestDiscovery, outputChannel, configuration);
    context.subscriptions.push(testController);

    debugConfigProvider = new DebugConfigurationProvider(extensionPath);

    targetsViewProvider = new TargetsViewProvider(context.extensionUri, context.workspaceState);
    targetsViewProvider.onBuildTarget((target) => buildTarget(target, buildTaskProvider));
    targetsViewProvider.onLaunchTarget((target) => launchTarget(target, debugConfigProvider));
    targetsViewProvider.onLaunchTargetWithoutDebugging((target) => launchTargetWithoutDebugging(target, buildTaskProvider));
    // targetsViewProvider.onTestTarget((target) => launchTestTarget(target, debugConfigProvider));
    targetsViewProvider.onTestTargetWithoutDebugging((target) => launchTestTargetWithoutDebugging(target, buildTaskProvider));
    targetsViewProvider.onSelectSimulator(async () => {
        const selected = await selectSimulator();
        if (selected) {
            targetsViewProvider.updateSimulatorInfo(selected);
        }
    });
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(TargetsViewProvider.viewType, targetsViewProvider, {
            webviewOptions: { retainContextWhenHidden: true }
        })
    );

    const workspaceFolder = vscode.workspace.workspaceFolders![0];
    const originalGraphPattern = new vscode.RelativePattern(
        workspaceFolder,
        originalGraphPath
    );
    // const processedGraphPattern = new vscode.RelativePattern(
    //     workspaceFolder,
    //     configuration.processedGraphPath
    // );
    origFileWatcher = vscode.workspace.createFileSystemWatcher(originalGraphPattern);
    // processedFileWatcher = vscode.workspace.createFileSystemWatcher(processedGraphPattern);
    outputChannel?.appendLine("Configuring file watchers...");
    origFileWatcher.onDidCreate((_e) => onGraphFileChanged(false));
    origFileWatcher.onDidChange((_e) => onGraphFileChanged(false));
    // processedFileWatcher.onDidCreate(onProcessedGraphFileChanged);
    // processedFileWatcher.onDidChange(onProcessedGraphFileChanged);
    outputChannel?.appendLine("File watchers configured successfully");

    const originalGraphUri = vscode.Uri.joinPath(workspaceFolder.uri, originalGraphPath);
    if (await fileExists(originalGraphUri)) {
        await onGraphFileChanged(true);
    }

    // Discover tests when documents are opened
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument((doc) => {
            testController.discoverTestsInFile(doc.uri);
        }),
    );

    // Discover tests when documents are saved (more reliable than file watcher)
    context.subscriptions.push(
        vscode.workspace.onDidSaveTextDocument((doc) => {
            testController.discoverTestsInFile(doc.uri);
        }),
    );

    // Discover tests in already open documents
    vscode.workspace.textDocuments.forEach((doc) => {
        testController.discoverTestsInFile(doc.uri);
    });
}

export function deactivate() {
    outputChannel?.appendLine("Deactivating...");
    origFileWatcher?.dispose();
    // processedFileWatcher?.dispose();
    outputChannel?.dispose();
    bspLogsViewer?.dispose();
}
