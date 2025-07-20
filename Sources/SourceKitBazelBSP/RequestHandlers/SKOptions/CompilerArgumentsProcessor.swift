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

import Foundation
import LanguageServerProtocol

private let logger = makeFileLevelBSPLogger()

enum CompilerArgumentsProcessor {
    // Parses and processes the compilation step for a given target from a larger aquery output.
    // The parsing step is only necessary because BazelTargetAquerier operates on text. Should become unnecessary once we move to proto.
    static func extractAndProcessCompilerArgs(
        fromAquery aqueryOutput: String,
        bazelTarget: String,
        contentToQuery: String,
        language: Language,
        initializedConfig: InitializedServerConfig
    ) -> [String]? {
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
                    if lines[i + 1] != "  Mnemonic: SwiftCompile" { continue }
                } else {
                    if lines[i + 1] != "  Mnemonic: ObjcCompile" { continue }
                    if lines[i + 2] != "  Target: \(bazelTarget)" { continue }
                }
                idx = i
                break
            }
        }
        if idx == -1 {
            logger.error("No module entry found in the aquery for \(contentToQuery)")
            return nil
        }
        // now, get the first index of the line that starts with "Command Line: ("
        lines = Array(lines.dropFirst(idx + 1))
        idx = -1
        for (i, line) in lines.enumerated() {
            if line.starts(with: "  Command Line: (") {
                idx = i
                // Also skip the swiftc line for swift targets
                if lines[idx + 1].contains("swiftc") { idx += 1 }
                break
            }
        }
        if idx == -1 {
            logger.error("No command line entry found")
            return nil
        }
        logger.info("Found command line entry at \(idx)")

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
            return nil
        }

        logger.info("Found where the args end at \(idx)")
        lines = Array(lines.dropLast(lines.count - idx - 1))

        // the spaced lines are the compiler arguments
        lines = lines.filter { $0.starts(with: "    ") }

        lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        lines = lines.map { $0.hasSuffix(" \\") ? String($0.dropLast(2)) : $0 }
        // remove the trailing ) from the last line
        lines[lines.count - 1] = String(lines[lines.count - 1].dropLast())

        // some args are wrapped in single quotes for some reason
        for i in 0..<lines.count {
            if lines[i].hasPrefix("'"), lines[i].hasSuffix("'") {
                lines[i] = String(lines[i].dropFirst().dropLast())
            }
        }

        let processedArgs = _processCompilerArguments(
            rawArguments: lines,
            contentToQuery: contentToQuery,
            language: language,
            initializedConfig: initializedConfig
        )

        lines = processedArgs

        logger.info("Finished processing compiler arguments")
        logger.logFullObjectInMultipleLogMessages(
            level: .debug,
            header: "Parsed compiler arguments",
            lines.joined(separator: "\n"),
        )

        return lines
    }

    /// Processes compiler arguments for the LSP by removing unnecessary arguments and replacing placeholders.
    private static func _processCompilerArguments(
        rawArguments: [String],
        contentToQuery: String,
        language: Language,
        initializedConfig: InitializedServerConfig
    ) -> [String] {

        let sdkRoot = initializedConfig.sdkRoot
        let devDir = initializedConfig.devDir
        let outputPath = initializedConfig.outputPath
        let rootUri = initializedConfig.rootUri
        let outputBase = initializedConfig.outputBase

        var compilerArguments: [String] = []

        let isObjCImpl = language == .objective_c && contentToQuery.hasSuffix(".m")
        // For Obj-C, start by adding some necessary args that wouldn't show up in the aquery
        if isObjCImpl {
            compilerArguments.append("-x")
            compilerArguments.append("objective-c")
        }

        var index = 0
        let count = rawArguments.count

        while index < count {
            let arg = rawArguments[index]

            // Skip wrapped arguments. These don't work for some reason
            if arg.hasPrefix("-Xwrapped-swift") {
                index += 1
                continue
            }

            // Skip unsupported -c arg for Obj-C
            if isObjCImpl, arg == "-c" {
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
                let transformedArg = arg.replacingOccurrences(of: "bazel-out/", with: outputPath + "/")

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
        if isObjCImpl {
            compilerArguments.append("-index-store-path")
            compilerArguments.append(initializedConfig.indexStorePath)
            compilerArguments.append("-working-directory")
            compilerArguments.append(initializedConfig.rootUri)
        } else if language == .swift {
            // For Swift, swap the index store arg with the global cache.
            // Bazel handles this a bit differently internally, which is why
            // we need to do this.
            editArg("-index-store-path", initializedConfig.indexStorePath, &compilerArguments)
        }

        return compilerArguments
    }

    private static func editArg(_ arg: String, _ new: String, _ lines: inout [String]) {
        guard let idx = lines.firstIndex(of: arg) else {
            return
        }
        lines[idx + 1] = new
    }
}
