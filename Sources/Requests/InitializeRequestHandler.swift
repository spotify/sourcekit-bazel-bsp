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

struct InitializeRequestHandler {
    func handle(
        request: InitializeBuildRequest,
        initializedConfig: InitializedServerConfig,
    ) throws -> InitializeBuildResponse {
        let capabilities = request.capabilities
        let watchers: [FileSystemWatcher]?
        let rootUri = initializedConfig.rootUri
        if let filesToWatch = initializedConfig.baseConfig.filesToWatch {
            watchers = filesToWatch.components(separatedBy: ",").map {
                FileSystemWatcher(globPattern: rootUri + "/" + $0)
            }
        } else {
            watchers = nil
        }
        return InitializeBuildResponse(
            displayName: "sourcekit-bazel-bsp",
            version: "0.0.1",
            bspVersion: "2.2.0",
            capabilities: BuildServerCapabilities(
                compileProvider: .init(languageIds: capabilities.languageIds),
                testProvider: .init(languageIds: capabilities.languageIds),
                runProvider: .init(languageIds: capabilities.languageIds),
                debugProvider: .init(languageIds: capabilities.languageIds),
                inverseSourcesProvider: true,
                dependencySourcesProvider: true,
                resourcesProvider: true,
                outputPathsProvider: false, // FIXME:
                buildTargetChangedProvider: true,
                canReload: true,
            ),
            dataKind: InitializeBuildResponseDataKind.sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: initializedConfig.indexDatabasePath,
                indexStorePath: initializedConfig.indexStorePath,
                outputPathsProvider: nil,
                prepareProvider: true,
                sourceKitOptionsProvider: true,
                watchers: watchers,
            ).encodeToLSPAny()
        )
    }
}
