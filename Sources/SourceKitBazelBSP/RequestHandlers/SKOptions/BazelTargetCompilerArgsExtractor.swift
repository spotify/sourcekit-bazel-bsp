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

import struct os.OSAllocatedUnfairLock

private let logger = makeFileLevelBSPLogger()

enum BazelTargetCompilerArgsExtractorError: Error, LocalizedError {
    case invalidCUri(String)
    case invalidTarget(String)
    case sdkRootNotFound(String)
    case targetNotFound(String)
    case actionNotFound(String, UInt32)
    case multipleTargetActions(String, UInt32)
    case unsupportedLanguage(String, String, String)
    case shouldNeverHappen(String)
    case relevantTargetActionsNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidCUri(let uri): return "Unexpected C-type URI missing root URI prefix: \(uri)"
        case .invalidTarget(let target): return "Expected to receive a build_test target, but got: \(target)"
        case .sdkRootNotFound(let sdk): return "sdkRootPath not found for \(sdk). Is it installed?"
        case .targetNotFound(let target): return "Target \(target) not found in the aquery output."
        case .actionNotFound(let target, let id):
            return "Action \(id) for target \(target) not found in the aquery output."
        case .relevantTargetActionsNotFound(let target):
            return "No relevant target actions found for \(target). This is unexpected."
        case .multipleTargetActions(let target, let id):
            return "Multiple relevant target actions found for target \(target) with id \(id). This is unexpected."
        case .unsupportedLanguage(let language, let file, let target):
            return
                "Was requested to extract compiler args for an unsupported language: \(language) (file: \(file), target: \(target))"
        case .shouldNeverHappen(let message):
            return "Triggered a code block that should have never happened! \(message)"
        }
    }
}

/// Abstraction that handles processing and answering compiler args requests for SourceKit-LSP.
final class BazelTargetCompilerArgsExtractor {
    enum ParsingStrategy: CustomStringConvertible {
        case swiftModule
        case objcImpl(String)
        case cImpl(String)
        case cHeader

        var description: String {
            switch self {
            case .swiftModule: return "swiftModule"
            case .objcImpl(let uri): return "objcImpl(\(uri))"
            case .cImpl(let uri): return "cImpl(\(uri))"
            case .cHeader: return "cHeader"
            }
        }
    }

    private let config: InitializedServerConfig
    private var argsCache = [String: [String]]()

    init(config: InitializedServerConfig) {
        self.config = config
    }

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

    func extractCompilerArgs(
        fromAquery aquery: AqueryResult,
        forTarget platformInfo: BazelTargetPlatformInfo,
        withStrategy strategy: ParsingStrategy,
    ) throws -> [String] {
        // Ignore Obj-C header requests as these don't compile.
        if case .cHeader = strategy {
            return []
        }

        logger.info(
            "Fetching SKOptions for \(platformInfo.label), strategy: \(strategy)",
        )

        let cacheKey = try getCacheKey(
            forTarget: platformInfo.label,
            fromAquery: aquery,
            strategy: strategy
        )

        logger.info("Fetching compiler args for \(cacheKey, privacy: .public)")
        if let cached = argsCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        // First, determine the SDK root based on the platform the target is built for.
        let platformSdk = platformInfo.platformSdkName
        guard let sdkRoot: String = config.sdkRootPaths[platformSdk] else {
            throw BazelTargetCompilerArgsExtractorError.sdkRootNotFound(platformSdk)
        }

        // Then, find the target compilation step that matches the parent data.
        let targetAction = try getTargetAction(
            forTarget: platformInfo,
            fromAquery: aquery,
            strategy: strategy
        )

        // Then, extract the compiler arguments for the target file from the resulting aquery.
        let processedArgs = _processCompilerArguments(
            rawArguments: targetAction.arguments,
            sdkRoot: sdkRoot,
            strategy: strategy,
            originalConfigName: platformInfo.topLevelParentConfig.configurationName,
            effectiveConfigName: platformInfo.topLevelParentConfig.effectiveConfigurationName
        )

        logger.info("Finished processing compiler arguments")
        logger.logFullObjectInMultipleLogMessages(
            level: .debug,
            header: "Parsed compiler arguments",
            processedArgs.joined(separator: "\n"),
        )

        argsCache[cacheKey] = processedArgs
        return processedArgs
    }

    private func getCacheKey(
        forTarget target: String,
        fromAquery aquery: AqueryResult,
        strategy: ParsingStrategy
    ) throws -> String {
        let queryHash = String(aquery.hashValue)
        // For Swift, compilation is done at the target-level. But for ObjC, it's file-based instead.
        switch strategy {
        case .swiftModule, .cHeader:
            return target + "|" + queryHash
        case .objcImpl(let uri), .cImpl(let uri):
            return target + "|" + uri + "|" + queryHash
        }
    }

