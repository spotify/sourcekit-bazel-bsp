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
import Testing

@testable import SourceKitBazelBSP

@Suite
struct RetryTests {
    enum TestError: Error {
        case simulated
    }

    @Test
    func succeedsOnFirstAttempt() throws {
        var attemptCount = 0
        let result = try withRetry {
            attemptCount += 1
            return "success"
        }

        #expect(result == "success")
        #expect(attemptCount == 1)
    }

    @Test
    func succeedsAfterRetries() throws {
        var attemptCount = 0
        let result = try withRetry {
            attemptCount += 1
            if attemptCount < 3 {
                throw TestError.simulated
            }
            return "success"
        }

        #expect(result == "success")
        #expect(attemptCount == 3)
    }

    @Test
    func failsAfterMaxAttempts() throws {
        var attemptCount = 0
        #expect(throws: TestError.self) {
            try withRetry(maxAttempts: 3) {
                attemptCount += 1
                throw TestError.simulated
            }
        }

        #expect(attemptCount == 3)
    }

    @Test
    func callsOnRetryCallback() throws {
        var retryAttempts: [Int] = []
        #expect(throws: TestError.self) {
            try withRetry(
                maxAttempts: 3,
                onRetry: { attempt, _ in
                    retryAttempts.append(attempt)
                },
                operation: {
                    throw TestError.simulated
                }
            )
        }

        #expect(retryAttempts == [1, 2, 3])
    }

    @Test
    func respectsCustomMaxAttempts() throws {
        var attemptCount = 0
        #expect(throws: TestError.self) {
            try withRetry(maxAttempts: 5) {
                attemptCount += 1
                throw TestError.simulated
            }
        }

        #expect(attemptCount == 5)
    }
}
