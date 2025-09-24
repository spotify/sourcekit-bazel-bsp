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

private let logger = makeFileLevelBSPLogger()

/// Small abstraction on top of Analysis_ActionGraphContainer to pre-aggregate the proto results.
struct AqueryResult: Hashable {
    let targets: [String: Analysis_Target]
    let actions: [UInt32: [Analysis_Action]]

    init(data: Data) throws {
        let results = try BazelProtobufBindings.parseActionGraph(data: data)
        self = AqueryResult(results: results)
    }

    init(results: Analysis_ActionGraphContainer) {
        let targets: [String: Analysis_Target] = results.targets.reduce(into: [:]) { result, target in
            if result.keys.contains(target.label) {
                logger.error(
                    "Duplicate target found when aquerying (\(target.label))! This is unexpected. Will ignore the duplicate."
                )
            }
            result[target.label] = target
        }
        let actions: [UInt32: [Analysis_Action]] = results.actions.reduce(into: [:]) { result, action in
            // If the aquery contains data of multiple platforms,
            // then we will see multiple entries for the same targetID.
            // We need to store all of them and find the correct variant later.
            result[action.targetID, default: []].append(action)
        }
        self.targets = targets
        self.actions = actions
    }
}
