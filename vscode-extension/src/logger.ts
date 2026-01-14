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

import * as vscode from "vscode";

let extensionChannel: vscode.OutputChannel | undefined;
let serverChannel: vscode.OutputChannel | undefined;

export interface LogChannels {
    extension: vscode.OutputChannel;
    server: vscode.OutputChannel;
}

export function initLogger(): LogChannels {
    extensionChannel = vscode.window.createOutputChannel(
        "SourceKit Bazel BSP (Extension)"
    );
    serverChannel = vscode.window.createOutputChannel(
        "SourceKit Bazel BSP (Server)"
    );
    return {
        extension: extensionChannel,
        server: serverChannel,
    };
}

export function getExtensionChannel(): vscode.OutputChannel | undefined {
    return extensionChannel;
}

export function getServerChannel(): vscode.OutputChannel | undefined {
    return serverChannel;
}

export function log(message: string) {
    extensionChannel?.appendLine(message);
}
