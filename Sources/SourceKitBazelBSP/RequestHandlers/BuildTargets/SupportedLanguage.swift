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

import BazelProtobufBindings
import BuildServerProtocol
import Foundation
import LanguageServerProtocol

private let logger = makeFileLevelBSPLogger()

// Represents information about languages that we know how to process in the BSP.
enum SupportedLanguage: String, Codable, Hashable, CaseIterable {
    case swift = "swift_library"
    case objective_c = "objc_library"
    case c = "cc_library"

    init?(fromLSPLanguage language: LanguageServerProtocol.Language) {
        switch language {
        case .swift: self = .swift
        case .objective_c, .objective_cpp: self = .objective_c
        case .c, .cpp: self = .c
        default: return nil
        }
    }

    static func languageAndKind(
        fromSrc src: URI,
        ruleKind: String
    ) -> (SupportedLanguage, SourceKitSourceItemKind)? {
        guard let pathExtension = src.fileURL?.pathExtension else {
            return nil
        }
        // Special case where two languages share the same header extension.
        if pathExtension == "h" {
            if ruleKind == SupportedLanguage.objective_c.ruleKind {
                return (SupportedLanguage.objective_c, .header)
            } else if ruleKind == SupportedLanguage.c.ruleKind {
                return (SupportedLanguage.c, .header)
            } else {
                return nil
            }
        }
        // Otherwise, just look for the language by the extension.
        for language in SupportedLanguage.allCases {
            if language.fileExtensions.contains(pathExtension) {
                return (language, .source)
            }
        }
        return nil
    }

    // func language(
    //     for srcString: String,
    //     srcKind: SourceKitSourceItemKind,
    //     ruleKind: String
    // ) throws -> SupportedLanguage {
    //     switch self {
    //     case .swift: return (.swift, .source)
    //     case .objective_c: return (.objective_c, .source)
    //     case .c: return (.c, .source)
    //     }
    // }

    var ruleKind: String {
        return rawValue
    }

    var compileMnemonic: String {
        switch self {
        case .swift: return "SwiftCompile"
        case .objective_c: return "ObjcCompile"
        case .c: return "CppCompile"
        }
    }

    var fileExtensions: Set<String> {
        switch self {
        case .swift: return ["swift"]
        case .objective_c: return ["h", "m", "mm"]
        case .c: return ["h", "c", "cpp"]
        }
    }

    var lspLanguage: LanguageServerProtocol.Language {
        switch self {
        case .swift: return .swift
        case .objective_c: return .objective_c
        case .c: return .c
        }
    }

    /*
                let kind: SourceKitSourceItemKind
            if srcString.hasSuffix("h") {
                kind = .header
            } else {
                kind = .source
            }
            let language: Language?
            if srcString.hasSuffix("swift") {
                language = .swift
            } else if srcString.hasSuffix("m") || kind == .header {
                language = .objective_c
            } else {
                language = nil
            }
        */

    /*
      func getParsingStrategy(for uri: URI, language: Language, targetUri: URI) throws -> ParsingStrategy {
        switch language {
        case .swift:
            return .swiftModule
        case .objective_c, .c, .objective_cpp:
            if uri.stringValue.hasSuffix(".h") {
                return .cHeader
            }
            // Make the path relative, as this is what aquery will return
            let fullUri = uri.stringValue
            let prefixToCut = "file://" + config.rootUri + "/"
            guard fullUri.hasPrefix(prefixToCut) else {
                throw BazelTargetCompilerArgsExtractorError.invalidCUri(fullUri)
            }
            let parsedFile = String(fullUri.dropFirst(prefixToCut.count))
            if language == .c {
                return .cImpl(parsedFile)
            } else if language == .objective_c || language == .objective_cpp {
                return .objcImpl(parsedFile)
            }
            throw BazelTargetCompilerArgsExtractorError.shouldNeverHappen("No language for C-type parsing")
        default:
            throw BazelTargetCompilerArgsExtractorError.unsupportedLanguage(
                language.rawValue,
                uri.stringValue,
                targetUri.stringValue
            )
        }
    }
    */

    /*
            // Handle remaining necessary adjustments for indexing.
        switch strategy {
        case .objcImpl, .cImpl:
            compilerArguments.append("-index-store-path")
            compilerArguments.append(config.indexStorePath)
            compilerArguments.append("-working-directory")
            compilerArguments.append(config.rootUri)
        case .swiftModule:
            // For Swift, swap the index store arg with the global cache.
            // Bazel handles this a bit differently internally, which is why
            // we need to do this.
            _editArg("-index-store-path", config.indexStorePath, &compilerArguments)
        case .cHeader:
            break
        }
        */

        /*
                    // For Swift, Bazel will print relative paths, but indexing needs absolute paths.
            if arg.hasSuffix(".swift"), !arg.hasPrefix("/") {
                let transformedArg = rootUri + "/" + arg
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }
            */

        /*
            private let supportedFileExtensions: Set<String> = [
        "swift",
        "h",
        "m",
        "mm",
        "c",
        "cpp",
    ]
    */
}
