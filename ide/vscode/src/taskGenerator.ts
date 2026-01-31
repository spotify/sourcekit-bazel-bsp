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
import { ProcessedGraph, ProcessedTarget } from "./graphProcessor";
import { TargetsViewProvider } from "./targetsView";
import { BuildTaskProvider } from "./buildTaskProvider";
import { DebugConfigurationProvider } from "./debugTaskProvider";
import { TestController } from "./testController";
import { outputChannel } from "./extension";

export async function generateTasks(
    inputUri: vscode.Uri,
    viewProvider: TargetsViewProvider,
    buildTaskProvider: BuildTaskProvider,
    debugConfigProvider: DebugConfigurationProvider,
    testController: TestController
): Promise<void> {
    const fileContents = await vscode.workspace.fs.readFile(inputUri);
    const graph: ProcessedGraph = JSON.parse(Buffer.from(fileContents).toString("utf-8"));
    const targets: ProcessedTarget[] = graph.targets;
    const fromGraphThatAlreadyExisted: boolean = graph.fromGraphThatAlreadyExisted;
    const bazelWrapper: string = graph.bazelWrapper ?? "bazel";
    outputChannel?.appendLine(`Updating targets view with ${targets.length} targets`);

    viewProvider.setTargets(targets);
    buildTaskProvider.setTargets(targets, bazelWrapper);
    debugConfigProvider.setTargets(targets);
    testController.setTargets(targets, fromGraphThatAlreadyExisted, bazelWrapper);

    // Notify VS Code of the updated task list
    await vscode.tasks.fetchTasks({ type: BuildTaskProvider.taskType });
}
