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

// Registry of all BSP requests that sourcekit-lsp expects (and that we can handle).

typealias BSPRequestHandler<Request: RequestType> = (
    (Request, RequestID) throws -> Request.Response
)

typealias InitializeBuildRequestHandler = BSPRequestHandler<InitializeBuildRequest>
typealias WaitForBuildUpdatesRequestHandler = BSPRequestHandler<
    WorkspaceWaitForBuildSystemUpdatesRequest
>
typealias BuildTargetPrepareRequestHandler = BSPRequestHandler<BuildTargetPrepareRequest>
typealias BuildShutdownRequestHandler = BSPRequestHandler<BuildShutdownRequest>
typealias WorkspaceBuildTargetsRequestHandler = BSPRequestHandler<
    WorkspaceBuildTargetsRequest
>
typealias BuildTargetSourcesRequestHandler = BSPRequestHandler<BuildTargetSourcesRequest>
typealias TextDocumentSourceKitOptionsRequestHandler = BSPRequestHandler<
    TextDocumentSourceKitOptionsRequest
>

extension BSPMessageHandler {
    final class RequestHandlers {
        let initializeBuild: InitializeBuildRequestHandler?
        let waitForBuildSystemUpdates: WaitForBuildUpdatesRequestHandler?
        let buildTargetPrepare: BuildTargetPrepareRequestHandler?
        let buildShutdown: BuildShutdownRequestHandler?
        let workspaceBuildTargets: WorkspaceBuildTargetsRequestHandler?
        let buildTargetSources: BuildTargetSourcesRequestHandler?
        let textDocumentSourceKitOptions: TextDocumentSourceKitOptionsRequestHandler?
        let prepareTarget: BuildTargetPrepareRequestHandler?

        init(
            initializeBuild: InitializeBuildRequestHandler? = nil,
            waitForBuildSystemUpdates: WaitForBuildUpdatesRequestHandler? = nil,
            buildTargetPrepare: BuildTargetPrepareRequestHandler? = nil,
            buildShutdown: BuildShutdownRequestHandler? = nil,
            workspaceBuildTargets: WorkspaceBuildTargetsRequestHandler? = nil,
            buildTargetSources: BuildTargetSourcesRequestHandler? = nil,
            textDocumentSourceKitOptions: TextDocumentSourceKitOptionsRequestHandler? = nil,
            prepareTarget: BuildTargetPrepareRequestHandler? = nil
        ) {
            self.initializeBuild = initializeBuild
            self.waitForBuildSystemUpdates = waitForBuildSystemUpdates
            self.buildTargetPrepare = buildTargetPrepare
            self.buildShutdown = buildShutdown
            self.workspaceBuildTargets = workspaceBuildTargets
            self.buildTargetSources = buildTargetSources
            self.textDocumentSourceKitOptions = textDocumentSourceKitOptions
            self.prepareTarget = prepareTarget
        }
    }
}
