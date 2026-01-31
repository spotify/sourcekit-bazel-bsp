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
import * as child_process from 'child_process';
import { promisify } from 'util';
import { TestClassLocation } from './interfaces/TestClassLocation';
import { TestMethodLocation } from './interfaces/TestMethodLocation';
import {
    SwiftASTSourceFile,
    SwiftASTClassDecl,
    SwiftASTFuncDecl,
    SwiftASTExtensionDecl,
} from './interfaces/SwiftASTTypes';
import {
    ObjCASTTranslationUnit,
    ObjCASTImplementationDecl,
    ObjCASTMethodDecl,
} from './interfaces/ObjCASTTypes';
import { LSPTestItem } from '../lspTestDiscovery';

const execFile = promisify(child_process.execFile);

/**
 * Check if a file is a test file based on its name pattern.
 */
export function isTestFile(filePath: string): boolean {
    const fileName = path.basename(filePath);
    // Match *Test.swift/*Tests.swift (Swift) or *Test.m/*Tests.m (Objective-C)
    return fileName.endsWith('Test.swift') || fileName.endsWith('Tests.swift') ||
           fileName.endsWith('Test.m') || fileName.endsWith('Tests.m');
}

/**
 * Check if a file is a Swift file.
 */
export function isSwiftFile(filePath: string): boolean {
    return filePath.endsWith('.swift');
}

/**
 * Check if a file is an Objective-C file.
 */
export function isObjCFile(filePath: string): boolean {
    return filePath.endsWith('.m');
}

/**
 * Convert a byte offset in a string to a line number (0-based).
 */
function byteOffsetToLine(content: string, offset: number): number {
    // Ensure offset is within bounds
    const safeOffset = Math.min(offset, content.length);
    return content.substring(0, safeOffset).split('\n').length - 1;
}

/**
 * Log a message to the output channel.
 */
function log(outputChannel: vscode.OutputChannel, message: string): void {
    outputChannel.appendLine(`[SourceTestDiscovery] ${message}`);
}

/**
 * Parse a Swift file using the Swift compiler's AST output.
 * Uses `swiftc -dump-parse -dump-ast-format json` for accurate parsing.
 *
 * Returns classes with their test methods, including accurate line numbers.
 * Returns empty arrays if swiftc fails (no fallback).
 */
