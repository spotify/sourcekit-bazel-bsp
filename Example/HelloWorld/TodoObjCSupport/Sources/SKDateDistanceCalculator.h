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

#import <Foundation/Foundation.h>

@interface SKDateDistanceCalculator : NSObject

/**
 * Calculates the time interval between the given date and now
 * @param date The reference date to calculate distance from
 * @return Time interval in seconds (positive if date is in the past, negative
 * if in the future)
 */
+ (NSTimeInterval)distanceFromNow:(NSDate *)date;

/**
 * Calculates the distance and returns a human-readable string
 * @param date The reference date to calculate distance from
 * @return A formatted string describing the time distance (e.g., "2 days ago",
 * "3 hours from now")
 */
+ (NSString *)humanReadableDistanceFromNow:(NSDate *)date;

/**
 * Calculates the distance in specific units
 * @param date The reference date to calculate distance from
 * @param unit The calendar unit to measure in (e.g., NSCalendarUnitDay,
 * NSCalendarUnitHour)
 * @return The distance in the specified unit
 */
+ (NSInteger)distanceFromNow:(NSDate *)date inUnit:(NSCalendarUnit)unit;

@end
