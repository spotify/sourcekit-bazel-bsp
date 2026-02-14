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

/// Executes a throwing operation with retry logic.
/// - Parameters:
///   - maxAttempts: Maximum number of attempts before giving up. Defaults to 3.
///   - onRetry: Optional callback invoked after each failed attempt with the attempt number and error.
///   - operation: The throwing operation to execute.
///   - delay: Optional delay between attempts. Defaults to nil.
/// - Returns: The result of the operation if successful.
/// - Throws: The last error if all attempts fail.
package func withRetry<T>(
    maxAttempts: Int = 3,
    onRetry: ((Int, Error) -> Void)? = nil,
    operation: () throws -> T,
    delay: TimeInterval? = nil
) throws -> T {
    for attempt in 1...maxAttempts {
        do {
            return try operation()
        } catch {
            onRetry?(attempt, error)
            if let delay = delay {
                Thread.sleep(forTimeInterval: delay)
            }
            if attempt == maxAttempts {
                throw error
            }
        }
    }
    fatalError("Unreachable")
}
