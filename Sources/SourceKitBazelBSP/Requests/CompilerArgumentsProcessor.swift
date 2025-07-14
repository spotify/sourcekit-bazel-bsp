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

enum CompilerArgumentsProcessor {
    /// Processes compiler arguments with transformations
    static func processCompilerArguments(
        rawArguments: [String],
        sdkRoot: String,
        devDir: String,
        outputPath: String,
        rootUri: String,
        outputBase: String
    ) throws -> [String] {
        var compilerArguments: [String] = []

        var index = 0
        let count = rawArguments.count

        while index < count {
            let arg = rawArguments[index]

            // Skip swiftc executable and wrapper arguments
            if arg.contains("-Xwrapped-swift") || arg.hasSuffix("worker") || arg.hasPrefix("swiftc") {
                index += 1
                continue
            }

            // skip clang
            if arg.contains("wrapped_clang") {
                index += 1
                continue
            }

            // Replace execution root placeholder
            if arg.contains("__BAZEL_EXECUTION_ROOT__") {
                let transformedArg = arg.replacingOccurrences(
                    of: "__BAZEL_EXECUTION_ROOT__",
                    with: rootUri
                )
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Skip batch mode (incompatible with -index-file)
            if arg.contains("-enable-batch-mode") {
                index += 1
                continue
            }

            // Skip index store path arguments (handled later)
            if arg.contains("-index-store-path") {
                if index + 1 < count, rawArguments[index + 1].contains("indexstore") {
                    index += 2
                    continue
                }
            }

            // Skip const-gather-protocols arguments
            if arg.contains("-Xfrontend"), index + 1 < count {
                let nextArg = rawArguments[index + 1]
                if nextArg.contains("-const-gather-protocols-file")
                    || nextArg.contains("const_protocols_to_gather.json")
                {
                    index += 2
                    continue
                }
            }

            // Replace SDK placeholder
            if arg.contains("__BAZEL_XCODE_SDKROOT__") {
                let transformedArg = arg.replacingOccurrences(
                    of: "__BAZEL_XCODE_SDKROOT__",
                    with: sdkRoot
                )
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // replace Xcode Developer Directory
            if arg.contains("__BAZEL_XCODE_DEVELOPER_DIR__") {
                let transformedArg = arg.replacingOccurrences(
                    of: "__BAZEL_XCODE_DEVELOPER_DIR__",
                    with: devDir
                )
                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Transform bazel-out/ paths
            if arg.contains("bazel-out/") {
                let transformedArg = arg.replacingOccurrences(of: "bazel-out/", with: outputPath + "/")

                compilerArguments.append(transformedArg)
                index += 1
                continue
            }

            // Transform external/ paths
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

        return compilerArguments
    }
}
