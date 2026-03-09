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
 * Interfaces for Objective-C AST JSON output from `clang -Xclang -ast-dump=json`.
 */

/**
 * Location information in the Clang AST.
 */
export interface ObjCASTLocation {
    line?: number;
    col?: number;
    file?: string;
    expansionLoc?: {
        line?: number;
        col?: number;
        file?: string;
    };
}

/**
 * The top-level translation unit node.
 */
export interface ObjCASTTranslationUnit {
    kind: 'TranslationUnitDecl';
    inner?: ObjCASTNode[];
}

/**
 * An @implementation declaration.
 */
export interface ObjCASTImplementationDecl {
    kind: 'ObjCImplementationDecl';
    name: string;
    loc?: ObjCASTLocation;
    inner?: ObjCASTNode[];
}

/**
 * An Objective-C method declaration.
 */
export interface ObjCASTMethodDecl {
    kind: 'ObjCMethodDecl';
    name: string;
    loc?: ObjCASTLocation;
}

/**
 * Union type for AST nodes we care about.
 */
export type ObjCASTNode = ObjCASTImplementationDecl | ObjCASTMethodDecl | { kind: string };
