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
import os

package struct BaseServerConfig {
    let bazelWrapper: String
    let targets: [String]
    let indexFlags: [String]
    let filesToWatch: String?

    package init(
        bazelWrapper: String,
        targets: [String],
        indexFlags: [String],
        filesToWatch: String?
    ) {
        self.bazelWrapper = bazelWrapper
        self.targets = targets
        self.indexFlags = indexFlags
        self.filesToWatch = filesToWatch
    }

    // FIXME: Temporary hack
    var appTarget: String {
        targets[0]
    }

    var aqueryString: String {
        var query = ""
        for target in self.targets {
            if query == "" {
                query = "deps(\(target))"
            } else {
                query += " union deps(\(target))"
            }
        }
        return query
    }
}

struct InitializedServerConfig {
    let baseConfig: BaseServerConfig
    let rootUri: String
    let outputBase: String
    let outputPath: String
    let devDir: String
    let sdkRoot: String
    let taskLogger: TaskLogger

    var indexDatabasePath: String {
        outputPath + "/_global_index_database"
    }

    var indexStorePath: String {
        outputPath + "/_global_index_store"
    }
}
