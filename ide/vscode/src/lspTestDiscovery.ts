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
import {
    LanguageClient,
    ParameterStructures,
    RequestType,
    RequestType0,
    TextDocumentIdentifier,
} from 'vscode-languageclient/node';

/**
 * Test style indicating the testing framework used.
 */
export type TestStyle = 'XCTest' | 'swift-testing' | 'test-target';

/**
 * Represents a single test item returned from SourceKit-LSP.
 */
export interface LSPTestItem {
    /** Unique identifier for the test case or test suite. */
    id: string;

    /** Display name describing the test. */
    label: string;

    /** Optional description that appears next to the label. */
    description?: string;

    /** String used for sorting. When undefined, label is used. */
    sortText?: string;

    /** Whether the test is disabled. */
    disabled: boolean;

    /** The type of test (testing framework). */
    style: TestStyle;

    /** The location of the test item in the source code. */
    location: {
        uri: string;
        range: {
            start: { line: number; character: number };
            end: { line: number; character: number };
        };
    };

    /** Child test items (for suites containing test cases or nested suites). */
    children: LSPTestItem[];

    /** Tags associated with this test item. */
    tags: { id: string }[];
}

/**
 * LSP request for workspace-wide test discovery.
 * This is a SourceKit-LSP extension, not part of the standard LSP.
 */
namespace WorkspaceTestsRequest {
    export const method = 'workspace/tests';
    export const type = new RequestType0<LSPTestItem[], never>(method);
}

/** Parameters for TextDocumentTestsRequest */
interface TextDocumentTestsParams {
    textDocument: TextDocumentIdentifier;
}

/**
 * LSP request for document-specific test discovery.
 * This is a SourceKit-LSP extension, not part of the standard LSP.
 */
namespace TextDocumentTestsRequest {
    export const method = 'textDocument/tests';
    export const type = new RequestType<TextDocumentTestsParams, LSPTestItem[], never>(method, ParameterStructures.byName);
}

/**
 * Interface for the LanguageClientManager from the Swift extension.
 */
interface LanguageClientManagerApi {
    useLanguageClient<T>(
        fn: (client: LanguageClient, token: vscode.CancellationToken) => Promise<T>
    ): Promise<T>;
}

/**
 * Interface for the LanguageClientToolchainCoordinator from the Swift extension.
 */
interface LanguageClientCoordinatorApi {
    get(folder: FolderContextApi): LanguageClientManagerApi;
}

/**
 * Interface for FolderContext from the Swift extension.
 */
interface FolderContextApi {
    folder: vscode.Uri;
    swiftVersion: { toString(): string };
}

/**
 * Interface matching the Swift extension's exposed API.
 */
interface SwiftExtensionApi {
    workspaceContext?: {
        folders: FolderContextApi[];
        currentFolder: FolderContextApi | null | undefined;
        languageClientManager: LanguageClientCoordinatorApi;
    };
}

/**
 * Provides test discovery using SourceKit-LSP via the Swift extension.
 * This reuses the existing sourcekit-lsp instance managed by the Swift extension,
 * avoiding the overhead of running a separate LSP server.
 */
export class LSPTestDiscovery implements vscode.Disposable {
    private swiftApi: SwiftExtensionApi | undefined;
    private outputChannel: vscode.OutputChannel;
    private initialized = false;

    constructor(outputChannel: vscode.OutputChannel) {
        this.outputChannel = outputChannel;
    }

    /**
     * Initialize the LSP test discovery by connecting to the Swift extension.
     * @returns true if initialization succeeded, false otherwise.
     */
    async initialize(): Promise<boolean> {
        if (this.initialized) {
            return this.swiftApi?.workspaceContext !== undefined;
        }

        this.log('Initializing LSP test discovery...');

        // Get the Swift extension
        const swiftExtension = vscode.extensions.getExtension<SwiftExtensionApi>(
            'swiftlang.swift-vscode'
        );

        if (!swiftExtension) {
            this.log('Swift extension (swiftlang.swift-vscode) not found');
            return false;
        }

        // Activate if not already active
        if (!swiftExtension.isActive) {
            this.log('Activating Swift extension...');
            try {
                await swiftExtension.activate();
            } catch (error) {
                this.log(`Failed to activate Swift extension: ${error}`);
                return false;
            }
        }

        this.swiftApi = swiftExtension.exports;
        this.initialized = true;

        if (!this.swiftApi?.workspaceContext) {
            this.log('Swift extension workspaceContext not available');
            return false;
        }

        this.log('LSP test discovery initialized successfully');
        return true;
    }

