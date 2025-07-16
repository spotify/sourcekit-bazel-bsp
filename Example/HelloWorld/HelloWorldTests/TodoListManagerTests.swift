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

class TodoListManagerTests: XCTestCase {

    let fakeDefaults = UserDefaults(suiteName: "test")!

    override func tearDown() {
        super.tearDown()
        fakeDefaults.removeObject(forKey: "todo-items")
    }

    func testTodoListManagerInitialization() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        XCTAssertNotNil(manager)
        XCTAssertTrue(manager.todoItems.isEmpty)
    }

    func testAddTodoItem() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        let initialCount = manager.todoItems.count

        manager.addTodoItem(title: "New Task")

        XCTAssertEqual(manager.todoItems.count, initialCount + 1)
        XCTAssertEqual(manager.todoItems.last?.title, "New Task")
        XCTAssertFalse(manager.todoItems.last?.isCompleted ?? true)
    }

    func testToggleTodoItem() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        manager.addTodoItem(title: "Test Task")

        guard let item = manager.todoItems.first else {
            XCTFail("No item found")
            return
        }

        let initialCompletionStatus = item.isCompleted
        manager.toggleTodoItem(item)

        XCTAssertNotEqual(initialCompletionStatus, manager.todoItems.first?.isCompleted)
    }

    func testDeleteTodoItem() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        manager.addTodoItem(title: "Task to Delete")

        guard let item = manager.todoItems.first else {
            XCTFail("No item found")
            return
        }

        let initialCount = manager.todoItems.count
        manager.deleteTodoItem(item)

        XCTAssertEqual(manager.todoItems.count, initialCount - 1)
        XCTAssertFalse(manager.todoItems.contains { $0.id == item.id })
    }

    func testTodoListManagerPersistence() {
        let manager1 = TodoListManager(userDefaults: fakeDefaults)
        manager1.addTodoItem(title: "Persistent Task")

        let manager2 = TodoListManager(userDefaults: fakeDefaults)
        XCTAssertEqual(manager2.todoItems.count, 1)
        XCTAssertEqual(manager2.todoItems.first?.title, "Persistent Task")
    }

    func testMultipleTodoItems() {
        let manager = TodoListManager(userDefaults: fakeDefaults)

        manager.addTodoItem(title: "Task 1")
        manager.addTodoItem(title: "Task 2")
        manager.addTodoItem(title: "Task 3")

        XCTAssertEqual(manager.todoItems.count, 3)
        XCTAssertEqual(manager.todoItems[0].title, "Task 1")
        XCTAssertEqual(manager.todoItems[1].title, "Task 2")
        XCTAssertEqual(manager.todoItems[2].title, "Task 3")
    }

    func testToggleNonExistentItem() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        let fakeItem = TodoItem(title: "Fake Item")

        // Should not crash
        manager.toggleTodoItem(fakeItem)
        XCTAssertTrue(manager.todoItems.isEmpty)
    }

    func testDeleteNonExistentItem() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        let fakeItem = TodoItem(title: "Fake Item")

        // Should not crash
        manager.deleteTodoItem(fakeItem)
        XCTAssertTrue(manager.todoItems.isEmpty)
    }

    func testEmptyTitleHandling() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        manager.addTodoItem(title: "")

        XCTAssertEqual(manager.todoItems.count, 1)
        XCTAssertEqual(manager.todoItems.first?.title, "")
    }

    func testVeryLongTitle() {
        let manager = TodoListManager(userDefaults: fakeDefaults)
        let longTitle = String(repeating: "A", count: 1000)
        manager.addTodoItem(title: longTitle)

        XCTAssertEqual(manager.todoItems.count, 1)
        XCTAssertEqual(manager.todoItems.first?.title, longTitle)
    }

    func testTodoListManagerPerformance() {
        let manager = TodoListManager(userDefaults: fakeDefaults)

        measure {
            for i in 0..<100 {
                manager.addTodoItem(title: "Task \(i)")
            }
        }
    }
}
