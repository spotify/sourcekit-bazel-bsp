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

final class PrepareTargetHandler {

    let initializedConfig: InitializedServerConfig

    private var didRun = false

    init(initializedConfig: InitializedServerConfig) {
        self.initializedConfig = initializedConfig
    }

    func handle(
        request: BuildTargetPrepareRequest,
        id: RequestID,
        targetsToBazelMap: [URI: String]
    ) throws {
        // FIXME: Invalidate on changes
        guard !didRun else {
            return
        }

        let targets = request.targets.map { $0.uri }
        // FIXME: error handling
        let bazelTargets = targets.map { targetsToBazelMap[$0]! }

        logger.info("Building \(bazelTargets.count, privacy: .public) targets")

        // FIXME: find out how to properly only build the specific targets
        let bazelWrapper = initializedConfig.baseConfig.bazelWrapper
        let outputBase = initializedConfig.outputBase
        let appsToBuild = initializedConfig.baseConfig.targets.joined(separator: " ")
        let flags = initializedConfig.baseConfig.indexFlags.joined(separator: " ")
        let args = bazelWrapper + " --output_base=\(outputBase) build \(appsToBuild) \(flags)"
        _ = try shell(args)

        // After building, fix the output permissions.
        // SK needs write permissions.
        _ = try shell("chmod -R 777 \(outputBase)")

        logger.info("Finished building targets!")

        didRun = true
    }
}
