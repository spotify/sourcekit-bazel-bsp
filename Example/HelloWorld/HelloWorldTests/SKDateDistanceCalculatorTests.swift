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
import TodoObjCSupport

@testable import HelloWorldLib

class SKDateDistanceCalculatorTests: XCTestCase {

    func testDistanceFromNowWithNilDate() {
        let distance = SKDateDistanceCalculator.distance(fromNow: nil)
        XCTAssertEqual(distance, 0.0)
    }

    func testDistanceFromNowWithPastDate() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let distance = SKDateDistanceCalculator.distance(fromNow: pastDate)
        XCTAssertGreaterThan(distance, 0)
        XCTAssertEqual(distance, 3600, accuracy: 1.0) // Allow 1 second tolerance
    }

    func testDistanceFromNowWithFutureDate() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let distance = SKDateDistanceCalculator.distance(fromNow: futureDate)
        XCTAssertLessThan(distance, 0)
        XCTAssertEqual(distance, -3600, accuracy: 1.0) // Allow 1 second tolerance
    }

    func testHumanReadableDistanceFromNowWithNilDate() {
        let result = SKDateDistanceCalculator.humanReadableDistance(fromNow: nil)
        XCTAssertEqual(result, "Invalid date")
    }

    func testHumanReadableDistanceFromNowWithPastDate() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let result = SKDateDistanceCalculator.humanReadableDistance(fromNow: pastDate)
        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertTrue(result.contains("hour"))
            XCTAssertTrue(result.contains("ago"))
        }
    }

    func testHumanReadableDistanceFromNowWithFutureDate() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let result = SKDateDistanceCalculator.humanReadableDistance(fromNow: futureDate)
        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertTrue(result.contains("hour"))
            XCTAssertTrue(result.contains("from now"))
        }
    }

    func testDistanceFromNowInUnitWithNilDate() {
        let result = SKDateDistanceCalculator.distance(fromNow: nil, in: .hour)
        XCTAssertEqual(result, 0)
    }

    func testDistanceFromNowInUnitWithPastDate() {
        let pastDate = Date().addingTimeInterval(-7200) // 2 hours ago
        let result = SKDateDistanceCalculator.distance(fromNow: pastDate, in: .hour)
        XCTAssertEqual(result, 2)
    }

    func testDistanceFromNowInUnitWithFutureDate() {
        let futureDate = Date().addingTimeInterval(7200) // 2 hours from now
        let result = SKDateDistanceCalculator.distance(fromNow: futureDate, in: .hour)
        XCTAssertEqual(result, -2)
    }

    func testDateDistanceCalculationPerformance() {
        let testDate = Date().addingTimeInterval(-86400) // 1 day ago

        measure {
            for _ in 0..<1000 {
                _ = SKDateDistanceCalculator.humanReadableDistance(fromNow: testDate)
            }
        }
    }
}