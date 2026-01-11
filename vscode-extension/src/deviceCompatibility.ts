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
import { Device, Target } from "./types";

/**
 * Parses a version string like "17.2" or "18.0" into a comparable number.
 * Returns [major, minor] tuple.
 */
function parseVersion(version: string): [number, number] {
    const parts = version.split(".").map((p) => parseInt(p, 10) || 0);
    return [parts[0] || 0, parts[1] || 0];
}

/**
 * Compares two version tuples. Returns:
 * - negative if a < b
 * - 0 if a == b
 * - positive if a > b
 */
function compareVersions(a: [number, number], b: [number, number]): number {
    if (a[0] !== b[0]) {
        return a[0] - b[0];
    }
    return a[1] - b[1];
}

/**
 * Extracts the platform type from a device runtime string.
 * e.g., "iOS 17.2" -> "ios", "watchOS 10.0" -> "watchos"
 */
function getDevicePlatformType(runtime: string): string {
    const match = runtime.match(/^(\w+)\s+/);
    if (match) {
        return match[1].toLowerCase();
    }
    return runtime.toLowerCase();
}

/**
 * Extracts the OS version from a device runtime string.
 * e.g., "iOS 17.2" -> "17.2"
 */
function getDeviceOsVersion(runtime: string): string {
    const match = runtime.match(/[\d.]+/);
    return match ? match[0] : "0.0";
}

/**
 * Maps target platform strings to device platform types.
 * Target platforms from Bazel are like "ios", "watchos", "darwin", "tvos", etc.
 */
function targetPlatformToDevicePlatform(targetPlatform: string): string | undefined {
    const platform = targetPlatform.toLowerCase();

    // Map Bazel platform names to device runtime platform names
    if (platform === "ios") {
        return "ios";
    }
    if (platform === "watchos") {
        return "watchos";
    }
    if (platform === "darwin" || platform === "macos") {
        return "macos";
    }
    if (platform === "tvos") {
        return "tvos";
    }
    if (platform === "visionos" || platform === "xros") {
        return "visionos";
    }

    return undefined;
}

/**
 * Checks if a device is compatible with a target.
 */
export function isDeviceCompatible(device: Device, target: Target): boolean {
    // If target has no platform info, assume compatible
    if (!target.platform) {
        return true;
    }

    const expectedPlatform = targetPlatformToDevicePlatform(target.platform);
    if (!expectedPlatform) {
        // Unknown platform, assume compatible
        return true;
    }

    const devicePlatformType = getDevicePlatformType(device.runtime);

    // Check platform type matches
    if (devicePlatformType !== expectedPlatform) {
        return false;
    }

    // For now, BSP only builds for simulators, so only allow simulators
    // (except for macOS which doesn't have simulators)
    if (expectedPlatform !== "macos" && device.isPhysical) {
        return false;
    }

    // Check minimum OS version
    if (target.minimumOsVersion) {
        const deviceVersion = parseVersion(getDeviceOsVersion(device.runtime));
        const minVersion = parseVersion(target.minimumOsVersion);

        if (compareVersions(deviceVersion, minVersion) < 0) {
            return false;
        }
    }

    return true;
}

/**
 * Filters devices to only those compatible with the target.
 */
export function getCompatibleDevices(
    devices: Device[],
    target: Target
): Device[] {
    return devices.filter((device) => isDeviceCompatible(device, target));
}

/**
 * Shows a quick pick to select a compatible device.
 * Returns the selected device or undefined if cancelled.
 */
export async function showCompatibleDevicePicker(
    compatibleDevices: Device[],
    target: Target
): Promise<Device | undefined> {
    if (compatibleDevices.length === 0) {
        const platformInfo = target.platform ? ` (${target.platform})` : "";
        const minOsInfo = target.minimumOsVersion
            ? `, min OS ${target.minimumOsVersion}`
            : "";

        vscode.window.showErrorMessage(
            `No compatible devices found for target${platformInfo}${minOsInfo}. ` +
                "Please install a compatible simulator or connect a compatible device."
        );
        return undefined;
    }

    const items = compatibleDevices.map((device) => ({
        label: device.name,
        description: device.runtime,
        detail: device.isPhysical ? "Physical Device" : "Simulator",
        device,
    }));

    const platformInfo = target.platform ? ` (${target.platform})` : "";

    const selected = await vscode.window.showQuickPick(items, {
        placeHolder: `Select a compatible device for ${target.label}${platformInfo}`,
        title: "Device Selection Required",
    });

    return selected?.device;
}
