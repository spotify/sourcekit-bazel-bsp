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

#import "HelloWorld/TodoObjCSupport/Sources/SKDateDistanceCalculator.h"

@implementation SKDateDistanceCalculator

+ (NSTimeInterval)distanceFromNow:(NSDate *)date {
  if (!date) {
    return 0.0;
  }

  NSDate *now = [NSDate date];
  return [now timeIntervalSinceDate:date];
}

+ (NSString *)humanReadableDistanceFromNow:(NSDate *)date {
  if (!date) {
    return @"Invalid date";
  }

  NSTimeInterval timeInterval = [self distanceFromNow:date];
  BOOL isPast = timeInterval > 0;

  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *components =
      [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth |
                           NSCalendarUnitDay | NSCalendarUnitHour |
                           NSCalendarUnitMinute | NSCalendarUnitSecond
                  fromDate:isPast ? date : [NSDate date]
                    toDate:isPast ? [NSDate date] : date
                   options:0];

  NSString *suffix = isPast ? @"ago" : @"from now";

  if (components.year > 0) {
    return
        [NSString stringWithFormat:@"%ld year%@ %@", (long)components.year,
                                   components.year == 1 ? @"" : @"s", suffix];
  } else if (components.month > 0) {
    return
        [NSString stringWithFormat:@"%ld month%@ %@", (long)components.month,
                                   components.month == 1 ? @"" : @"s", suffix];
  } else if (components.day > 0) {
    return [NSString stringWithFormat:@"%ld day%@ %@", (long)components.day,
                                      components.day == 1 ? @"" : @"s", suffix];
  } else if (components.hour > 0) {
    return
        [NSString stringWithFormat:@"%ld hour%@ %@", (long)components.hour,
                                   components.hour == 1 ? @"" : @"s", suffix];
  } else if (components.minute > 0) {
    return
        [NSString stringWithFormat:@"%ld minute%@ %@", (long)components.minute,
                                   components.minute == 1 ? @"" : @"s", suffix];
  } else {
    return
        [NSString stringWithFormat:@"%ld second%@ %@", (long)components.second,
                                   components.second == 1 ? @"" : @"s", suffix];
  }
}

+ (NSInteger)distanceFromNow:(NSDate *)date inUnit:(NSCalendarUnit)unit {
  if (!date) {
    return 0;
  }

  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *components = [calendar components:unit
                                             fromDate:date
                                               toDate:[NSDate date]
                                              options:0];

  switch (unit) {
  case NSCalendarUnitYear:
    return components.year;
  case NSCalendarUnitMonth:
    return components.month;
  case NSCalendarUnitDay:
    return components.day;
  case NSCalendarUnitHour:
    return components.hour;
  case NSCalendarUnitMinute:
    return components.minute;
  case NSCalendarUnitSecond:
    return components.second;
  default:
    return 0;
  }
}

@end
