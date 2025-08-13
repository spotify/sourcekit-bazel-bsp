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

import TodoModels
import XCTest

@testable import HelloWorldLib

class TodoItemTests: XCTestCase {

    func testTodoItemInitialization() {
        let title = "Test Task"
        let item = TodoItem(title: title)

        XCTAssertEqual(item.title, title)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNotNil(item.id)
        XCTAssertNotNil(item.createdAt)
    }

    func testTodoItemInitializationWithCompletionStatus() {
        let title = "Completed Task"
        let item = TodoItem(title: title, isCompleted: true)

        XCTAssertEqual(item.title, title)
        XCTAssertTrue(item.isCompleted)
    }

    func testTodoItemCodable() {
        let originalItem = TodoItem(title: "Test Task", isCompleted: true)

        do {
            let data = try JSONEncoder().encode(originalItem)
            let decodedItem = try JSONDecoder().decode(TodoItem.self, from: data)

            XCTAssertEqual(originalItem.title, decodedItem.title)
            XCTAssertEqual(originalItem.isCompleted, decodedItem.isCompleted)
            XCTAssertEqual(originalItem.id, decodedItem.id)
        } catch {
            XCTFail("Failed to encode/decode TodoItem: \(error)")
        }
    }

    func testTodoItemiOSOnlyContent() {
        XCTAssertEqual(TodoItem.iOSOnlyContent(), "iOS only content")
    }
}
