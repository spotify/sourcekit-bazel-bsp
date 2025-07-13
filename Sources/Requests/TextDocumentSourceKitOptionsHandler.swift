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
import LanguageServerProtocolJSONRPC

final class TextDocumentSourceKitOptionsHandler {
    let initializedConfig: InitializedServerConfig

    private var rootQueryCache: String?
    private var queryCache: [String: [String]] = [:]

    init(initializedConfig: InitializedServerConfig) {
        self.initializedConfig = initializedConfig
    }

    func handle(
        request: TextDocumentSourceKitOptionsRequest,
        id: RequestID,
        targetsToBazelMap: [URI: String],
    ) throws -> TextDocumentSourceKitOptionsResponse? {
        // Ignore header requests
        if request.textDocument.uri.stringValue.hasSuffix(".h") {
            return nil
        }
        let targetUri = request.target.uri
        logger.info(
            "Getting SKOptions for \(targetUri.stringValue, privacy: .public), language: \(request.language, privacy: .public)"
        )
        // FIXME: error handling
        let bazelTarget = targetsToBazelMap[targetUri]!
        logger.info("Target is: \(bazelTarget, privacy: .public)")
        let args = try getCompilerArguments(
            bazelTarget,
            request.language,
            request.textDocument.uri,
        )

        // If no compiler arguments are found, return nil to avoid sourcekit indexing with no input files
        if args.isEmpty {
            return nil
        }

        return TextDocumentSourceKitOptionsResponse(
            compilerArguments: args,
            workingDirectory: initializedConfig.rootUri
        )
    }

    func getCompilerArguments(
        _ bazelTarget: String,
        _ language: Language,
        _ textDocumentUri: URI,
    ) throws -> [String] {
        // For Swift, we query the whole target. But for ObjC, we need to query the files individually.
        let cacheKey: String
        let contentToQuery: String
        if language == .swift {
            cacheKey = bazelTarget
            contentToQuery = bazelTarget
        } else {
            let fullUri = textDocumentUri.stringValue
            let parsedFile = String(
                fullUri.dropFirst("file://".count + initializedConfig.rootUri.count + 1))
            // Make the path relative, as this is what aquery will return
            cacheKey = bazelTarget + "|" + parsedFile
            contentToQuery = parsedFile
        }
        if let cachedArgs = queryCache[cacheKey] {
            logger.info("Returning cached compiler arguments for \(cacheKey, privacy: .public)")
            return cachedArgs
        }
        logger.info("Getting compiler arguments for \(cacheKey, privacy: .public)")
        let bazelWrapper = initializedConfig.baseConfig.bazelWrapper
        let appToBuild = initializedConfig.baseConfig.aqueryString
        let outputBase = initializedConfig.outputBase
        let rootUri = initializedConfig.rootUri
        let flags = initializedConfig.baseConfig.indexFlags.joined(separator: " ")
        var output: String
        if let cachedRoot = rootQueryCache {
            output = cachedRoot
        } else {
            let cmd =
                bazelWrapper
                    + " --output_base=\(outputBase) aquery \"mnemonic('SwiftCompile|ObjcCompile', \(appToBuild))\" --noinclude_artifacts \(flags)"
            output = try shell(cmd, cwd: rootUri)
            rootQueryCache = output
        }
        logger.info("Parsing compiler arguments...")
        let result = try parseAquery(
            output,
            bazelTarget,
            contentToQuery,
            language,
        )
        queryCache[cacheKey] = result
        return result
    }

    func parseAquery(
        _ aqueryOutput: String,
        _ bazelTarget: String,
        _ contentToQuery: String,
        _ language: Language,
    ) throws -> [String] {
        var lines: [String] = aqueryOutput.components(separatedBy: "\n")
        var idx = -1
        for (i, line) in lines.enumerated() {
            var actionPrefix = "action 'Compiling "
            if language == .swift {
                actionPrefix += "Swift module \(bazelTarget)'"
            } else {
                actionPrefix += "\(contentToQuery)'"
            }
            if line.hasPrefix(actionPrefix) {
                if language == .swift {
                    if lines[i + 1] != "  Mnemonic: SwiftCompile" {
                        continue
                    }
                } else {
                    if lines[i + 1] != "  Mnemonic: ObjcCompile" {
                        continue
                    }
                    if lines[i + 2] != "  Target: \(bazelTarget)" {
                        continue
                    }
                }
                idx = i
                break
            }
        }
        if idx == -1 {
            logger.error(
                "No module entry found in the aquery for \(contentToQuery, privacy: .public)")
            return []
        }
        logger.info("Found module for \(bazelTarget, privacy: .public) at \(idx, privacy: .public)")
        // now, get the first index of the line that starts with "Command Line: ("
        lines = Array(lines.dropFirst(idx + 1))
        idx = -1
        for (i, line) in lines.enumerated() {
            if line.starts(with: "  Command Line: (") {
                idx = i
                // Also skip the swiftc line for swift targets
                if lines[idx + 1].contains("swiftc") {
                    idx += 1
                }
                break
            }
        }
        if idx == -1 {
            logger.error("No command line entry found")
            return []
        }
        logger.info("Found command line entry at \(idx, privacy: .public)")

        // now, find where the arguments end
        lines = Array(lines.dropFirst(idx + 1))

        idx = -1
        for (i, line) in lines.enumerated() {
            if line.starts(with: "#") {
                idx = i
                break
            }
        }
        if idx == -1 {
            logger.error("Couldn't find where the args end")
            return []
        }

        logger.info("Found where the args end at \(idx, privacy: .public)")
        lines = Array(lines.dropLast(lines.count - idx - 1))

        // the spaced lines are the compiler arguments
        lines = lines.filter { $0.starts(with: "    ") }

        lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        lines = lines.map { $0.hasSuffix(" \\") ? String($0.dropLast(2)) : $0 }
        // remove the trailing ) from the last line
        lines[lines.count - 1] = String(lines[lines.count - 1].dropLast())

        // some args are wrapped in single quotes for some reason
        for i in 0 ..< lines.count {
            if lines[i].hasPrefix("'"), lines[i].hasSuffix("'") {
                lines[i] = String(lines[i].dropFirst().dropLast())
            }
        }

        // Process compiler arguments with transformations
        let processedArgs = try processCompilerArguments(
            rawArguments: lines,
            language: language,
            contentToQuery: contentToQuery
        )

        lines = processedArgs

        logger.info("Finished processing compiler arguments")

        return lines
    }

