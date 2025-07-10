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

#import "HelloWorld/ObjCDep/Sources/ObjCType.h"

@interface SomeObjCType ()

@property(nonatomic, strong) UITableView *otherTableView;
@property(nonatomic, strong) NSArray *otherData;

@end

@implementation SomeObjCType

- (void)viewDidLoad {
  _otherTableView = [[UITableView alloc] initWithFrame:self.view.frame];
  _otherData = @[ @"Hello", @"World" ];
  [super viewDidLoad];
  self.data = @[ @"Hello", @"World" ];
  self.tableView = [[UITableView alloc] initWithFrame:self.view.frame];
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  [self.view addSubview:self.tableView];
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  return self.data.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                reuseIdentifier:@"cell"];
}

@end