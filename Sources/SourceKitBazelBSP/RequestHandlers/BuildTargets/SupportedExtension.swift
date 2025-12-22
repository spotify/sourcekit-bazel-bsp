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

// Contains data about all the file types the BSP knows how to parse.
// See also: DependencyRuleType.swift, TopLevelRuleType.swift
enum SupportedExtension: String, CaseIterable {
    case c
    case cc
    case cpp
    case cxx
    case h
    case hpp
    case m
    case mm
    case swift

    var kind: SourceKitSourceItemKind {
        switch self {
        case .h, .hpp: return .header
        case .c, .cc, .cpp, .cxx: return .source
        case .m, .mm: return .source
        case .swift: return .source
        }
    }

    // Source: https://github.com/swiftlang/sourcekit-lsp/blob/7495f5532fdb17184d69518f46a207e596b26c64/Sources/LanguageServerProtocolExtensions/Language%2BInference.swift#L33
    var language: Language {
        switch self {
        case .c: return .c
        case .cpp, .cc, .cxx, .hpp: return .cpp
        case .m: return .objective_c
        case .mm, .h: return .objective_cpp
        case .swift: return .swift
        }
    }
}