    /// Processes compiler arguments with transformations
    func processCompilerArguments(
        rawArguments: [String],
        language: Language,
        contentToQuery: String
    ) throws -> [String] {
        var compilerArguments: [String] = []

        let sdkRoot = initializedConfig.sdkRoot
        let devDir = initializedConfig.devDir
        let outputPath = initializedConfig.outputPath
        let rootUri = initializedConfig.rootUri
        let outputBase = initializedConfig.outputBase

        var index = 0
        let count = rawArguments.count

        let indexingObjCHeader = language == .objective_c && contentToQuery.hasSuffix(".m")

        if indexingObjCHeader {
            // Xcode index builds adds these arguments to the beginning.
            compilerArguments.append("-x")
            compilerArguments.append("objective-c")
        }

        // Filtering/processing arguments that are either not needed for indexing or cause problems with it
        while index < count {
            let arg = rawArguments[index]

            // Skip wrapper arguments
            if arg.hasPrefix("-Xwrapped-swift") {
                index += 1
                continue
            }

            // Just aligning inconsistencies with Xcode index Obj-C builds.
            if arg == "-c" && indexingObjCHeader {
                index += 1
                continue
            }

            // Skip batch mode (incompatible with -index-file)
            if arg.contains("-enable-batch-mode") {
                index += 1
                continue
            }

            // For Swift, swap the index store arg with the global cache.
            // Bazel handles this a bit differently internally, which is why
            // we need to do this.
            if arg == "-index-store-path" {
                compilerArguments.append("-index-store-path")
                compilerArguments.append(initializedConfig.indexStorePath)
                index += 2
                continue
            }

            // For Swift, Bazel will print relative paths, but indexing needs absolute paths.
            if arg.hasSuffix(".swift"), !arg.hasPrefix("/") {
                let transformedArg = rootUri + "/" + arg
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Same as above, but for modulemaps.
            if arg.hasPrefix("-fmodule-map-file="), !arg.hasPrefix("-fmodule-map-file=/") {
                let components = arg.components(separatedBy: "-fmodule-map-file=")
                let proper = rootUri + "/" + components[1]
                let transformedArg = "-fmodule-map-file=" + proper
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Otherwise, just add the argument.
            compilerArguments.append(arg)
            index += 1
        }

        // Now, replace Bazel env placeholders with the actual values
        for i in 0 ..< compilerArguments.count {
            let arg = compilerArguments[i]

            if arg.contains(BazelEnvPlaceholder.execRoot.rawValue) {
                compilerArguments[i] = arg.replacingOccurrences(
                    of: BazelEnvPlaceholder.execRoot.rawValue,
                    with: rootUri
                )
                continue
            }

            if arg.contains(BazelEnvPlaceholder.sdkRoot.rawValue) {
                compilerArguments[i] = arg.replacingOccurrences(
                    of: BazelEnvPlaceholder.sdkRoot.rawValue,
                    with: sdkRoot
                )
                continue
            }

            if arg.contains(BazelEnvPlaceholder.devDir.rawValue) {
                compilerArguments[i] = arg.replacingOccurrences(
                    of: BazelEnvPlaceholder.devDir.rawValue,
                    with: devDir
                )
                continue
            }

            // For bazel-out/, we want to replace the symlinks only,
            // not references to the actual folder.
            if arg.contains("bazel-out/") && !arg.contains("execroot/_main/bazel-out/") {
                // FIXME: Need guardrails to make sure this is actually
                // the bazel-out and not some path who just happens to have
                // bazel-out/ in its name
                compilerArguments[i] = arg.replacingOccurrences(
                    of: "bazel-out/",
                    with: outputPath + "/"
                )
                continue
            }

            if arg.contains("external/") {
                // FIXME: Need guardrails to make sure this is actually
                // the folder we're looking for and not some path who just happens to have
                // external/ in its name
                compilerArguments[i] = arg.replacingOccurrences(
                    of: "external/",
                    with: outputBase + "/external/"
                )
                continue
            }
        }

        if indexingObjCHeader {
            // For Obj-C, add additional arguments that are needed for indexing
            // that Bazel / SK doesn't add by default, and adjust other inconsistencies
            // with Xcode index builds.
            compilerArguments.append("-index-store-path")
            compilerArguments.append(initializedConfig.indexStorePath)
            compilerArguments.append("-working-directory")
            compilerArguments.append(initializedConfig.rootUri)
        }

        return compilerArguments
    }

    func removeArgSingle(_ arg: String, _ lines: inout [String]) {
        guard let idx = lines.firstIndex(of: arg) else {
            return
        }
        lines.remove(at: idx)
    }

    func removeArg(_ arg: String, _ lines: inout [String]) {
        guard let idx = lines.firstIndex(of: arg) else {
            return
        }
        lines.remove(at: idx + 1)
        lines.remove(at: idx)
    }

    func editArg(_ arg: String, _ new: String, _ lines: inout [String]) {
        guard let idx = lines.firstIndex(of: arg) else {
            return
        }
        lines[idx + 1] = new
    }
}
