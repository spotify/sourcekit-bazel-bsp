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
import { ProcessedTarget } from "./graphProcessor";
import { BuildTaskProvider, getTestLaunchTaskLabel } from "./buildTaskProvider";
import { LSPTestDiscovery, LSPTestItem } from "./lspTestDiscovery";

export class TestController {
    private context: vscode.ExtensionContext;
    private controller: vscode.TestController;
    private buildTaskProvider: BuildTaskProvider;
    private testItemsByLabel = new Map<string, vscode.TestItem>();
    private testTargetForSourceFile = new Map<string, string>();
    private lspTestDiscovery: LSPTestDiscovery;
    private outputChannel: vscode.OutputChannel;
    private enableTestDiscovery: boolean;
    private testFileWatcher: vscode.FileSystemWatcher | undefined;

    constructor(context: vscode.ExtensionContext, buildTaskProvider: BuildTaskProvider, lspTestDiscovery: LSPTestDiscovery, outputChannel: vscode.OutputChannel, enableTestDiscovery: boolean) {
        this.context = context;
        this.buildTaskProvider = buildTaskProvider;
        this.lspTestDiscovery = lspTestDiscovery;
        this.outputChannel = outputChannel;
        this.enableTestDiscovery = enableTestDiscovery;
        this.controller = vscode.tests.createTestController(
            "sourcekit-bazel-bsp-test-controller",
            "SourceKit Bazel BSP Tests"
        );
        this.controller.createRunProfile(
            "Run Tests",
            vscode.TestRunProfileKind.Run,
            (request, token) => this.runTests(request, token),
            true
        );
        lspTestDiscovery.initialize();
    }

    async setTargets(targets: ProcessedTarget[], fromGraphThatAlreadyExisted: boolean): Promise<void> {
        this.controller.items.replace([]);
        this.testItemsByLabel.clear();
        this.testTargetForSourceFile.clear();

        const testTargets = targets.filter((t) => t.type === "test");
        for (const target of testTargets) {
            if (target.testSources) {
                for (const testSource of target.testSources) {
                    this.testTargetForSourceFile.set(testSource, target.label);
                }
            }
        }

        for (const target of testTargets) {
            const testItem = this.controller.createTestItem(
                target.label,
                target.displayName,
                undefined
            );
            this.controller.items.add(testItem);
            this.testItemsByLabel.set(target.label, testItem);
        }

        if (!this.enableTestDiscovery) {
            this.log("Test discovery is disabled, skipping adding children");
            return;
        }

        // Watch for changes to the test sources provided so that we can provide test info on-demand.
        if (this.testFileWatcher) {
            this.testFileWatcher.dispose();
            this.testFileWatcher = undefined;
        }
        this.testFileWatcher = vscode.workspace.createFileSystemWatcher('**/*.{swift,m,mm}');
        this.testFileWatcher.onDidChange((uri) => {
            if (this.testTargetForSourceFile.has(uri.toString())) {
                this.discoverTestsInFile(uri);
            }
        });
        this.testFileWatcher.onDidCreate((uri) => {
            if (this.testTargetForSourceFile.has(uri.toString())) {
                this.discoverTestsInFile(uri);
            }
        });
        this.testFileWatcher.onDidDelete((uri) => {
            if (this.testTargetForSourceFile.has(uri.toString())) {
                const testTarget = this.testTargetForSourceFile.get(uri.toString());
                if (!testTarget) {
                    return;
                }
                const parentItem = this.testItemsByLabel.get(testTarget);
                if (!parentItem) {
                    return;
                }
                this.removeUriFromParent(uri, parentItem);
            }
        });
        this.context.subscriptions.push(this.testFileWatcher);

        // Fetching LSP info right at startup doesn't work. We need the graph to be updated first.
        if (fromGraphThatAlreadyExisted) {
            this.log("Skipping generating test info (waiting for an updated graph)");
            return;
        }

        // At the same time, discover ALL unit tests via the LSP in the background
        this.discoverAllTests();
    }

    /**
     * Discovers tests in a specific file and updates the corresponding test target.
     */
    private async discoverTestsInFile(uri: vscode.Uri): Promise<void> {
        const testTarget = this.testTargetForSourceFile.get(uri.toString());
        if (!testTarget) {
            this.log(`No test target found for file: ${uri.fsPath}`);
            return;
        }

        const parentItem = this.testItemsByLabel.get(testTarget);
        if (!parentItem) {
            this.log(`No parent test item found for target: ${testTarget}`);
            return;
        }

        this.log(`Discovering tests in file: ${uri.fsPath}`);
        const lspTests = await this.lspTestDiscovery.getDocumentTests(uri);
        if (!lspTests) {
            this.log(`No tests found in file: ${uri.fsPath}`);
            return;
        }

        this.log(`LSP returned ${lspTests.length} tests for file: ${uri.fsPath}`);

        // Remove existing children from this file and re-add
        this.removeUriFromParent(uri, parentItem);
        for (const lspTest of lspTests) {
            this.addLSPTestToParent(lspTest, parentItem, 1);
        }
    }

    private removeUriFromParent(uri: vscode.Uri, parent: vscode.TestItem): void {
        parent.children.forEach((child) => {
            if (child.uri?.toString() === uri.toString()) {
                parent.children.delete(child.id);
            }
        });
    }

