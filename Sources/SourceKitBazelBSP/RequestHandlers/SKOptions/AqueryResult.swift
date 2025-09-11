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

enum AqueryResultError: Error, LocalizedError {
    case duplicateTarget(label: String)
    case duplicateAction(targetID: UInt32)

    var errorDescription: String? {
        switch self {
        case .duplicateTarget(let label): return "Duplicate target found in the aquery! (\(label)) This can happen if a target gets different arguments depending on which top-level target builds it (on the same platform). Currently, the BSP expects the target to be stable in that sense."
        case .duplicateAction(let targetID): return "Duplicate action ID found in the aquery! (\(targetID)) This is unexpected. Failing pre-emptively."
        }
    }
}

/// Small abstraction on top of Analysis_ActionGraphContainer to pre-aggregate the proto results.
final class AqueryResult {
    let targets: [String: Analysis_Target]
    let actions: [UInt32: Analysis_Action]

    init(results: Analysis_ActionGraphContainer) throws {
        let targets: [String: Analysis_Target] = try results.targets.reduce(into: [:]) { result, target in
            if result.keys.contains(target.label) {
                throw AqueryResultError.duplicateTarget(label: target.label)
            }
            result[target.label] = target
        }
        let actions: [UInt32: Analysis_Action] = try results.actions.reduce(into: [:]) { result, action in
            if result.keys.contains(action.targetID) {
                throw AqueryResultError.duplicateAction(targetID: action.targetID)
            }
            result[action.targetID] = action
        }
        self.targets = targets
        self.actions = actions
    }
}
