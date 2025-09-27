#!/bin/bash

set -euo pipefail

bsp_config_path="%bsp_config_path%"

bsp_folder_path="$BUILD_WORKSPACE_DIRECTORY/.bsp"

mkdir -p "$bsp_folder_path"

target_bsp_config_path="$bsp_folder_path/skbsp.json"

cp "$bsp_config_path" "$target_bsp_config_path"

chmod +w "$target_bsp_config_path"
