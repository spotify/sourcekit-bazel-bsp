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

import struct os.OSAllocatedUnfairLock

@testable import SourceKitBazelBSP

final class BazelTargetStoreFake: BazelTargetStore {
    let stateLock = OSAllocatedUnfairLock()
    var clearCacheCalled = false
    var fetchTargetsCalled = false
    var fetchTargetsError: Error?
    var mockSrcToBspURIs: [DocumentURI: [DocumentURI]] = [:]
    var mockPlatformsToTopLevelLabelsMap: [String: [String]] = [:]

    var platformsToTopLevelLabelsMap: [String: [String]] { mockPlatformsToTopLevelLabelsMap }

    func fetchTargets() throws -> [BuildTarget] {
        fetchTargetsCalled = true
        if let error = fetchTargetsError {
            throw error
        }
        return []
    }

    func bspURIs(containingSrc src: DocumentURI) throws -> [DocumentURI] {
        if let uris = mockSrcToBspURIs[src] {
            return uris
        }
        throw BazelTargetStoreError.unknownBSPURI(src)
    }

    func bazelTargetLabel(forBSPURI uri: DocumentURI) throws -> String {
        unimplemented()
    }

    func bazelTargetSrcs(forBSPURI uri: DocumentURI) throws -> [DocumentURI] {
        unimplemented()
    }

    func platformBuildLabelInfo(forBSPURI uri: URI) throws -> BazelTargetPlatformInfo {
        unimplemented()
    }

    func clearCache() {
        clearCacheCalled = true
    }
}
