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

#import "HelloWorld/TodoObjCSupport/Sources/SKObjCUtils.h"
#import "HelloWorld/TodoCSupport/include/SKCUtils.h"

@implementation SKObjCUtils

+ (NSString *)greetingFromC {
    const char *cGreeting = sk_c_get_greeting();
    return [NSString stringWithUTF8String:cGreeting];
}

+ (NSInteger)multiplyWithC:(NSInteger)a b:(NSInteger)b {
    return sk_c_multiply((int)a, (int)b);
}

@end