    /**
     * Discovers tests from LSP and adds them as children to matching top-level targets.
     */
    private async discoverAllTests(): Promise<void> {
        const lspTests = await this.lspTestDiscovery.getWorkspaceTests();
        if (!lspTests) {
            this.log("No tests found by the LSP, skipping adding children");
            return;
        }

        this.log(`LSP returned ${lspTests.length} top-level test items`);

        for (const parentTestItem of this.testItemsByLabel.values()) {
            parentTestItem.children.replace([]);
        }

        for (const lspTest of lspTests) {
            const testTarget = this.testTargetForSourceFile.get(lspTest.location?.uri);
            if (!testTarget) {
                continue;
            }
            const parentItem = this.testItemsByLabel.get(testTarget);
            if (!parentItem) {
                continue;
            }
            this.addLSPTestToParent(lspTest, parentItem, 1);
        }
    }

    /**
     * Recursively adds an LSP test item and its children to a parent VS Code TestItem.
     */
    private addLSPTestToParent(lspTest: LSPTestItem, parent: vscode.TestItem, depth: number): void {
        const uri = lspTest.location?.uri ? vscode.Uri.parse(lspTest.location.uri) : undefined;
        const range = lspTest.location?.range
            ? new vscode.Range(
                  lspTest.location.range.start.line,
                  lspTest.location.range.start.character,
                  lspTest.location.range.end.line,
                  lspTest.location.range.end.character
              )
            : undefined;

        // Use the ID field to propagate info regarding what this is (target, class, method)
        let testId = parent.label;
        if (depth == 1) {
            testId += "|FILTER|" + lspTest.label;
        } else if (depth == 2) {
            testId = parent.id;
            let label = lspTest.label;
            // Swift tests come with the parenthesis for some reason
            if (label.endsWith("()")) {
                label = label.slice(0, -2);
            }
            testId += "/" + label;
        }

        const testItem = this.controller.createTestItem(
            testId,
            lspTest.label,
            uri
        );

        if (range) {
            testItem.range = range;
        }

        if (parent) {
            parent.children.add(testItem);
        } else {
            this.controller.items.add(testItem);
            this.testItemsByLabel.set(lspTest.label, testItem);
        }

        for (const child of lspTest.children) {
            this.addLSPTestToParent(child, testItem, depth + 1);
        }
    }

    private async runTests(
        request: vscode.TestRunRequest,
        token: vscode.CancellationToken
    ): Promise<void> {
        this.log(`Requested to run tests: ${JSON.stringify(request, null, 2)}`);
        const run = this.controller.createTestRun(request);

        const testsToRun: vscode.TestItem[] = [];
        if (request.include) {
            testsToRun.push(...request.include);
        } else {
            this.controller.items.forEach((item) => testsToRun.push(item));
        }

        for (const testItem of testsToRun) {
            if (token.isCancellationRequested) {
                run.skipped(testItem);
                continue;
            }
            run.started(testItem);
            try {
                const success = await this.executeTest(testItem.id, token);
                if (success) {
                    run.passed(testItem);
                } else {
                    run.failed(testItem, new vscode.TestMessage("Test failed"));
                }
            } catch (err) {
                const message = err instanceof Error ? err.message : String(err);
                run.errored(testItem, new vscode.TestMessage(message));
            }
        }

        run.end();
    }

    /**
     * Parses a test item ID into target and filter components.
     * Format: "//target:Tests|FILTER|TestClass/testMethod"
     */
    private parseTestId(testItemId: string): { target: string; filter: string | undefined } {
        const filterSeparator = "|FILTER|";
        const idx = testItemId.indexOf(filterSeparator);
        if (idx !== -1) {
            return {
                target: testItemId.substring(0, idx),
                filter: testItemId.substring(idx + filterSeparator.length),
            };
        }
        return { target: testItemId, filter: undefined };
    }

    private async executeTest(
        testItemId: string,
        token: vscode.CancellationToken
    ): Promise<boolean> {
        const { target, filter } = this.parseTestId(testItemId);
        if (filter) {
            this.log(`Parsed filter ${filter} for test task ${target}`);
        }
        const task = this.buildTaskProvider.getTask(getTestLaunchTaskLabel(target));
        if (!task) {
            throw new Error(`Test task not found for target: ${target}`);
        }

        if (filter) {
            const execution = task.execution as vscode.ShellExecution;
            if (execution.options?.env) {
                execution.options.env["BAZEL_TEST_FILTER"] = filter;
            }
            task.name = task.name + " (Filter: " + filter + ")";
        }

        return new Promise((resolve) => {
            const disposables: vscode.Disposable[] = [];
            const taskExecution = vscode.tasks.executeTask(task);

            disposables.push(
                vscode.tasks.onDidEndTaskProcess((e) => {
                    if (e.execution.task.name === task.name) {
                        disposables.forEach((d) => d.dispose());
                        resolve(e.exitCode === 0);
                    }
                })
            );
            disposables.push(
                token.onCancellationRequested(() => {
                    taskExecution.then((exec) => exec.terminate());
                    disposables.forEach((d) => d.dispose());
                    resolve(false);
                })
            );
        });
    }

    private log(message: string): void {
        this.outputChannel.appendLine(`[TestController] ${message}`);
    }

    dispose(): void {
        if (this.testFileWatcher) {
            this.testFileWatcher.dispose();
            this.testFileWatcher = undefined;
        }
        this.controller.dispose();
    }
}
