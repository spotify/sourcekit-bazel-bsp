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

/**
 * Interfaces for Swift AST JSON output from `swiftc -dump-parse -dump-ast-format json`.
 */

/**
 * A Swift source file node in the AST.
 */
export interface SwiftASTSourceFile {
    _kind: 'source_file';
    filename: string;
    items: SwiftASTItem[];
}

/**
 * A class declaration in the Swift AST.
 */
export interface SwiftASTClassDecl {
    _kind: 'class_decl';
    name: { base_name: { name: string } };
    range: { start: number; end: number };
    members: SwiftASTItem[];
    inherits?: Array<{ type: string }>;
}

/**
 * A function declaration in the Swift AST.
 */
export interface SwiftASTFuncDecl {
    _kind: 'func_decl';
    name: { base_name: { name: string } };
    range: { start: number; end: number };
}

/**
 * An extension declaration in the Swift AST.
 */
export interface SwiftASTExtensionDecl {
    _kind: 'extension_decl';
    extended_type: string;
    range: { start: number; end: number };
    members: SwiftASTItem[];
}

/**
 * Union type for all AST items we care about.
 */
export type SwiftASTItem = SwiftASTClassDecl | SwiftASTFuncDecl | SwiftASTExtensionDecl | { _kind: string };
