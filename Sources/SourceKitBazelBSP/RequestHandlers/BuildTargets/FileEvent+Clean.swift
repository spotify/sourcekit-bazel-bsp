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
import BuildServerProtocol
import Foundation
import LanguageServerProtocol

extension Array where Element == FileEvent {
    // Cleans up the events array by doing three things:
    // 1. Removing duplicates (e.g. adding the same file with no removal in between)
    // 2. Removing actions that cancel each other out, such as an addition followed by a removal of the same file.
    // 3. Ignoring .changed events
    func cleaned() -> [FileEvent] {

        // Step 1: Ignore .changed and remove sequential duped events
        var lastEventForUri: [DocumentURI: FileChangeType] = [:]
        var deduped = [FileEvent]()
        for event in self where event.type != .changed {
            if let lastEvent = lastEventForUri[event.uri] {
                if lastEvent != event.type {
                    deduped.append(event)
                    lastEventForUri[event.uri] = event.type
                }
            } else {
                deduped.append(event)
                lastEventForUri[event.uri] = event.type
            }
        }

        // Step 2: Only keep the last odd event for each URI
        var lastIndexForUri: [DocumentURI: (count: Int, lastIndex: Int)] = [:]
        for i in 0..<deduped.count {
            let curr = lastIndexForUri[deduped[i].uri, default: (count: 0, lastIndex: 0)]
            lastIndexForUri[deduped[i].uri] = (curr.count + 1, i)
        }
        return deduped.enumerated().filter { index, event in
            guard let data = lastIndexForUri[event.uri] else {
                return false
            }
            return data.count % 2 == 1 && index == data.lastIndex
        }.map { $0.element }
    }
}
