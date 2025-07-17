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
import BSPLogging
import Foundation
import SourceKitBazelBSP

let logger = SwiftLogger(label: "sourcekit-bazel-bsp")

struct Serve: ParsableCommand {
    @Option(help: "The name of the Bazel CLI to invoke (e.g. 'bazelisk')")
    var bazelWrapper: String = "bazel"

    // FIXME: We should support any library target, not just the app ones.
    // The problem is that ios_application targets apply transitions that don't get reflected
    // when building libraries individually. Queries have a --universe_scope flag to account for this,
    // but this is not available for build actions at the moment. We need to find a stable way of building
    // libraries with the same configs that would be applied when building the full app.
    @Option(
        parsing: .singleValue,
        help:
            "The Bazel ios_application or test targets that this should serve a BSP for. Can be specified multiple times."
    )
    var target: [String]

    @Option(
        parsing: .singleValue,
        help:
            "A flag that should be passed to all indexing-related Bazel invocations. Do not include the -- prefix. Can be specified multiple times."
    )
    var indexFlag: [String] = []

    @Option(
        help:
            "Comma separated list of file globs to watch for changes."
    )
    var filesToWatch: String?
    
    @Flag(
        help:
            "Use FileHandler as backend which will be stored at ~/bazel-bsp.log. Default is to use OSLog as backend"
    )
    var logToFile: Bool = false

    func run() throws {
        // setup logging as early as we can
        BSPLogging.setup(logToFile: logToFile, logLevel: .info)
        
        logger.info("`serve` invoked, initializing BSP server...")
        let config = BaseServerConfig(
            bazelWrapper: bazelWrapper,
            targets: target,
            indexFlags: indexFlag.map { "--" + $0 },
            filesToWatch: filesToWatch
        )
        let server = SourceKitBazelBSPServer(baseConfig: config)
        server.run()
    }
}