    /**
     * Check if LSP test discovery is available.
     */
    get isAvailable(): boolean {
        return this.swiftApi?.workspaceContext !== undefined;
    }

    /**
     * Get a language client manager from the Swift extension.
     * Uses the current folder if available, otherwise uses the first folder.
     */
    private getLanguageClientManager(): LanguageClientManagerApi | undefined {
        const workspaceContext = this.swiftApi?.workspaceContext;
        if (!workspaceContext) {
            return undefined;
        }

        // Try to get the current folder, or fall back to the first folder
        const folder = workspaceContext.currentFolder ?? workspaceContext.folders[0];
        if (!folder) {
            this.log('No folder context available');
            return undefined;
        }

        try {
            return workspaceContext.languageClientManager.get(folder);
        } catch (error) {
            this.log(`Failed to get language client manager: ${error}`);
            return undefined;
        }
    }

    /**
     * Discover all tests in the workspace using SourceKit-LSP.
     * @returns Array of test items, or undefined if discovery fails.
     */
    async getWorkspaceTests(): Promise<LSPTestItem[] | undefined> {
        if (!this.swiftApi?.workspaceContext) {
            this.log('Cannot get workspace tests: Swift extension not initialized');
            return undefined;
        }

        const clientManager = this.getLanguageClientManager();
        if (!clientManager) {
            this.log('Cannot get workspace tests: No language client manager available');
            return undefined;
        }

        try {
            return await clientManager.useLanguageClient(
                async (client, token) => {
                    // Check if the server supports this capability
                    if (!this.checkCapability(client, WorkspaceTestsRequest.method, 2)) {
                        throw new Error('workspace/tests not supported by sourcekit-lsp');
                    }
                    this.log('Requesting workspace tests from LSP...');
                    const tests = await client.sendRequest(WorkspaceTestsRequest.type, token);
                    this.log(`LSP returned ${tests.length} top-level test items`);
                    return tests;
                }
            );
        } catch (error) {
            this.log(`Failed to get workspace tests: ${error}`);
            return undefined;
        }
    }

    /**
     * Discover tests in a specific document using SourceKit-LSP.
     * @param uri The document URI to discover tests in.
     * @returns Array of test items, or undefined if discovery fails.
     */
    async getDocumentTests(uri: vscode.Uri): Promise<LSPTestItem[] | undefined> {
        if (!this.swiftApi?.workspaceContext) {
            this.log('Cannot get document tests: Swift extension not initialized');
            return undefined;
        }

        const clientManager = this.getLanguageClientManager();
        if (!clientManager) {
            this.log('Cannot get document tests: No language client manager available');
            return undefined;
        }

        try {
            return await clientManager.useLanguageClient(
                async (client, token) => {
                    // Check if the server supports this capability
                    if (!this.checkCapability(client, TextDocumentTestsRequest.method, 2)) {
                        throw new Error('textDocument/tests not supported by sourcekit-lsp');
                    }
                    this.log(`Requesting tests for document: ${uri.toString()}`);
                    const tests = await client.sendRequest<LSPTestItem[]>(
                        'textDocument/tests',
                        { textDocument: { uri: uri.toString() } },
                        token
                    );
                    this.log(`LSP returned ${tests.length} test items for document`);
                    return tests;
                }
            );
        } catch (error) {
            this.log(`Failed to get document tests: ${error}`);
            return undefined;
        }
    }

    /**
     * Check if the LSP server supports a specific experimental capability.
     */
    private checkCapability(
        client: LanguageClient,
        method: string,
        minVersion: number
    ): boolean {
        const experimental = client.initializeResult?.capabilities.experimental as
            | Record<string, { version?: number }>
            | undefined;

        if (!experimental) {
            this.log(`No experimental capabilities found`);
            return false;
        }

        const capability = experimental[method];
        const version = capability?.version ?? -1;
        const supported = version >= minVersion;

        if (!supported) {
            this.log(`Capability ${method} version ${version} < required ${minVersion}`);
        }

        return supported;
    }

    private log(message: string): void {
        this.outputChannel.appendLine(`[LSPTestDiscovery] ${message}`);
    }

    dispose(): void {
        // Nothing to dispose - we don't own the Swift extension's language client
    }
}
