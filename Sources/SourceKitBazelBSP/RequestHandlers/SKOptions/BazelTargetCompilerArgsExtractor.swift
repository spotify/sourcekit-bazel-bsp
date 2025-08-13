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

enum BazelTargetCompilerArgsExtractorError: Error, LocalizedError {
    case invalidObjCUri(String)
    case invalidTarget(String)

    var errorDescription: String? {
        switch self {
        case .invalidObjCUri(let uri): return "Unexpected non-Swift URI missing root URI prefix: \(uri)"
        case .invalidTarget(let target): return "Expected to receive a build_test target, but got: \(target)"
        }
    }
}

/// Abstraction that handles running action queries and extracting the compiler args for a given target file.
final class BazelTargetCompilerArgsExtractor {

    private let aquerier: BazelTargetAquerier
    private let config: InitializedServerConfig
    private var argsCache = [String: [String]?]()

    init(aquerier: BazelTargetAquerier = BazelTargetAquerier(), config: InitializedServerConfig) {
        self.aquerier = aquerier
        self.config = config
    }

    func compilerArgs(
        forDoc textDocument: URI,
        inTarget bazelTarget: String,
        underlyingLibrary: String,
        language: Language
    ) throws -> [String]? {
        // Ignore Obj-C header requests, since these don't compile
        guard !textDocument.stringValue.hasSuffix(".h") else {
            return nil
        }

        // For Swift, compilation is done at the target-level. But for ObjC, it's file-based instead.
        let cacheKey: String
        let contentToQuery: String
        if language == .swift {
            cacheKey = bazelTarget
            contentToQuery = bazelTarget
        } else {
            // Make the path relative, as this is what aquery will return
            let fullUri = textDocument.stringValue
            let prefixToCut = "file://" + config.rootUri + "/"
            guard fullUri.hasPrefix(prefixToCut) else {
                throw BazelTargetCompilerArgsExtractorError.invalidObjCUri(fullUri)
            }
            let parsedFile = String(fullUri.dropFirst(prefixToCut.count))
            cacheKey = bazelTarget + "|" + parsedFile
            contentToQuery = parsedFile
        }

        logger.info("Fetching compiler args for \(cacheKey)")

        if let cached = argsCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        // First, run an aquery against the build_test target in question,
        // filtering for the "real" underlying library.
        let resultAquery = try aquerier.aquery(
            target: bazelTarget,
            filteringFor: underlyingLibrary,
            config: config,
            mnemonics: ["SwiftCompile", "ObjcCompile"],
            additionalFlags: ["--noinclude_artifacts", "--noinclude_aspects"]
        )

        // Then, extract the compiler arguments for the target file from the resulting aquery.
        let processedArgs = CompilerArgumentsProcessor.extractAndProcessCompilerArgs(
            fromAquery: resultAquery,
            bazelTarget: underlyingLibrary,
            contentToQuery: contentToQuery,
            language: language,
            initializedConfig: config
        )
        argsCache[cacheKey] = processedArgs
        return processedArgs
    }

    func clearCache() {
        argsCache = [:]
        aquerier.clearCache()
    }
}
