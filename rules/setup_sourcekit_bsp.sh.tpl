#!/bin/bash

set -euo pipefail

# Returns 0 (true) if target doesn't exist or differs from source
function needs_update() {
    local source="$1"
    local target="$2"
    ! [ -f "$target" ] || ! cmp -s "$source" "$target"
}

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

# Update the BSP config if needed
if needs_update "$bsp_config_path" "$target_bsp_config_path"; then
    cp "$bsp_config_path" "$target_bsp_config_path"
    chmod +w "$target_bsp_config_path"
fi

# Update the LSP config if needed
# For merging, we need to compare the merged result (not the source template)
if [ -f "$target_lsp_config_path" ] && command -v jq &> /dev/null; then
    jq -S -s '.[0] * .[1]' "$target_lsp_config_path" "$lsp_config_path" > "$target_lsp_config_path.tmp"
    if ! cmp -s "$target_lsp_config_path.tmp" "$target_lsp_config_path"; then
        mv "$target_lsp_config_path.tmp" "$target_lsp_config_path"
        chmod +w "$target_lsp_config_path"
    else
        rm -f "$target_lsp_config_path.tmp"
    fi
elif needs_update "$lsp_config_path" "$target_lsp_config_path"; then
    cp "$lsp_config_path" "$target_lsp_config_path"
    chmod +w "$target_lsp_config_path"
fi

# Update the BSP binary if needed
# Delete the existing binary first to avoid issues when running this while a server is running.
if needs_update "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"; then
    rm -f "$target_sourcekit_bazel_bsp_path" || true
    cp "$sourcekit_bazel_bsp_path" "$target_sourcekit_bazel_bsp_path"
    chmod +w "$target_sourcekit_bazel_bsp_path"
fi
