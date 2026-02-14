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

enum SafeIndexError: Error, LocalizedError {
    case indexOutOfBounds(Int, Int)

    var errorDescription: String? {
        switch self {
        case .indexOutOfBounds(let index, let line): return "Index \(index) is out of bounds for array at line \(line)"
        }
    }
}

extension Array {
    func getIndexThrowing(_ index: Int, _ line: Int = #line) throws -> Element {
        guard index < count else {
            throw SafeIndexError.indexOutOfBounds(index, line)
        }
        return self[index]
    }
}
