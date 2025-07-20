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

struct AddTodoView: View {

    @ObservedObject
    var todoManager: TodoListManager
    @Binding
    var isPresented: Bool
    @State
    private var todoTitle = ""
    @FocusState
    private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)

                    Text("Add New Task")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Enter the details for your new task below")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Task Title")
                        .font(.headline)
                        .foregroundColor(.primary)

                    TextField("Enter task title...", text: $todoTitle, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .padding(.horizontal)
                }
                .padding(.horizontal)

                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: addTask) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Task")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.gray
                                : Color.blue
                        )
                        .cornerRadius(12)
                    }
                    .disabled(todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal)

                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                }

                Spacer()
            }
            .navigationBarHidden(true)
            .onAppear {
                isTextFieldFocused = true
            }
            .onSubmit {
                addTask()
            }
        }
    }

    private func addTask() {
        let trimmedTitle = todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        todoManager.addTodoItem(title: trimmedTitle)
        todoTitle = ""
        isPresented = false
    }
}
