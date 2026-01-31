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

import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as child_process from 'child_process';

export interface FailureInfo {
    message: string;
    file?: string;
    line?: number;
}

export interface TestCaseResult {
    className: string;
    methodName: string;
    passed: boolean;
    time: number;
    failures: FailureInfo[];
}

/**
 * Parse test.xml file from bazel-testlogs to extract test results.
 * Only returns results if the file was modified after testStartTime to avoid
 * using stale test.xml from previous runs when build fails.
 *
 * @param testStartTime - The time when the test was started (Date.now())
 * @param bazelWrapper - The bazel command to use.
 */
export function parseTestXml(
    outputChannel: vscode.OutputChannel,
    workspaceRoot: string,
    bazelTarget: string,
    testStartTime: number,
    bazelWrapper: string
): TestCaseResult[] | undefined {
    try {
        // Get the testlogs directory from bazel info
        let testlogsDir: string;
        try {
            const result = child_process.execSync(`${bazelWrapper} info bazel-testlogs`, {
                cwd: workspaceRoot,
                encoding: 'utf-8',
                stdio: ['pipe', 'pipe', 'pipe']
            });
            testlogsDir = result.trim();
        } catch (error) {
            // Fallback to bazel-testlogs symlink
            testlogsDir = path.join(workspaceRoot, 'bazel-testlogs');
        }

        // Convert bazel target to testlogs path
        // //foo/bar:baz -> testlogs/foo/bar/baz/test.xml
        const targetPath = bazelTarget
            .replace(/^\/\//, '')  // Remove leading //
            .replace(':', '/');     // Replace : with /

        const testXmlPath = path.join(testlogsDir, targetPath, 'test.xml');

        if (!fs.existsSync(testXmlPath)) {
            return undefined;
        }

        // Check file modification time to ensure it's from the current test run
        // Only use test.xml if it was modified AFTER we started the test
        const stats = fs.statSync(testXmlPath);
        if (stats.mtimeMs < testStartTime) {
            // Stale file from previous run - ignore it
            return undefined;
        }

        const xmlContent = fs.readFileSync(testXmlPath, 'utf-8');
        const results = parseJunitXml(outputChannel, xmlContent);

        return results;
    } catch (error) {
        // Silently return undefined on parse errors
        return undefined;
    }
}

/**
 * Parse JUnit XML format to extract test case results
 */
function parseJunitXml(
    _outputChannel: vscode.OutputChannel,
    xmlContent: string
): TestCaseResult[] {
    const results: TestCaseResult[] = [];
    // Match testcase elements - either self-closing or with content
    const testcaseRegex = /<testcase\s+([^>]*?)(?:\s*\/\s*>|>([\s\S]*?)<\/testcase>)/g;

    let match;
    while ((match = testcaseRegex.exec(xmlContent)) !== null) {
        const attrs = match[1] || '';
        const content = match[2] || '';  // Empty for self-closing tags

        // Use \s before name to avoid matching "classname" which contains "name"
        const nameMatch = attrs.match(/\sname="([^"]+)"/);
        const classMatch = attrs.match(/classname="([^"]+)"/);
        const timeMatch = attrs.match(/(?:time|duration)="([^"]+)"/);

        if (nameMatch) {
            const methodName = nameMatch[1];
            const className = classMatch ? classMatch[1] : '';
            const time = timeMatch ? parseFloat(timeMatch[1]) : 0;

            const failures: FailureInfo[] = [];
            const failureRegex = /<failure[^>]*message="([^"]*)"[^>]*>([\s\S]*?)<\/failure>/g;
            let failureMatch;
            while ((failureMatch = failureRegex.exec(content)) !== null) {
                const rawMessage = failureMatch[1] || 'Test failed';
                const failureContent = failureMatch[2]?.trim() || '';

                const failure = parseFailureInfo(rawMessage, failureContent);
                failures.push(failure);
            }

            // Handle failures without message attribute or error tags
            if (failures.length === 0 && (content.includes('<failure') || content.includes('<error'))) {
                failures.push({ message: 'Test failed' });
            }

            const passed = failures.length === 0;
            results.push({ className, methodName, passed, time, failures });
        }
    }

    return results;
}

