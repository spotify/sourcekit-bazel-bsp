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
import LanguageServerProtocol
import Testing

@testable import SourceKitBazelBSP

@Suite
struct FileEventTests {
    private func makeFileEvent(path: String, type: FileChangeType) throws -> FileEvent {
        FileEvent(uri: try DocumentURI(string: "file://\(path)"), type: type)
    }

    @Test
    func emptyArrayReturnsEmpty() {
        let events: [FileEvent] = []
        #expect(events.cleaned().isEmpty)
    }

    @Test
    func singleEventDoesntRemoveEvents() throws {
        let events = [
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .created),
            try makeFileEvent(path: "/c.swift", type: .deleted),
            try makeFileEvent(path: "/d.swift", type: .created),
        ]
        let result = events.cleaned()
        #expect(
            result == [
                try makeFileEvent(path: "/a.swift", type: .created),
                try makeFileEvent(path: "/b.swift", type: .created),
                try makeFileEvent(path: "/c.swift", type: .deleted),
                try makeFileEvent(path: "/d.swift", type: .created),
            ]
        )
    }

    @Test
    func irrelevantDeleteAfterCreateIsIgnored() throws {
        let events = [
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .created),
            try makeFileEvent(path: "/c.swift", type: .deleted),
            try makeFileEvent(path: "/d.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .deleted),
        ]
        let result = events.cleaned()
        #expect(
            result == [
                try makeFileEvent(path: "/a.swift", type: .created),
                try makeFileEvent(path: "/c.swift", type: .deleted),
                try makeFileEvent(path: "/d.swift", type: .created),
            ]
        )
    }

    @Test
    func irrelevantCreateAfterDeleteIsIgnored() throws {
        let events = [
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .created),
            try makeFileEvent(path: "/c.swift", type: .deleted),
            try makeFileEvent(path: "/c.swift", type: .created),
            try makeFileEvent(path: "/d.swift", type: .created),
        ]
        let result = events.cleaned()
        #expect(
            result == [
                try makeFileEvent(path: "/a.swift", type: .created),
                try makeFileEvent(path: "/b.swift", type: .created),
                try makeFileEvent(path: "/d.swift", type: .created),
            ]
        )
    }

    @Test
    func duplicateEventsAreRemoved() throws {
        let events = [
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .created),
            try makeFileEvent(path: "/c.swift", type: .deleted),
            try makeFileEvent(path: "/d.swift", type: .created),
        ]
        let result = events.cleaned()
        #expect(
            result == [
                try makeFileEvent(path: "/a.swift", type: .created),
                try makeFileEvent(path: "/b.swift", type: .created),
                try makeFileEvent(path: "/c.swift", type: .deleted),
                try makeFileEvent(path: "/d.swift", type: .created),
            ]
        )
    }

    @Test
    func duplicateEventsAreRemoved2() throws {
        let events = [
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/b.swift", type: .created),
            try makeFileEvent(path: "/c.swift", type: .deleted),
            try makeFileEvent(path: "/d.swift", type: .created),
            try makeFileEvent(path: "/a.swift", type: .deleted),
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/a.swift", type: .created),
            try makeFileEvent(path: "/a.swift", type: .deleted),
        ]
        let result = events.cleaned()
        #expect(
            result == [
                try makeFileEvent(path: "/b.swift", type: .created),
                try makeFileEvent(path: "/c.swift", type: .deleted),
                try makeFileEvent(path: "/d.swift", type: .created),
            ]
        )
    }
}
