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

import ArgumentParser
import Foundation
import OSLog
import SourceKitBazelBSP

private let logger = makeFileLevelBSPLogger()

struct Serve: ParsableCommand {
    private static let defaultBuildTestPlatformPlaceholder = "(PLAT)"

    @Option(help: "The name of the Bazel CLI to invoke (e.g. 'bazelisk')")
    var bazelWrapper: String = "bazel"

    @Option(
        parsing: .singleValue,
        help:
            "The *top level* Bazel application or test target that this should serve a BSP for. Can be specified multiple times. It's best to keep this list small if possible for performance reasons. If not specified, the server will try to discover top-level targets automatically."
    )
    var target: [String] = []

    @Option(
        parsing: .singleValue,
        help:
            "A flag that should be passed to all indexing-related Bazel invocations. Do not include the -- prefix. Can be specified multiple times."
    )
    var indexFlag: [String] = []

    @Option(
        help:
            "The expected suffix format for build_test targets. Use the value of `--build-test-platform-placeholder` as a platform placeholder.",
    )
    var buildTestSuffix: String = "_\(Self.defaultBuildTestPlatformPlaceholder)_skbsp"

    @Option(
        help:
            "The expected platform placeholder for build_test targets.",
    )
    var buildTestPlatformPlaceholder: String = Self.defaultBuildTestPlatformPlaceholder

    @Option(
        help:
            "The expected platform placeholder for build_test targets.",
    )
    var buildTestPlatformPlaceholder: String = "(PLAT)"

    // FIXME: This should be enabled by default, but I ran into some weird race condition issues with rules_swift I'm not sure about.
    @Flag(
        help:
            "Whether to use a separate output base for compiler arguments requests. This greatly increases the performance of the server at the cost of more disk usage."
    )
    var separateAqueryOutput: Bool = false

    @Option(help: "Comma separated list of file globs to watch for changes.")
    var filesToWatch: String?

    func run() throws {
        logger.info("`serve` invoked, initializing BSP server...")

        let targets: [String]
        if !target.isEmpty {
            targets = target
        } else {
            // If the user provided no specific targets, try to discover them
            // in the workspace.
            logger.warning(
                "No targets specified (--target)! Will now try to discover them. This can cause the BSP to perform poorly if we find too many targets. Prefer using --target explicitly if possible."
            )
            do {
                targets = try BazelTargetDiscoverer.discoverTargets(
                    bazelWrapper: bazelWrapper
                )
            } catch {
                logger.error(
                    "Failed to initialize server: Could not discover targets. Please check your Bazel configuration or try specifying targets explicitly with `--target` instead. Failure: \(error)"
                )
                throw error
            }
        }

        let config = BaseServerConfig(
            bazelWrapper: bazelWrapper,
            targets: targets,
            indexFlags: indexFlag.map { "--" + $0 },
            buildTestSuffix: buildTestSuffix,
            buildTestPlatformPlaceholder: buildTestPlatformPlaceholder,
            filesToWatch: filesToWatch,
            useSeparateOutputBaseForAquery: separateAqueryOutput
        )
        let server = SourceKitBazelBSPServer(baseConfig: config)
        server.run()
    }
}
