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

import Testing

@testable import SourceKitBazelBSP

@Suite
struct LabelBuildPriorityTests {
    @Test
    func emptySequence_returnsNil() {
        let items: [(String, TopLevelRuleType)] = []
        #expect(items.labelWithHighestBuildPriority() == nil)
    }

    @Test
    func singleElement_returnsThatLabel() {
        let items: [(String, TopLevelRuleType)] = [
            ("//app:MyApp", .iosUnitTest)
        ]
        #expect(items.labelWithHighestBuildPriority() == "//app:MyApp")
    }
    @Test
    func prefersApp() {
        let items: [(String, TopLevelRuleType)] = [
            ("//test:UnitTest", .iosUnitTest),
            ("//ext:Extension", .iosExtension),
            ("//app:MyApp", .iosApplication),
            ("//test:BuildTest", .iosBuildTest),
            ("//clip:AppClip", .iosAppClip),
        ]
        #expect(items.labelWithHighestBuildPriority() == "//app:MyApp")
    }

    @Test
    func picksFirstWhenMultipleMaxPrio() {
        let items: [(String, TopLevelRuleType)] = [
            ("//test:UnitTest", .iosUnitTest),
            ("//ext:Extension", .iosExtension),
            ("//app:MyApp", .iosApplication),
            ("//test:BuildTest", .iosBuildTest),
            ("//app:MyOtherApp", .iosApplication),
            ("//clip:AppClip", .iosAppClip),
        ]
        #expect(items.labelWithHighestBuildPriority() == "//app:MyApp")
    }
}
