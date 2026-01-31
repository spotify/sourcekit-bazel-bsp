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

interface Configuration {
    id: number;
    platform: String
    minimumOsVersion: String
    cpuArch: String
    sdkName: String
    dependencyBuildArgs: string[];
}

interface TopLevelTarget {
    label: string;
    launchType?: string;
    configId: number;
    testSources: string[] | undefined;
}

interface DependencyTarget {
    label: string;
    configId: number;
}

interface Graph {
    configurations: Configuration[];
    topLevelTargets: TopLevelTarget[];
    dependencyTargets: DependencyTarget[];
    bazelWrapper?: string;
}

export type TargetType = "app" | "test" | "library";

export interface ProcessedGraph {
    targets: ProcessedTarget[];
    fromGraphThatAlreadyExisted: boolean;
    bazelWrapper: string;
}

export interface ProcessedTarget {
    label: string;
    displayName: string;
    type: TargetType;
    extraBuildArgs: string[];
    canRun: boolean;
    canDebug: boolean;
    testSources: string[] | undefined;
    platform: string | undefined;
    sdkName: string | undefined;
}

function canRun(_platform: string | undefined, _sdkName: string | undefined): boolean {
    // if (platform == "darwin") {
    //     return true;
    // } else if (platform == "ios" && sdkName == "iphonesimulator") {
    //     return true;
    // }
    // return false;
    // FIXME: Not true for xctestrunner, but other test runners might
    // so allowing everything by default
    return true;
}

function canDebug(platform: string | undefined, sdkName: string | undefined, launchType: string | undefined): boolean {
    if (platform == "ios" && sdkName == "iphonesimulator") {
        return launchType == "app";
    }
    return false;
}

export async function processGraph(inputUri: vscode.Uri, appsToAlwaysInclude: string[] = [], alreadyExisted: boolean = false): Promise<ProcessedGraph> {
    const fileContents = await vscode.workspace.fs.readFile(inputUri);
    const graph: Graph = JSON.parse(Buffer.from(fileContents).toString("utf-8"));

    const configIdToConfiguration = new Map<number, Configuration>();
    for (const config of graph.configurations) {
        configIdToConfiguration.set(config.id, config);
    }

    const topLevelTargets: ProcessedTarget[] = graph.topLevelTargets.map((target) => {
        const config = configIdToConfiguration.get(target.configId);
        const platform = config?.platform?.toString();
        const sdkName = config?.sdkName?.toString();
        const launchType = target.launchType;
        const hasLaunchType = launchType !== undefined;
        return {
            label: target.label,
            displayName: target.label,
            type: (target.launchType as TargetType) ?? "app",
            extraBuildArgs: [],
            canRun: canRun(platform, sdkName) && hasLaunchType,
            canDebug: canDebug(platform, sdkName, launchType) && hasLaunchType,
            testSources: target.testSources,
            platform: config?.platform?.toString(),
            sdkName,
        };
    });

    const existingTopLevelLabels = new Set(graph.topLevelTargets.map((t) => t.label));
    for (const label of appsToAlwaysInclude) {
        if (!existingTopLevelLabels.has(label)) {
            topLevelTargets.push({
                label,
                displayName: label,
                type: "app",
                extraBuildArgs: [],
                canRun: true,
                canDebug: true,
                testSources: undefined,
                platform: undefined,
                sdkName: undefined,
            });
        }
    }

    const dependencyTargets: ProcessedTarget[] = graph.dependencyTargets.map((dep) => {
        const config = configIdToConfiguration.get(dep.configId);
        if (!config) {
            throw new Error("Configuration not found for dependency target: " + dep.label);
        }
        const platform = config.platform;
        const minimumOsVersion = config.minimumOsVersion;
        return {
            label: dep.label,
            displayName: dep.label + " (" + platform + "_" + minimumOsVersion + ")",
            type: "library" as TargetType,
            extraBuildArgs: config.dependencyBuildArgs,
            canRun: false,
            canDebug: false,
            testSources: undefined,
            platform: platform?.toString(),
            sdkName: config.sdkName?.toString(),
        };
    });

    const allTargets = [...topLevelTargets, ...dependencyTargets];
    allTargets.sort((a, b) => a.displayName.localeCompare(b.displayName));

    return {
        targets: allTargets,
        fromGraphThatAlreadyExisted: alreadyExisted,
        bazelWrapper: graph.bazelWrapper ?? "bazel",
    };
}
