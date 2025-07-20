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
import SwiftUI

public final class TodoListManager: ObservableObject {
    @Published
    public var todoItems: [TodoItem] = []

    private let userDefaults: UserDefaults
    private let todoItemsKey = "todo-items"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadTodoItems()
    }

    public func addTodoItem(title: String) {
        let newItem = TodoItem(title: title)
        todoItems.append(newItem)
        saveTodoItems()
    }

    public func toggleTodoItem(_ item: TodoItem) {
        if let index = todoItems.firstIndex(where: { $0.id == item.id }) {
            todoItems[index].isCompleted.toggle()
            saveTodoItems()
        }
    }

    public func deleteTodoItem(_ item: TodoItem) {
        todoItems.removeAll { $0.id == item.id }
        saveTodoItems()
    }

    private func saveTodoItems() {
        if let encoded = try? JSONEncoder().encode(todoItems) {
            userDefaults.set(encoded, forKey: todoItemsKey)
        }
    }

    private func loadTodoItems() {
        if let data = userDefaults.data(forKey: todoItemsKey),
            let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        {
            todoItems = decoded
        }
    }
}
