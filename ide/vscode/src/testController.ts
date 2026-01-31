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
import { discoverTestsByBuilding } from "./syntax_test_discovery/sourceTestDiscovery";
import { Configuration } from "./configuration";
import { parseTestXml, createFailureMessages, findMethodResult, TestCaseResult } from "./testResults";

export class TestController {
    private context: vscode.ExtensionContext;
    private controller: vscode.TestController;
    private buildTaskProvider: BuildTaskProvider;
    private testItemsByLabel = new Map<string, vscode.TestItem>();
    private testTargetForSourceFile = new Map<string, string>();
    private lspTestDiscovery: LSPTestDiscovery;
    private outputChannel: vscode.OutputChannel;
    private configuration: Configuration;
    private testFileWatcher: vscode.FileSystemWatcher | undefined;
    private pendingDiscoveries = new Map<string, boolean>();
    private statusBarItem: vscode.StatusBarItem;
    private bazelWrapper: string = "bazel";

    constructor(context: vscode.ExtensionContext, buildTaskProvider: BuildTaskProvider, lspTestDiscovery: LSPTestDiscovery, outputChannel: vscode.OutputChannel, configuration: Configuration) {
        this.context = context;
        this.buildTaskProvider = buildTaskProvider;
        this.lspTestDiscovery = lspTestDiscovery;
        this.outputChannel = outputChannel;
        this.configuration = configuration;
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
        this.statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 0);
        context.subscriptions.push(this.statusBarItem);
        lspTestDiscovery.initialize();
    }

    async setTargets(targets: ProcessedTarget[], fromGraphThatAlreadyExisted: boolean, bazelWrapper: string): Promise<void> {
        this.log("setTargets");
        this.bazelWrapper = bazelWrapper;

        const testTargets = targets.filter((t) => t.type === "test" && t.canRun);
        const newTargetLabels = new Set(testTargets.map(t => t.label));

        // Preserve children of existing targets that still exist in the new target list
        // This prevents gutter icons from disappearing while waiting for LSP discovery.
        // NOTE! We can remove this once discovery via LSP is faster (along with the AST parsing fallback).
        const preservedChildren = new Map<string, vscode.TestItem[]>();
        for (const [label, existingItem] of this.testItemsByLabel) {
            if (newTargetLabels.has(label) && existingItem.children.size > 0) {
                const children: vscode.TestItem[] = [];
                existingItem.children.forEach(child => children.push(child));
                preservedChildren.set(label, children);
            }
        }

        this.controller.items.replace([]);
        this.testItemsByLabel.clear();
        this.testTargetForSourceFile.clear();

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

            // Restore preserved children for this target
            const preserved = preservedChildren.get(target.label);
            if (preserved) {
                for (const child of preserved) {
                    testItem.children.add(child);
                }
            }

            this.controller.items.add(testItem);
            this.testItemsByLabel.set(target.label, testItem);
        }

        if (!this.configuration.enableTestDiscovery) {
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
            this.discoverTestsInFile(uri);
        });
        this.testFileWatcher.onDidCreate((uri) => {
            this.discoverTestsInFile(uri);
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

        // Discover ALL unit tests via the LSP in the background
        this.discoverAllTests();
    }

    /**
     * Discovers tests in a specific file and updates the corresponding test target.
     */
    async discoverTestsInFile(uri: vscode.Uri): Promise<void> {
        const uriString = uri.toString();

        // Skip if discovery is already in progress for this file
        if (this.pendingDiscoveries.get(uriString)) {
            this.log(`Skipping discovery for ${uri.fsPath} - already in progress`);
            return;
        }

        if (!this.testTargetForSourceFile.has(uriString)) {
            return;
        }
        const testTarget = this.testTargetForSourceFile.get(uriString);
        if (!testTarget) {
            this.log(`No test target found for file: ${uri.fsPath}`);
            return;
        }

        const parentItem = this.testItemsByLabel.get(testTarget);
        if (!parentItem) {
            this.log(`No parent test item found for target: ${testTarget}`);
            return;
        }

        // Mark discovery as in progress
        this.pendingDiscoveries.set(uriString, true);

        try {
            await this.discoverTestsInFileImpl(uri, parentItem);
        } finally {
            // Always clear the pending flag
            this.pendingDiscoveries.delete(uriString);
        }
    }

    private async discoverTestsInFileImpl(uri: vscode.Uri, parentItem: vscode.TestItem): Promise<void> {
        this.log(`Discovering tests in file: ${uri.fsPath}`);

        // Log current state before removal
        const existingTestNames: string[] = [];
        parentItem.children.forEach(child => {
            if (child.uri?.toString() === uri.toString()) {
                existingTestNames.push(child.label);
                child.children.forEach(method => {
                    existingTestNames.push(`  ${method.label}`);
                });
            }
        });
        if (existingTestNames.length > 0) {
            this.log(`Existing tests in UI: ${existingTestNames.join(', ')}`);
        }

        // Use AST parsing for fast, reliable test discovery
        // This avoids LSP cache invalidation issues
        this.log(`Parsing tests using AST for ${uri.fsPath}`);
        const astTests = await discoverTestsByBuilding(this.outputChannel, uri);

        if (!astTests || astTests.length === 0) {
            this.log(`No tests found in file: ${uri.fsPath}`);
            this.removeUriFromParent(uri, parentItem);
            return;
        }

        // Log what AST returned
        const astTestNames: string[] = [];
        for (const astTest of astTests) {
            astTestNames.push(astTest.label);
            for (const child of astTest.children) {
                astTestNames.push(`  ${child.label}`);
            }
        }
        this.log(`AST returned ${astTests.length} test classes: ${astTestNames.join(', ')}`);

        // Remove existing children from this file and re-add
        this.log(`Removing all existing tests for ${uri.fsPath}`);
        this.removeUriFromParent(uri, parentItem);

        this.log(`Adding ${astTests.length} test classes from AST`);
        for (const astTest of astTests) {
            this.addLSPTestToParent(astTest, parentItem, 1);
        }
    }

    private removeUriFromParent(uri: vscode.Uri, parent: vscode.TestItem): void {
        const uriString = uri.toString();
        const toDelete: string[] = [];
        const toDeleteDetails: string[] = [];

        // Check if this item or any of its descendants has the matching URI
        const hasMatchingUri = (item: vscode.TestItem): boolean => {
            if (item.uri?.toString() === uriString) {
                return true;
            }
            // Recursively check children
            let found = false;
            item.children.forEach(child => {
                if (hasMatchingUri(child)) {
                    found = true;
                }
            });
            return found;
        };

        // Find top-level children that contain the URI (either directly or in descendants)
        parent.children.forEach(child => {
            if (hasMatchingUri(child)) {
                toDelete.push(child.id);

                // Log details about what we're removing
                const childDetails: string[] = [child.label];
                child.children.forEach(method => {
                    childDetails.push(`  ${method.label}`);
                });
                toDeleteDetails.push(childDetails.join(', '));
            }
        });

        if (toDelete.length > 0) {
            this.log(`Will delete ${toDelete.length} test classes: ${toDeleteDetails.join('; ')}`);
        } else {
            this.log(`No existing tests to delete for ${uri.fsPath}`);
        }

        // Delete those top-level children (their descendants will be automatically removed)
        for (const id of toDelete) {
            this.log(`Deleting test class with ID: ${id}`);
            parent.children.delete(id);
        }

        if (toDelete.length > 0) {
            this.log(`Successfully deleted ${toDelete.length} test classes`);
        }
    }

    /**
     * Discovers tests using a hybrid approach:
     * 1. Use LSP workspace/tests to find all test files
     * 2. Use AST to parse each file for actual test discovery
     * This avoids LSP cache invalidation issues while still benefiting from LSP's file discovery.
     */
    private async discoverAllTests(): Promise<void> {
        this.log("Starting workspace-wide test discovery");

        // Get all test files from LSP with status bar indicator
        this.statusBarItem.text = "$(sync~spin) Finding test files in targets (after indexing)...";
        this.statusBarItem.show();

        const lspTests = await this.lspTestDiscovery.getWorkspaceTests();

        if (!lspTests) {
            this.log("No tests found by the LSP, skipping adding children");
            this.statusBarItem.hide();
            return;
        }

        this.log(`LSP returned ${lspTests.length} top-level test items`);

        // Clear existing tests
        for (const parentTestItem of this.testItemsByLabel.values()) {
            parentTestItem.children.replace([]);
        }

        // Extract unique file URIs from LSP response
        const testFileUris = new Set<string>();
        const extractUrisFromLSPTest = (test: LSPTestItem) => {
            if (test.location?.uri) {
                testFileUris.add(test.location.uri);
            }
            for (const child of test.children) {
                extractUrisFromLSPTest(child);
            }
        };

        for (const lspTest of lspTests) {
            extractUrisFromLSPTest(lspTest);
        }

        this.log(`Found ${testFileUris.size} unique test files from LSP`);

        // Now use AST to parse each file with controlled concurrency
        const totalFiles = testFileUris.size;
        let processedFiles = 0;

        // Limit concurrent AST parsing to avoid overwhelming the system with subprocesses
        const concurrencyLimit = this.configuration.testDiscoveryConcurrency;
        const fileUriArray = Array.from(testFileUris);

        const processFile = async (uriString: string) => {
            try {
                const uri = vscode.Uri.parse(uriString);

                // Find the parent test item for this file
                const testTarget = this.testTargetForSourceFile.get(uriString);
                if (!testTarget) {
                    return;
                }

                const parentItem = this.testItemsByLabel.get(testTarget);
                if (!parentItem) {
                    return;
                }

                // Use AST to discover tests in this file
                this.log(`Parsing ${uri.fsPath} with AST`);
                const astTests = await discoverTestsByBuilding(this.outputChannel, uri);

                if (astTests && astTests.length > 0) {
                    for (const astTest of astTests) {
                        this.addLSPTestToParent(astTest, parentItem, 1);
                    }
                }
            } catch (error) {
                this.log(`Error discovering tests in ${uriString}: ${error}`);
            } finally {
                // Update progress (atomic increment)
                processedFiles++;
                this.statusBarItem.text = `$(sync~spin) Discovering tests (${processedFiles}/${totalFiles})`;
            }
        };

        // Process files in batches to limit concurrency
        for (let i = 0; i < fileUriArray.length; i += concurrencyLimit) {
            const batch = fileUriArray.slice(i, i + concurrencyLimit);
            await Promise.all(batch.map(processFile));
        }

        this.log("Workspace-wide test discovery complete");
        this.statusBarItem.hide();
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
        const run = this.controller.createTestRun(request);

        const testsToRun: vscode.TestItem[] = [];
        if (request.include) {
            testsToRun.push(...request.include);
        } else {
            this.controller.items.forEach((item) => testsToRun.push(item));
        }

        // Track results for notification
        let totalTests = 0;
        let passedTests = 0;
        let failedTests = 0;
        let erroredTests = 0;

        for (const testItem of testsToRun) {
            if (token.isCancellationRequested) {
                run.skipped(testItem);
                continue;
            }

            // Mark test and all children as started
            run.started(testItem);

            const childTests: vscode.TestItem[] = [];

            // Detect if this is a target (has classes) or a class (has methods)
            // If children have children, we're at target level; otherwise we're at class level
            const firstChild = testItem.children.size > 0 ? Array.from(testItem.children)[0][1] : undefined;
            const isTargetLevel = firstChild && firstChild.children.size > 0;

            if (isTargetLevel) {
                // Target level: children are classes, grandchildren are methods
                testItem.children.forEach(child => {
                    child.children.forEach(method => {
                        run.started(method);
                        childTests.push(method);
                    });
                });
            } else if (testItem.children.size > 0) {
                // Class level: children are methods
                testItem.children.forEach(child => {
                    run.started(child);
                    childTests.push(child);
                });
            }

            try {
                const { success, testResults, errorType } = await this.executeTest(testItem.id, token);
                const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;

                // Handle build/execution errors (not test failures)
                if (errorType === 'errored') {
                    const errorMsg = new vscode.TestMessage("Build or execution error");
                    run.errored(testItem, errorMsg);
                    childTests.forEach(child => run.errored(child, errorMsg));
                    erroredTests += (childTests.length > 0 ? childTests.length : 1);
                    totalTests += (childTests.length > 0 ? childTests.length : 1);
                }
                // Case 1: Test item is a leaf (individual test method)
                else if (childTests.length === 0 && testResults && testResults.length > 0 && workspaceRoot) {
                    // This is a single test method - apply results to it directly
                    const result = testResults[0]; // Should only be one result
                    totalTests++;
                    if (result.passed) {
                        run.passed(testItem, result.time * 1000);
                        passedTests++;
                    } else {
                        const messages = createFailureMessages(workspaceRoot, result, testItem);
                        run.failed(testItem, messages, result.time * 1000);
                        failedTests++;
                    }
                }
                // Case 2: Test item has children (target or class) - update children with detailed results
                else if (testResults && testResults.length > 0 && childTests.length > 0) {
                    const childResults = this.updateTestItemsWithResults(run, testItem, childTests, testResults);
                    totalTests += childResults.total;
                    passedTests += childResults.passed;
                    failedTests += childResults.failed;
                }
                // Case 3: Fallback to simple pass/fail
                else {
                    const count = childTests.length > 0 ? childTests.length : 1;
                    totalTests += count;
                    if (success) {
                        run.passed(testItem);
                        childTests.forEach(child => run.passed(child));
                        passedTests += count;
                    } else {
                        run.failed(testItem, new vscode.TestMessage("Test failed"));
                        childTests.forEach(child => run.failed(child, new vscode.TestMessage("Test failed")));
                        failedTests += count;
                    }
                }
            } catch (err) {
                const message = err instanceof Error ? err.message : String(err);
                run.errored(testItem, new vscode.TestMessage(message));
                childTests.forEach(child => run.errored(child, new vscode.TestMessage(message)));
                const count = childTests.length > 0 ? childTests.length : 1;
                erroredTests += count;
                totalTests += count;
            }
        }

        run.end();

        // Show notification with test results
        if (totalTests > 0) {
            if (erroredTests > 0) {
                vscode.window.showErrorMessage(
                    `Tests failed to build or run: ${erroredTests} errored, ${failedTests} failed, ${passedTests} passed`
                );
            } else if (failedTests > 0) {
                vscode.window.showWarningMessage(
                    `Tests completed: ${failedTests} failed, ${passedTests} passed`
                );
            } else {
                vscode.window.showInformationMessage(
                    `All ${passedTests} test${passedTests === 1 ? '' : 's'} passed`
                );
            }
        }
    }

    /**
     * Update test items with detailed results from test.xml
     */
    private updateTestItemsWithResults(
        run: vscode.TestRun,
        parentItem: vscode.TestItem,
        childTests: vscode.TestItem[],
        testResults: TestCaseResult[]
    ): { total: number; passed: number; failed: number } {
        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
        if (!workspaceRoot) {
            return { total: 0, passed: 0, failed: 0 };
        }

        let passed = 0;
        let failed = 0;

        // Update individual child test items
        for (const child of childTests) {
            // Extract class and method name from test ID
            // Format: "//target:Tests|FILTER|TestClass/testMethod"
            const idParts = child.id.split('|FILTER|');
            if (idParts.length < 2) {
                continue;
            }

            const filterPart = idParts[1]; // "TestClass/testMethod"
            const filterParts = filterPart.split('/');
            if (filterParts.length < 2) {
                continue;
            }

            const className = filterParts[0];
            const methodName = filterParts[1];

            // Find matching result
            const result = findMethodResult(testResults, className, methodName);
            if (result) {
                if (result.passed) {
                    run.passed(child, result.time * 1000);
                    passed++;
                } else {
                    const messages = createFailureMessages(workspaceRoot, result, child);
                    run.failed(child, messages, result.time * 1000);
                    failed++;
                }
            } else {
                // No result found - assume passed
                run.passed(child);
                passed++;
            }
        }

        // Update parent based on all test results
        // Check if ANY result failed (not just matched children)
        const anyResultFailed = testResults.some(r => !r.passed);
        if (anyResultFailed) {
            // Collect all failure messages from failed tests
            const allMessages: vscode.TestMessage[] = [];
            for (const result of testResults) {
                if (!result.passed) {
                    allMessages.push(...createFailureMessages(workspaceRoot, result, parentItem));
                }
            }
            run.failed(parentItem, allMessages.length > 0 ? allMessages : [new vscode.TestMessage("Test failed")]);
        } else {
            run.passed(parentItem);
        }

        return { total: passed + failed, passed, failed };
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
    ): Promise<{ success: boolean; testResults?: TestCaseResult[]; errorType?: 'failed' | 'errored' }> {
        const { target, filter } = this.parseTestId(testItemId);
        if (filter) {
            this.log(`Parsed filter ${filter} for test task ${target}`);
        }
        const baseTask = this.buildTaskProvider.getTask(getTestLaunchTaskLabel(target, true));
        if (!baseTask) {
            throw new Error(`Test task not found for target: ${target}`);
        }

        // Create a new task with the filter to avoid modifying the cached task
        let task = baseTask;
        if (filter) {
            const baseExecution = baseTask.execution as vscode.ShellExecution;
            if (!baseExecution.commandLine && !baseExecution.command) {
                throw new Error("Task execution has no command");
            }

            const newEnv = { ...baseExecution.options?.env, BAZEL_TEST_FILTER: filter };

            // ShellExecution can be created with either commandLine or command+args
            const newExecution = baseExecution.commandLine
                ? new vscode.ShellExecution(baseExecution.commandLine, { ...baseExecution.options, env: newEnv })
                : new vscode.ShellExecution(
                    baseExecution.command!,
                    baseExecution.args || [],
                    { ...baseExecution.options, env: newEnv }
                );

            task = new vscode.Task(
                baseTask.definition,
                baseTask.scope || vscode.TaskScope.Workspace,
                baseTask.name + " (Filter: " + filter + ")",
                baseTask.source,
                newExecution,
                baseTask.problemMatchers
            );
            task.group = baseTask.group;
            task.isBackground = baseTask.isBackground;
            task.presentationOptions = baseTask.presentationOptions;
        }

        // Record when we start the test so we can detect stale test.xml files
        const testStartTime = Date.now();

        return new Promise((resolve) => {
            const disposables: vscode.Disposable[] = [];
            const taskExecution = vscode.tasks.executeTask(task);

            disposables.push(
                vscode.tasks.onDidEndTaskProcess((e) => {
                    if (e.execution.task.name === task.name) {
                        disposables.forEach((d) => d.dispose());
                        const success = e.exitCode === 0;

                        // Parse test results from test.xml (only if modified after test start)
                        const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
                        let testResults: TestCaseResult[] | undefined;
                        if (workspaceRoot) {
                            testResults = parseTestXml(this.outputChannel, workspaceRoot, target, testStartTime, this.bazelWrapper);
                        }

                        // Determine error type based on results
                        // If non-zero exit code but no (fresh) test results, it's a build failure
                        let errorType: 'failed' | 'errored' | undefined;
                        if (!success) {
                            if (!testResults || testResults.length === 0) {
                                // Build failed - no tests ran (or stale results were ignored)
                                errorType = 'errored';
                            } else {
                                // Tests ran but some failed
                                errorType = 'failed';
                            }
                        }

                        resolve({ success, testResults, errorType });
                    }
                })
            );
            disposables.push(
                token.onCancellationRequested(() => {
                    taskExecution.then((exec) => exec.terminate());
                    disposables.forEach((d) => d.dispose());
                    resolve({ success: false, errorType: 'errored' });
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
        this.statusBarItem.dispose();
        this.controller.dispose();
    }
}
