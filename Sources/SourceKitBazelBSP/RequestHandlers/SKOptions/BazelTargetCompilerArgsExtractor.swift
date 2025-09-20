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

import struct os.OSAllocatedUnfairLock

private let logger = makeFileLevelBSPLogger()

enum BazelTargetCompilerArgsExtractorError: Error, LocalizedError {
    case invalidObjCUri(String)
    case invalidTarget(String)
    case sdkRootNotFound(String)
    case noCachedAquery

    var errorDescription: String? {
        switch self {
        case .invalidObjCUri(let uri): return "Unexpected non-Swift URI missing root URI prefix: \(uri)"
        case .invalidTarget(let target): return "Expected to receive a build_test target, but got: \(target)"
        case .sdkRootNotFound(let sdk): return "sdkRootPath not found for \(sdk). Is it installed?"
        case .noCachedAquery: return "runAqueryForArgsExtraction must be ran before calling compilerArgs."
        }
    }
}

/// Abstraction that handles running action queries and extracting the compiler args for a given target file.
final class BazelTargetCompilerArgsExtractor {

    private let commandRunner: CommandRunner
    private let aquerier: BazelTargetAquerier
    private let config: InitializedServerConfig

    private var argsCache = [String: [String]?]()
    // BazelTargetAquerier has a cache of its own,
    // but we replicate it here to avoid having to store data about how to perform the query.
    private var aqueryCache: AqueryResult? = nil

    init(
        commandRunner: CommandRunner = ShellCommandRunner(),
        aquerier: BazelTargetAquerier = BazelTargetAquerier(),
        config: InitializedServerConfig
    ) {
        self.commandRunner = commandRunner
        self.aquerier = aquerier
        self.config = config
    }

    func compilerArgs(
        forDoc textDocument: URI,
        inTarget bazelTarget: String,
        buildingUnder platformInfo: BazelTargetPlatformInfo,
        language: Language,
    ) throws -> [String]? {
        // Ignore Obj-C header requests, since these don't compile
        guard !textDocument.stringValue.hasSuffix(".h") else {
            return nil
        }

        let bazelTargetToBuild = platformInfo.buildTestLabel

        // For Swift, compilation is done at the target-level. But for ObjC, it's file-based instead.
        let cacheKey: String
        let contentToQuery: String
        if language == .swift {
            cacheKey = bazelTargetToBuild
            contentToQuery = bazelTargetToBuild
        } else {
            // Make the path relative, as this is what aquery will return
            let fullUri = textDocument.stringValue
            let prefixToCut = "file://" + config.rootUri + "/"
            guard fullUri.hasPrefix(prefixToCut) else {
                throw BazelTargetCompilerArgsExtractorError.invalidObjCUri(fullUri)
            }
            let parsedFile = String(fullUri.dropFirst(prefixToCut.count))
            cacheKey = bazelTargetToBuild + "|" + parsedFile
            contentToQuery = parsedFile
        }

        logger.info("Fetching compiler args for \(cacheKey)")

        if let cached = argsCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        guard let resultAquery = aqueryCache else {
            throw BazelTargetCompilerArgsExtractorError.noCachedAquery
        }

        // First, determine the SDK root based on the platform the target is built for.
        let platformSdk = platformInfo.platformSdkName
        guard let sdkRoot: String = config.sdkRootPaths[platformSdk] else {
            throw BazelTargetCompilerArgsExtractorError.sdkRootNotFound(platformSdk)
        }

        // Then, extract the compiler arguments for the target file from the resulting aquery.
        let processedArgs = CompilerArgumentsProcessor.extractAndProcessCompilerArgs(
            fromAquery: resultAquery,
            bazelTarget: bazelTarget,
            parentBazelTarget: platformInfo.topLevelParentLabel,
            parentRuleType: platformInfo.topLevelParentRuleType,
            contentToQuery: contentToQuery,
            language: language,
            sdkRoot: sdkRoot,
            platformSdk: platformSdk,
            initializedConfig: config
        )
        argsCache[cacheKey] = processedArgs
        return processedArgs
    }

    func runAqueryForArgsExtraction(
        withTargets targets: [String],
    ) {
        // We pass BundleTreeApp as a trick to gain access to the parent's configuration id.
        // We can then use this to locate the exact variant of the target we are looking for.
        do {
            aqueryCache = try aquerier.aquery(
                targets: targets,
                config: config,
                mnemonics: ["SwiftCompile", "ObjcCompile", "BundleTreeApp"],
                additionalFlags: [
                    "--noinclude_artifacts",
                    "--noinclude_aspects",
                    "--features=-compiler_param_file",  // Context: https://github.com/spotify/sourcekit-bazel-bsp/pull/60
                ]
            )
        } catch {
            logger.error("Error running aquery for args extraction: \(error)")
            aqueryCache = nil
        }
    }

    func clearCache() {
        argsCache = [:]
        aqueryCache = nil
        aquerier.clearCache()
    }
}
