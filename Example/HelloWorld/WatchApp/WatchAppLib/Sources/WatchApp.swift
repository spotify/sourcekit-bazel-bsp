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

@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup {
            TestView()
        }
    }
}

struct TestView: View {
    @State
    private var items: [TodoItem] = [
        TodoItem(title: "Buy milk"),
        TodoItem(title: "Walk the dog"),
        TodoItem(title: "Read a book"),
    ]

    var body: some View {
        List {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    Image(systemName: items[index].isCompleted ? "checkmark.circle.fill" : "circle")
                        .onTapGesture {
                            items[index].isCompleted.toggle()
                        }
                    Text(items[index].title)
                        .strikethrough(items[index].isCompleted)
                }
            }
        }
        .navigationTitle("Todo List")
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}
