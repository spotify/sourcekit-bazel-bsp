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

import BuildServerProtocol
import Foundation
import LanguageServerProtocol

private let logger = makeFileLevelBSPLogger()

enum SupportedLanguages {
    static let headerExtensions: Set<String> = ["h", "hpp"]
    static let sourceExtensions: Set<String> = ["c", "cpp", "cc", "cxx", "m", "mm", "swift"]
    static let compileMnemonics: [String] = ["SwiftCompile", "ObjcCompile"] // CppCompile
    static let ruleKinds: [String: Language] = [
        "swift_library": .swift,
        "objc_library": .objective_c
        // "cc_library": .cpp,
    ]
}
