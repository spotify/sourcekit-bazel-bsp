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
import TodoObjCSupport

struct TodoItemRow: View {
    let item: TodoItem
    let todoManager: TodoListManager

    var body: some View {
        HStack {
            Button(action: {
                todoManager.toggleTodoItem(item)
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundColor(item.isCompleted ? .gray : .primary)
                    .animation(.easeInOut(duration: 0.2), value: item.isCompleted)

                Text(SKDateDistanceCalculator.humanReadableDistance(fromNow: item.createdAt))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
