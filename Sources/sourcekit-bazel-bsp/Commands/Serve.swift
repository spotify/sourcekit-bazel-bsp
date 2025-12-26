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
    @Option(help: "The name of the Bazel CLI to invoke (e.g. 'bazelisk')")
    var bazelWrapper: String = "bazel"

    @Option(
        parsing: .singleValue,
        help:
            "The *top level* Bazel application or test target that this should serve a BSP for. Can be specified multiple times. Wildcards are supported (e.g. //foo/...). It's best to keep this list small if possible for performance reasons. If not specified, the server will try to discover top-level targets automatically."
    )
    var target: [String] = []

    @Option(
        parsing: .singleValue,
        help:
            "A flag that should be passed to all indexing-related Bazel invocations. Do not include the -- prefix. Can be specified multiple times."
    )
    var indexFlag: [String] = []

    @Option(help: "Comma separated list of file globs to watch for changes.")
    var filesToWatch: String?

    @Option(
        parsing: .singleValue,
        help:
            "A top-level rule type to discover targets for (e.g. 'ios_application', 'ios_unit_test'). Can be specified multiple times. If not specified, all supported top-level rule types will be used for target discovery."
    )
    var topLevelRuleToDiscover: [TopLevelRuleType] = []

    @Option(
        parsing: .singleValue,
        help:
            "A rule kind to discover dependencies for (e.g. 'swift_library', 'objc_library', 'cc_library'). Can be specified multiple times. If not specified, all supported rule kinds will be used for dependency discovery."
    )
    var dependencyRuleToDiscover: [DependencyRuleType] = []

    @Flag(
        help:
            "Instead of attempting to build targets individually, build the top-level parent. If your project contains build_test targets for your individual libraries and you're passing them as the top-level targets for the BSP, you can use this flag to build those targets directly for better predictability and caching."
    )
    var compileTopLevel: Bool = false

    @Option(
        parsing: .singleValue,
        help:
            "A target pattern to exclude when discovering top-level targets. Can be specified multiple times. Wildcards are supported (e.g. //foo/...)."
    )
    var topLevelTargetToExclude: [String] = []

    @Option(
        parsing: .singleValue,
        help:
            "A target pattern to exclude when discovering dependency targets. Can be specified multiple times. Wildcards are supported (e.g. //foo/...)."
    )
    var dependencyTargetToExclude: [String] = []

    func run() throws {
        logger.info("`serve` invoked, initializing BSP server...")

        let topLevelRulesToDiscover: [TopLevelRuleType] =
            topLevelRuleToDiscover.isEmpty ? TopLevelRuleType.allCases : topLevelRuleToDiscover
        let dependencyRulesToDiscover: [DependencyRuleType] =
            dependencyRuleToDiscover.isEmpty ? DependencyRuleType.allCases : dependencyRuleToDiscover
        let indexFlags = indexFlag.map { "--" + $0 }
        let targets = target.isEmpty ? ["//..."] : target

        let config = BaseServerConfig(
            bazelWrapper: bazelWrapper,
            targets: targets,
            indexFlags: indexFlags,
            filesToWatch: filesToWatch,
            compileTopLevel: compileTopLevel,
            topLevelRulesToDiscover: topLevelRulesToDiscover,
            dependencyRulesToDiscover: dependencyRulesToDiscover,
            topLevelTargetsToExclude: topLevelTargetToExclude,
            dependencyTargetsToExclude: dependencyTargetToExclude
        )

        logger.debug("Initializing BSP with targets: \(targets)")

        let server = SourceKitBazelBSPServer(baseConfig: config)
        server.run()
    }
}