async function parseSwiftTestFile(
    outputChannel: vscode.OutputChannel,
    filePath: string,
    content: string,
): Promise<{ classes: TestClassLocation[]; methods: TestMethodLocation[] }> {
    try {
        log(outputChannel, `parseSwiftTestFile: Parsing ${filePath} with swiftc`);

        let stdout = '';
        let stderr = '';

        try {
            const result = await execFile('swiftc', [
                '-dump-parse',
                '-dump-ast-format', 'json',
                filePath,
            ], {
                maxBuffer: 10 * 1024 * 1024, // 10MB buffer for large files
                timeout: 5000, // 5 second timeout - swiftc should be fast for parse-only
            });
            stdout = result.stdout;
            stderr = result.stderr;
        } catch (execError: unknown) {
            // swiftc may exit with non-zero code due to parse errors but still produce valid JSON
            // The error object contains stdout/stderr from the failed command
            const err = execError as { stdout?: string; stderr?: string };
            if (err.stdout) {
                log(outputChannel, `parseSwiftTestFile: swiftc exited with error but produced output, trying to parse`);
                stdout = err.stdout;
                stderr = err.stderr || '';
            } else {
                throw execError;
            }
        }

        log(outputChannel, `parseSwiftTestFile: swiftc completed, stdout length: ${stdout.length}`);
        if (stderr) {
            log(outputChannel, `parseSwiftTestFile: swiftc stderr (truncated): ${stderr.substring(0, 200)}`);
        }

        // The JSON may be followed by error messages, try to find the JSON part
        // JSON starts with { and we need to find the matching closing brace
        let jsonEnd = stdout.lastIndexOf('}');
        if (jsonEnd === -1) {
            log(outputChannel, `parseSwiftTestFile: No JSON closing brace found in output, returning empty`);
            return { classes: [], methods: [] };
        }
        const jsonStr = stdout.substring(0, jsonEnd + 1);

        const ast = JSON.parse(jsonStr) as SwiftASTSourceFile;
        log(outputChannel, `parseSwiftTestFile: Parsed AST, items count: ${ast.items?.length ?? 0}`);

        const classes: TestClassLocation[] = [];
        const methods: TestMethodLocation[] = [];

        // Process top-level items looking for class declarations and extensions
        // Only treat classes ending with "Test" or "Tests" as test classes
        if (!ast.items) {
            log(outputChannel, `parseSwiftTestFile: AST has no items array`);
            return { classes: [], methods: [] };
        }

        // Helper to extract test methods from a members array
        const extractTestMethods = (members: typeof ast.items, className: string) => {
            for (const member of members) {
                if (member._kind !== 'func_decl') {
                    continue;
                }

                const funcDecl = member as SwiftASTFuncDecl;
                const methodName = funcDecl.name?.base_name?.name;
                if (!methodName || !methodName.startsWith('test')) {
                    continue;
                }

                const methodLine = byteOffsetToLine(content, funcDecl.range.start);
                log(outputChannel, `parseSwiftTestFile: Found test method "${methodName}" at line ${methodLine}`);

                methods.push({
                    methodName,
                    className,
                    line: methodLine,
                });
            }
        };

        for (const item of ast.items) {
            if (item._kind === 'class_decl') {
                const classDecl = item as SwiftASTClassDecl;
                const className = classDecl.name?.base_name?.name;
                if (!className) {
                    continue;
                }

                // Only include classes whose names end with "Test" or "Tests"
                if (!className.endsWith('Test') && !className.endsWith('Tests')) {
                    log(outputChannel, `parseSwiftTestFile: Skipping class "${className}" - name doesn't end with Test/Tests`);
                    continue;
                }

                // Convert byte offset to line number
                const classLine = byteOffsetToLine(content, classDecl.range.start);

                log(outputChannel, `parseSwiftTestFile: Found test class "${className}" at line ${classLine}`);
                classes.push({
                    className,
                    line: classLine,
                });

                // Look for test methods in this class
                if (classDecl.members) {
                    extractTestMethods(classDecl.members, className);
                }
            } else if (item._kind === 'extension_decl') {
                const extDecl = item as SwiftASTExtensionDecl;
                const extendedType = extDecl.extended_type;
                if (!extendedType) {
                    continue;
                }

                // Only process extensions of types that look like test classes
                if (!extendedType.endsWith('Test') && !extendedType.endsWith('Tests')) {
                    log(outputChannel, `parseSwiftTestFile: Skipping extension of "${extendedType}" - name doesn't end with Test/Tests`);
                    continue;
                }

                log(outputChannel, `parseSwiftTestFile: Found extension of test class "${extendedType}"`);

                // Look for test methods in this extension
                if (extDecl.members) {
                    extractTestMethods(extDecl.members, extendedType);
                }
            }
        }

        log(outputChannel, `parseSwiftTestFile: Found ${classes.length} classes and ${methods.length} methods via AST`);
        return { classes, methods };

    } catch (error) {
        // swiftc not available or failed - return empty (no fallback)
        log(outputChannel, `parseSwiftTestFile: swiftc failed: ${error}`);
        return { classes: [], methods: [] };
    }
}

/**
 * Get the iOS Simulator SDK path for Objective-C compilation.
 * Uses iOS SDK because it includes XCTest framework.
 */
async function getSDKPath(outputChannel: vscode.OutputChannel): Promise<string | null> {
    try {
        const { stdout } = await execFile('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path'], {
            timeout: 5000,
        });
        return stdout.trim();
    } catch (error) {
        log(outputChannel, `getSDKPath: Failed to get SDK path: ${error}`);
        return null;
    }
}

/**
 * Parse an Objective-C file using Clang's AST output.
 * Uses `clang -Xclang -ast-dump=json -fsyntax-only` for accurate parsing.
 *
 * Returns classes with their test methods, including accurate line numbers.
 * Returns empty arrays if clang fails (no fallback).
 */
