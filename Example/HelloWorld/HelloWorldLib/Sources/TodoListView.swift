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

import SwiftUI
import TodoModels

struct TodoListView: View {
    @StateObject
    private var todoManager = TodoListManager()
    @State
    private var showingAddTodo = false

    var body: some View {
        NavigationView {
            VStack {
                if todoManager.todoItems.isEmpty {
                    EmptyView()
                } else {
                    List {
                        ForEach(todoManager.todoItems) { item in
                            TodoItemRow(item: item, todoManager: todoManager)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("My Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddTodo = true
                    }) {
                        Image(systemName: "plus").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddTodo) {
                AddTodoView(todoManager: todoManager, isPresented: $showingAddTodo)
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            todoManager.deleteTodoItem(todoManager.todoItems[index])
        }
    }
}

struct EmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No tasks yet!")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.gray)

            Text("Tap the + button to add your first task.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
