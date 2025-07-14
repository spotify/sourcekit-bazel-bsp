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
        let processedArgs = try CompilerArgumentsProcessor.processCompilerArguments(
            rawArguments: lines,
            sdkRoot: initializedConfig.sdkRoot,
            devDir: initializedConfig.devDir,
            outputPath: initializedConfig.outputPath,
            rootUri: initializedConfig.rootUri,
            outputBase: initializedConfig.outputBase
        )

        lines = processedArgs

        if language == .objective_c, contentToQuery.hasSuffix(".m") {
            // For Obj-C, add additional arguments that are needed for indexing
            // that Bazel / SK doesn't add by default, and adjust other inconsistencies
            // with Xcode index builds.
            removeArgSingle("-c", &lines)
            lines.insert("-x", at: 0)
            lines.insert("objective-c", at: 1)
            lines.append("-index-store-path")
            lines.append(initializedConfig.indexStorePath)
            lines.append("-working-directory")
            lines.append(initializedConfig.rootUri)
        } else if language == .swift {
            // For Swift, swap the index store arg with the global cache.
            // Bazel handles this a bit differently internally, which is why
            // we need to do this.
            editArg("-index-store-path", initializedConfig.indexStorePath, &lines)
        }

        logger.info("Finished processing compiler arguments")
        logger.logFullObjectInMultipleLogMessages(
            level: .debug,
            header: "Parsed compiler arguments",
            lines.joined(separator: "\n"),
        )

        return lines
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

    /// Convenience method for testing - processes compiler arguments using the configured settings
    func processCompilerArguments(rawArguments: [String]) throws -> [String] {
        return try CompilerArgumentsProcessor.processCompilerArguments(
            rawArguments: rawArguments,
            sdkRoot: initializedConfig.sdkRoot,
            devDir: initializedConfig.devDir,
            outputPath: initializedConfig.outputPath,
            rootUri: initializedConfig.rootUri,
            outputBase: initializedConfig.outputBase
        )
    }
}
