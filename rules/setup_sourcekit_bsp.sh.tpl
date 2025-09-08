#!/bin/bash

set -euo pipefail

sourcekit_bazel_bsp_path="%sourcekit_bazel_bsp_path%"
bsp_config_path="%bsp_config_path%"

mkdir -p "$BUILD_WORKSPACE_DIRECTORY/.bsp"

cp "${bsp_config_path}" "$BUILD_WORKSPACE_DIRECTORY/.bsp/config.json"
cp "${sourcekit_bazel_bsp_path}" "$BUILD_WORKSPACE_DIRECTORY/.bsp/sourcekit-bazel-bsp"

chmod +w "$BUILD_WORKSPACE_DIRECTORY/.bsp/config.json"
chmod +w "$BUILD_WORKSPACE_DIRECTORY/.bsp/sourcekit-bazel-bsp"
