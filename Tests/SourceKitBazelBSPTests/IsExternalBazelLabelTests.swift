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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct IsExternalBazelLabelTests {
    @Test
    func internalLabelWithoutAtPrefix() {
        #expect("//foo/bar:target".isExternalBazelLabel() == false)
    }

    @Test
    func internalLabelWithSingleAtPrefix() {
        #expect("@//foo/bar:target".isExternalBazelLabel() == false)
    }

    @Test
    func internalLabelWithDoubleAtPrefix() {
        #expect("@@//foo/bar:target".isExternalBazelLabel() == false)
    }

    @Test
    func relativeLabel() {
        #expect(":target".isExternalBazelLabel() == false)
    }

    @Test
    func externalRepoLabel() {
        #expect("@external_repo//foo:bar".isExternalBazelLabel() == true)
    }

    @Test
    func bzlmodExternalRepoLabel() {
        #expect("@@external_repo//foo:bar".isExternalBazelLabel() == true)
    }

    @Test
    func externalRepoWithoutPath() {
        #expect("@external_repo".isExternalBazelLabel() == true)
    }

    @Test
    func emptyString() {
        #expect("".isExternalBazelLabel() == false)
    }

    @Test
    func singleAtOnly() {
        #expect("@".isExternalBazelLabel() == false)
    }

    @Test
    func doubleAtOnly() {
        #expect("@@".isExternalBazelLabel() == false)
    }

    @Test
    func tripleAtExternalLabel() {
        #expect("@@@repo//foo:bar".isExternalBazelLabel() == true)
    }
}