    private func getTargetAction(
        forTarget platformInfo: BazelTargetPlatformInfo,
        fromAquery aquery: AqueryResult,
        strategy: ParsingStrategy
    ) throws -> Analysis_Action {
        let bazelTarget = platformInfo.label
        guard let target = aquery.targets[bazelTarget] else {
            throw BazelTargetCompilerArgsExtractorError.targetNotFound(bazelTarget)
        }
        guard let actions = aquery.actions[target.id] else {
            throw BazelTargetCompilerArgsExtractorError.actionNotFound(bazelTarget, target.id)
        }
        // `actions` will contain all different configurations for the target we're processing.
        // We need to now locate the one that matches the configuration from the parent action
        // we're using as a reference.
        var candidateActions = actions.filter {
            // FIXME: We need to search for the configuration _name_ because Bazel for some reason
            // creates multiple config ids for build_test rules and I'm not sure why.
            // This would be much faster if we could search by id directly.
            guard let config = aquery.configurations[$0.configurationID] else {
                return false
            }
            return config.mnemonic == platformInfo.topLevelParentConfig.configurationName
        }
        let contentBeingQueried: String
        switch strategy {
        case .swiftModule, .cHeader:
            contentBeingQueried = bazelTarget
        case .objcImpl(let uri), .cImpl(let uri):
            // For C, we need to additionally filter for the action containing the specific file we're looking at.
            contentBeingQueried = uri + " (\(bazelTarget))"
            candidateActions = candidateActions.filter {
                let args = $0.arguments
                for i in (0..<args.count).reversed() {
                    if args[i] == "-c" && args[i + 1] == uri {
                        return true
                    }
                }
                return false
            }
        }
        guard candidateActions.count > 0 else {
            throw BazelTargetCompilerArgsExtractorError.relevantTargetActionsNotFound(contentBeingQueried)
        }
        guard candidateActions.count == 1 else {
            throw BazelTargetCompilerArgsExtractorError.multipleTargetActions(contentBeingQueried, target.id)
        }
        return candidateActions[0]
    }

    func clearCache() {
        argsCache = [:]
    }
}

extension BazelTargetCompilerArgsExtractor {
    /// Processes compiler arguments for the LSP by removing unnecessary arguments and replacing placeholders.
    private func _processCompilerArguments(
        rawArguments: [String],
        sdkRoot: String,
        strategy: ParsingStrategy,
        originalConfigName: String,
        effectiveConfigName: String
    ) -> [String] {
        let devDir = config.devDir
        let rootUri = config.rootUri
        let outputPath = config.outputPath
        let outputBase = config.outputBase

        var compilerArguments: [String] = []

        // For Obj-C, start by adding some necessary args that wouldn't show up in the aquery
        if case .objcImpl(let fileURL) = strategy {
            compilerArguments.append("-x")

            if fileURL.hasSuffix(".mm") {
                compilerArguments.append("objective-c++")
            } else {
                compilerArguments.append("objective-c")
            }
        }

        var index = 0
        let count = rawArguments.count

        // For Swift, invocations start with "wrapped swiftc". We can ignore those.
        // In the case of Obj-C, this is just a single `clang` reference.
        switch strategy {
        case .swiftModule: index = 2
        case .objcImpl, .cImpl, .cHeader: index = 1
        }

        while index < count {
            let arg = rawArguments[index]

            // Skip wrapped arguments. These don't work for some reason
            if arg.hasPrefix("-Xwrapped-swift") {
                index += 1
                continue
            }

            // Skip unsupported -c arg for Obj-C
            if case .objcImpl = strategy, arg == "-c" {
                index += 1
                continue
            }

            // Replace execution root placeholder
            if arg.contains("__BAZEL_EXECUTION_ROOT__") {
                let transformedArg = arg.replacingOccurrences(of: "__BAZEL_EXECUTION_ROOT__", with: rootUri)
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Skip batch mode (incompatible with -index-file)
            if arg == "-enable-batch-mode" {
                index += 1
                continue
            }

            // Skip -emit-const-values-path for now, this causes permission issues in bazel-out
            if arg == "-emit-const-values-path" {
                index += 2
                continue
            }

            // Replace SDK placeholder
            if arg.contains("__BAZEL_XCODE_SDKROOT__") {
                let transformedArg = arg.replacingOccurrences(of: "__BAZEL_XCODE_SDKROOT__", with: sdkRoot)
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Replace Xcode Developer Directory
            if arg.contains("__BAZEL_XCODE_DEVELOPER_DIR__") {
                let transformedArg = arg.replacingOccurrences(of: "__BAZEL_XCODE_DEVELOPER_DIR__", with: devDir)
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Transform bazel-out/ paths
            // FIXME: How to be sure this is actually the placeholder and not an actual "bazel-out" folder?
            if arg.contains("bazel-out/") {
                var transformedArg = arg.replacingOccurrences(of: "bazel-out/", with: outputPath + "/")
                // If compiling libraries individually, we need to also map the full apps' conf name
                // with the one that will be used in practice.
                if !config.baseConfig.compileTopLevel {
                    transformedArg = transformedArg.replacingOccurrences(
                        of: "/\(originalConfigName)/",
                        with: "/\(effectiveConfigName)/"
                    )
                }
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Transform external/ paths
            // FIXME: How to be sure this is actually the placeholder and not an actual "external/"" folder?
            if arg.contains("external/") {
                let transformedArg = arg.replacingOccurrences(of: "external/", with: outputBase + "/external/")
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // For Swift, Bazel will print relative paths, but indexing needs absolute paths.
            if arg.hasSuffix(".swift"), !arg.hasPrefix("/") {
                let transformedArg = rootUri + "/" + arg
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Same thing for modulemaps.
            if arg.hasPrefix("-fmodule-map-file="), !arg.hasPrefix("-fmodule-map-file=/") {
                let components = arg.components(separatedBy: "-fmodule-map-file=")
                let proper = rootUri + "/" + components[1]
                let transformedArg = "-fmodule-map-file=" + proper
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            compilerArguments.append(arg)
            index += 1
        }

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

        return compilerArguments
    }

    private func _editArg(_ arg: String, _ new: String, _ lines: inout [String]) {
        guard let idx = lines.firstIndex(of: arg) else {
            return
        }
        lines[idx + 1] = new
    }
}
