#!/bin/bash

set -euo pipefail

sourcekit_bazel_bsp_path="%sourcekit_bazel_bsp_path%"
bsp_config_path="%bsp_config_path%"
lsp_config_path="%lsp_config_path%"

bsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.bsp"
lsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.sourcekit-lsp"

mkdir -p "$bsp_folder_path"
mkdir -p "$lsp_folder_path"

target_bsp_config_path="$bsp_folder_path/skbsp.json"
target_sourcekit_bazel_bsp_path="$bsp_folder_path/sourcekit-bazel-bsp"
target_lsp_config_path="$lsp_folder_path/config.json"

cp "$bsp_config_path" "$target_bsp_config_path"
cp "$lsp_config_path" "$target_lsp_config_path"

# Delete the existing binary first to avoid issues when running this while a server is running.
rm -f "$target_sourcekit_bazel_bsp_path" || true
cp "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"

chmod +w "$target_bsp_config_path"
chmod +w "$target_sourcekit_bazel_bsp_path"
chmod +w "$target_lsp_config_path"