async function parseObjCTestFile(
    outputChannel: vscode.OutputChannel,
    filePath: string,
    _content: string,
): Promise<{ classes: TestClassLocation[]; methods: TestMethodLocation[] }> {
    try {
        log(outputChannel, `parseObjCTestFile: Parsing ${filePath} with clang`);

        const sdkPath = await getSDKPath(outputChannel);
        if (!sdkPath) {
            log(outputChannel, `parseObjCTestFile: Could not get SDK path, returning empty`);
            return { classes: [], methods: [] };
        }

        let stdout = '';
        let stderr = '';

        try {
            const result = await execFile('clang', [
                '-Xclang', '-ast-dump=json',
                '-fsyntax-only',
                '-fmodules',
                '-isysroot', sdkPath,
                '-target', 'arm64-apple-ios16.0-simulator',
                filePath,
            ], {
                maxBuffer: 50 * 1024 * 1024, // 50MB buffer - clang AST includes all headers
                timeout: 30000, // 30 second timeout - clang can be slower due to module loading
            });
            stdout = result.stdout;
            stderr = result.stderr;
        } catch (execError: unknown) {
            // clang may exit with non-zero code due to errors but still produce valid JSON
            const err = execError as { stdout?: string; stderr?: string };
            if (err.stdout) {
                log(outputChannel, `parseObjCTestFile: clang exited with error but produced output, trying to parse`);
                stdout = err.stdout;
                stderr = err.stderr || '';
            } else {
                throw execError;
            }
        }

        log(outputChannel, `parseObjCTestFile: clang completed, stdout length: ${stdout.length}`);
        if (stderr) {
            log(outputChannel, `parseObjCTestFile: clang stderr (truncated): ${stderr.substring(0, 200)}`);
        }

        // Find the JSON - error messages may appear before it, so find the first {
        const jsonStart = stdout.indexOf('{');
        const jsonEnd = stdout.lastIndexOf('}');
        if (jsonStart === -1 || jsonEnd === -1 || jsonEnd <= jsonStart) {
            log(outputChannel, `parseObjCTestFile: No valid JSON found in output (start=${jsonStart}, end=${jsonEnd}), returning empty`);
            return { classes: [], methods: [] };
        }
        const jsonStr = stdout.substring(jsonStart, jsonEnd + 1);
        log(outputChannel, `parseObjCTestFile: Extracted JSON from positions ${jsonStart} to ${jsonEnd}`);

        const ast = JSON.parse(jsonStr) as ObjCASTTranslationUnit;
        log(outputChannel, `parseObjCTestFile: Parsed AST, inner count: ${ast.inner?.length ?? 0}`);

        const classes: TestClassLocation[] = [];
        const methods: TestMethodLocation[] = [];

        if (!ast.inner) {
            log(outputChannel, `parseObjCTestFile: AST has no inner array`);
            return { classes: [], methods: [] };
        }

        // Process top-level items looking for @implementation declarations
        for (const item of ast.inner) {
            if (item.kind !== 'ObjCImplementationDecl') {
                continue;
            }

            const implDecl = item as ObjCASTImplementationDecl;
            const className = implDecl.name;
            if (!className) {
                continue;
            }

            // Only include classes whose names end with "Test" or "Tests"
            if (!className.endsWith('Test') && !className.endsWith('Tests')) {
                log(outputChannel, `parseObjCTestFile: Skipping class "${className}" - name doesn't end with Test/Tests`);
                continue;
            }

            // Get line number from loc
            const classLine = implDecl.loc?.line ?? implDecl.loc?.expansionLoc?.line ?? 0;
            // Clang uses 1-based line numbers, convert to 0-based
            const classLineZeroBased = classLine > 0 ? classLine - 1 : 0;

            log(outputChannel, `parseObjCTestFile: Found test class "${className}" at line ${classLineZeroBased}`);
            classes.push({
                className,
                line: classLineZeroBased,
            });

            // Look for test methods in this class
            if (implDecl.inner) {
                for (const member of implDecl.inner) {
                    if (member.kind !== 'ObjCMethodDecl') {
                        continue;
                    }

                    const methodDecl = member as ObjCASTMethodDecl;
                    const methodName = methodDecl.name;
                    if (!methodName || !methodName.startsWith('test')) {
                        continue;
                    }

                    const methodLine = methodDecl.loc?.line ?? methodDecl.loc?.expansionLoc?.line ?? 0;
                    const methodLineZeroBased = methodLine > 0 ? methodLine - 1 : 0;

                    log(outputChannel, `parseObjCTestFile: Found test method "${methodName}" at line ${methodLineZeroBased}`);
                    methods.push({
                        methodName,
                        className,
                        line: methodLineZeroBased,
                    });
                }
            }
        }

        log(outputChannel, `parseObjCTestFile: Found ${classes.length} classes and ${methods.length} methods via AST`);
        return { classes, methods };

    } catch (error) {
        // clang not available or failed - return empty (no fallback)
        log(outputChannel, `parseObjCTestFile: clang failed: ${error}`);
        return { classes: [], methods: [] };
    }
}

