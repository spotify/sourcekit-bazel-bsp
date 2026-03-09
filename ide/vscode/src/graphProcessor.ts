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
    mnemonic: string;
    platform: String
    minimumOsVersion: String
    cpuArch: String
    sdkName: String
    /** Build invocation template for aspect-based builds */
    buildInvocation: string;
}

interface TopLevelTarget {
    label: string;
    launchType?: string;
    configMnemonic: string;
    testSources: string[] | undefined;
}

interface DependencyTarget {
    label: string;
    configMnemonic: string;
    /** The top-level parent to build through for aspect-based builds */
    topLevelParent: string;
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
        return launchType == "app" || launchType == "test";
    }
    return false;
}

export async function processGraph(inputUri: vscode.Uri, appsToAlwaysInclude: string[] = [], alreadyExisted: boolean = false): Promise<ProcessedGraph> {
    const fileContents = await vscode.workspace.fs.readFile(inputUri);
    const graph: Graph = JSON.parse(Buffer.from(fileContents).toString("utf-8"));

    const configMnemonicToConfiguration = new Map<string, Configuration>();
    for (const config of graph.configurations) {
        configMnemonicToConfiguration.set(config.mnemonic, config);
    }

    const topLevelTargets: ProcessedTarget[] = graph.topLevelTargets.map((target) => {
        const config = configMnemonicToConfiguration.get(target.configMnemonic);
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
        const config = configMnemonicToConfiguration.get(dep.configMnemonic);
        if (!config) {
            throw new Error("Configuration not found for dependency target: " + dep.label);
        }
        const platform = config.platform;
        const minimumOsVersion = config.minimumOsVersion;

        // Sanitize label for output group: //path/to:Target -> aspect_path_to_Target
        let sanitized = dep.label;
        if (sanitized.startsWith("//")) {
            sanitized = sanitized.substring(2);
        }
        sanitized = "aspect_" + sanitized
            .replace(/\//g, "_")
            .replace(/:/g, "_")
            .replace(/-/g, "_")
            .replace(/\./g, "_");

        // Build through parent using aspect approach
        const extraBuildArgs = [
            "--aspects=//.bsp/skbsp_generated:aspect.bzl%platform_deps_aspect",
            "--output_groups=" + sanitized
        ];

        return {
            label: dep.topLevelParent,
            displayName: dep.label + " (" + platform + "_" + minimumOsVersion + ")",
            type: "library" as TargetType,
            extraBuildArgs: extraBuildArgs,
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
