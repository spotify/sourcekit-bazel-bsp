#!/bin/bash

set -euo pipefail

sourcekit_bazel_bsp_path="%sourcekit_bazel_bsp_path%"
bsp_config_path="%bsp_config_path%"

bsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.bsp"

mkdir -p "$bsp_folder_path"

target_bsp_config_path="$bsp_folder_path/config.json"
target_sourcekit_bazel_bsp_path="$bsp_folder_path/sourcekit-bazel-bsp"

cp "$bsp_config_path" "$target_bsp_config_path"
cp "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"

chmod +w "$target_bsp_config_path"
chmod +w "$target_sourcekit_bazel_bsp_path"