/**
 * Parse a test file (Swift or Objective-C) using the appropriate compiler.
 */
async function parseTestFile(
    outputChannel: vscode.OutputChannel,
    filePath: string,
    content: string,
): Promise<{ classes: TestClassLocation[]; methods: TestMethodLocation[] }> {
    if (isObjCFile(filePath)) {
        return parseObjCTestFile(outputChannel, filePath, content);
    } else {
        return parseSwiftTestFile(outputChannel, filePath, content);
    }
}

/**
 * Async version of findTestClasses that uses AST parsing.
 * Supports both Swift (via swiftc) and Objective-C (via clang).
 * Returns empty array if parsing fails (no fallback).
 */
export async function findTestClassesAsync(
    outputChannel: vscode.OutputChannel,
    document: vscode.TextDocument,
): Promise<TestClassLocation[]> {
    const filePath = document.uri.fsPath;
    const content = document.getText();

    const { classes } = await parseTestFile(outputChannel, filePath, content);
    log(outputChannel, `findTestClassesAsync: Found ${classes.length} classes`);
    return classes;
}

/**
 * Async version of findTestMethods that uses AST parsing.
 * Supports both Swift (via swiftc) and Objective-C (via clang).
 * Returns empty array if parsing fails (no fallback).
 *
 * Note: The testClasses parameter is accepted for API compatibility but the
 * method discovery uses the AST which already associates methods with classes.
 */
export async function findTestMethodsAsync(
    outputChannel: vscode.OutputChannel,
    document: vscode.TextDocument,
    _testClasses: TestClassLocation[],
): Promise<TestMethodLocation[]> {
    const filePath = document.uri.fsPath;
    const content = document.getText();

    const { methods } = await parseTestFile(outputChannel, filePath, content);
    log(outputChannel, `findTestMethodsAsync: Found ${methods.length} methods`);
    return methods;
}

/**
 * Discovers tests in a file using raw source parsing (swiftc/clang AST).
 * Returns results in LSPTestItem format for compatibility.
 * We might be able to remove this when https://github.com/swiftlang/sourcekit-lsp/issues/2455 is fixed
 */
export async function discoverTestsByBuilding(outputChannel: vscode.OutputChannel, uri: vscode.Uri): Promise < LSPTestItem[] > {
    const document = await vscode.workspace.openTextDocument(uri);
    const classes = await findTestClassesAsync(outputChannel, document);
    const methods = await findTestMethodsAsync(outputChannel, document, classes);

    // Convert to LSPTestItem format - group methods by class
    const classMap = new Map<string, LSPTestItem>();

    for(const cls of classes) {
        classMap.set(cls.className, {
            id: cls.className,
            label: cls.className,
            disabled: false,
            style: 'XCTest',
            location: {
                uri: uri.toString(),
                range: {
                    start: { line: cls.line, character: 0 },
                    end: { line: cls.line, character: 0 },
                },
            },
            children: [],
            tags: [],
        });
    }

    for(const method of methods) {
        const classItem = classMap.get(method.className);
        if (classItem) {
            classItem.children.push({
                id: `${method.className}/${method.methodName}`,
                label: method.methodName,
                disabled: false,
                style: 'XCTest',
                location: {
                    uri: uri.toString(),
                    range: {
                        start: { line: method.line, character: 0 },
                        end: { line: method.line, character: 0 },
                    },
                },
                children: [],
                tags: [],
            });
        }
    }

    return Array.from(classMap.values());
}
