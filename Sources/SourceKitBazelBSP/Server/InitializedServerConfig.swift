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

/// The full configuration of the server, including all information needed to operate the BSP.
/// Created by the BSP based on the initial `BaseServerConfig`` when the LSP sends us the `initialize` request.
struct InitializedServerConfig: Equatable {

    static let rulesSwiftIndexStoreFolderName = "_global_index_store"
    static let lspIndexDatabaseFolderName = "_global_index_database"

    let baseConfig: BaseServerConfig
    let rootUri: String
    let workspaceName: String
    let outputBase: String
    let outputPath: String
    let baseIndexDataFolder: String
    let devDir: String
    let xcodeVersion: String
    let devToolchainPath: String
    let executionRoot: String
    let sdkRootPaths: [String: String]

    var indexDatabasePath: String {
        baseIndexDataFolder + "/" + Self.lspIndexDatabaseFolderName
    }

    var indexStorePath: String {
        baseIndexDataFolder + "/" + Self.rulesSwiftIndexStoreFolderName
    }
}