/**
 * Parse failure information from XML to extract file path and line number
 */
function parseFailureInfo(rawMessage: string, content: string): FailureInfo {
    // Decode HTML entities
    let message = decodeHtmlEntities(rawMessage);
    let file: string | undefined;
    let line: number | undefined;

    // Try to get location from content first (simple format: path/to/file.swift:17 or file.m:19)
    // Match Swift (.swift) and Objective-C (.m, .mm, .h) files
    const contentLocation = content.match(/([^\s]+\.(?:swift|m|mm|h)):(\d+)/);
    if (contentLocation && !content.includes('???')) {
        file = contentLocation[1];
        line = parseInt(contentLocation[2], 10);
    } else {
        // Fallback: extract location from message (format: "at: file.swift:23")
        const messageLocation = message.match(/(?:at|at:)\s*([^\s]+\.(?:swift|m|mm|h)):(\d+)/i);
        if (messageLocation) {
            file = messageLocation[1];
            line = parseInt(messageLocation[2], 10);
        }
    }

    // Clean up the message for display
    message = cleanFailureMessage(message);

    return { message, file, line };
}

function decodeHtmlEntities(text: string): string {
    return text
        .replace(/&#10;/g, '\n')
        .replace(/&#13;/g, '\r')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
}

function cleanFailureMessage(message: string): string {
    // Remove "Test failure:\n" prefix if present
    message = message.replace(/^Test failure:\s*/i, '');

    // Remove "It occurred at: file.swift:123" suffix
    message = message.replace(/\s*It occurred at:.*$/i, '');

    // Trim whitespace and normalize newlines
    message = message.trim().replace(/\n+/g, ' ');

    // If empty after cleanup, use a default
    return message || 'Test failed';
}

/**
 * Create vscode.TestMessage objects with file locations from test results
 */
export function createFailureMessages(
    workspaceRoot: string,
    testResult: TestCaseResult,
    test: vscode.TestItem
): vscode.TestMessage[] {
    if (testResult.failures.length === 0) {
        const msg = new vscode.TestMessage('Test failed');
        if (test.uri && test.range) {
            msg.location = new vscode.Location(test.uri, test.range);
        }
        return [msg];
    }

    return testResult.failures.map(failure => {
        const message = new vscode.TestMessage(failure.message);

        if (failure.file && failure.line !== undefined) {
            let filePath = failure.file;
            if (!path.isAbsolute(filePath)) {
                filePath = path.join(workspaceRoot, filePath);
            }

            // Line numbers: XCTest is 1-based, VSCode is 0-based
            const zeroBasedLine = failure.line - 1;
            message.location = new vscode.Location(
                vscode.Uri.file(filePath),
                new vscode.Range(zeroBasedLine, 0, zeroBasedLine, 1000)
            );
        } else if (test.uri && test.range) {
            // Fallback to test item location
            message.location = new vscode.Location(test.uri, test.range);
        }

        return message;
    });
}

/**
 * Check if method names match, handling async suffixes
 */
function methodNamesMatch(xmlMethodName: string, methodName: string): boolean {
    // Direct match
    if (xmlMethodName === methodName) {
        return true;
    }

    // Match with or without "WithCompletionHandler:" suffix (common for async Swift tests)
    const suffix = 'WithCompletionHandler:';
    if (xmlMethodName === methodName + suffix || xmlMethodName + suffix === methodName) {
        return true;
    }

    return false;
}

/**
 * Find test result for a specific method
 */
export function findMethodResult(
    results: TestCaseResult[],
    className: string,
    methodName: string
): TestCaseResult | undefined {
    // Filter to matching class first
    const matchingResults = results.filter(r =>
        r.className.includes(className) ||
        className.includes(r.className.split('.').pop() || '')
    );

    // Try to find matching method using flexible matching
    return matchingResults.find(result => methodNamesMatch(result.methodName, methodName));
}
