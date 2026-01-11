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
import { Target } from "./types";

const TASK_TYPE = "sourcekit-bazel-bsp";

interface BuildTaskDefinition extends vscode.TaskDefinition {
    target: string;
}

export class BuildTaskProvider implements vscode.TaskProvider {
    private targets: Target[] = [];

    setTargets(targets: Target[]): void {
        this.targets = targets;
    }

    provideTasks(): vscode.Task[] {
        return this.targets.map((target) => this.createBuildTask(target));
    }

    resolveTask(task: vscode.Task): vscode.Task | undefined {
        const definition = task.definition as BuildTaskDefinition;
        if (definition.target) {
            return this.createBuildTask({
                label: definition.target,
                uri: definition.target,
                kind: "library",
            });
        }
        return undefined;
    }

    private createBuildTask(target: Target): vscode.Task {
        const definition: BuildTaskDefinition = {
            type: TASK_TYPE,
            target: target.uri,
        };

        const task = new vscode.Task(
            definition,
            vscode.TaskScope.Workspace,
            `Build ${target.label}`,
            "SourceKit Bazel BSP",
            new vscode.ShellExecution("bazelisk", ["build", target.uri]),
            "$gcc"
        );

        task.group = vscode.TaskGroup.Build;
        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Always,
            panel: vscode.TaskPanelKind.Shared,
        };

        return task;
    }
}
