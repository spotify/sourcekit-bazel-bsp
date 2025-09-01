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
import Foundation
import LanguageServerProtocol

private let logger = makeFileLevelBSPLogger()

enum CompilerArgumentsProcessor {
    // Parses and processes the compilation step for a given target from a larger aquery output.
    static func extractAndProcessCompilerArgs(
        fromAquery aqueryOutput: Analysis_ActionGraphContainer,
        bazelTarget: String,
        contentToQuery: String,
        language: Language,
        sdkRoot: String,
        initializedConfig: InitializedServerConfig
    ) -> [String]? {
        guard let target = aqueryOutput.targets.first(where: { $0.label == bazelTarget }) else {
            logger.debug("Target: \(bazelTarget) not found.")
            return nil
        }
        guard let action = aqueryOutput.actions.first(where: { $0.targetID == target.id }) else {
            logger.debug("Action for \(bazelTarget) not found.")
            return nil
        }

        let rawArguments = action.arguments

        let processedArgs = _processCompilerArguments(
            rawArguments: rawArguments,
            contentToQuery: contentToQuery,
            language: language,
            sdkRoot: sdkRoot,
            initializedConfig: initializedConfig
        )

        logger.info("Finished processing compiler arguments")
        logger.logFullObjectInMultipleLogMessages(
            level: .debug,
            header: "Parsed compiler arguments",
            processedArgs.joined(separator: "\n"),
        )
        return processedArgs
    }

    /// Processes compiler arguments for the LSP by removing unnecessary arguments and replacing placeholders.
    private static func _processCompilerArguments(
        rawArguments: [String],
        contentToQuery: String,
        language: Language,
        sdkRoot: String,
        initializedConfig: InitializedServerConfig
    ) -> [String] {

        let devDir = initializedConfig.devDir
        let rootUri = initializedConfig.rootUri

        // We ran the aquery on the aquery output base, but we need this
        // to reflect the data of the real build output base.
        let outputPath: String = {
            let base: String = initializedConfig.outputPath
            guard initializedConfig.aqueryOutputBase != initializedConfig.outputBase else {
                return base
            }
            return base.replacingOccurrences(
                of: initializedConfig.aqueryOutputBase,
                with: initializedConfig.outputBase
            )
        }()
        let outputBase = {
            let base: String = initializedConfig.outputBase
            guard initializedConfig.aqueryOutputBase != initializedConfig.outputBase else {
                return base
            }
            return base.replacingOccurrences(
                of: initializedConfig.aqueryOutputBase,
                with: initializedConfig.outputBase
            )
        }()

        var compilerArguments: [String] = []

        let isObjCImpl = language == .objective_c && contentToQuery.hasSuffix(".m")
        // For Obj-C, start by adding some necessary args that wouldn't show up in the aquery
        if isObjCImpl {
            compilerArguments.append("-x")
            compilerArguments.append("objective-c")
        }

        var index = 0
        let count = rawArguments.count

        // For Swift, invocations start with "wrapped swiftc". We can ignore those.
        // In the case of Obj-C, this is just a single `clang` reference.
        switch language {
        case .swift: index = 2
        case .objective_c: index = 1
        default: break
        }

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
