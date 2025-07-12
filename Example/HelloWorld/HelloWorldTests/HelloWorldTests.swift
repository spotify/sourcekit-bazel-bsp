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

import XCTest
import TodoModels
import TodoObjCSupport

@testable import HelloWorldLib

class HelloWorldTests: XCTestCase {

    // MARK: - Integration Tests

    func testBasicIntegration() {
        // Test that all components work together
        let manager = TodoListManager()
        manager.addTodoItem(title: "Integration Test Task")

        guard let item = manager.todoItems.first else {
            XCTFail("No item found")
            return
        }

        // Test that the date distance calculator works with the todo item
        let distance = SKDateDistanceCalculator.distance(fromNow: item.createdAt)
        XCTAssertGreaterThanOrEqual(distance, 0)

        // Test that the human readable format works
        let readableDistance = SKDateDistanceCalculator.humanReadableDistance(fromNow: item.createdAt)
        XCTAssertNotNil(readableDistance)
    }

    func testEndToEndWorkflow() {
        let manager = TodoListManager()

        // Add a task
        manager.addTodoItem(title: "End to End Test")
        XCTAssertEqual(manager.todoItems.count, 1)

        // Toggle completion
        guard let item = manager.todoItems.first else {
            XCTFail("No item found")
            return
        }
        manager.toggleTodoItem(item)
        XCTAssertTrue(manager.todoItems.first?.isCompleted ?? false)

        // Delete the task
        manager.deleteTodoItem(item)
        XCTAssertEqual(manager.todoItems.count, 0)
    }
}
