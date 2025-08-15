#!/bin/bash

set -euo pipefail

sourcekit_bazel_bsp_path="%sourcekit_bazel_bsp_path%"
bsp_config_path="%bsp_config_path%"

cp "${bsp_config_path}" "$BUILD_WORKSPACE_DIRECTORY/.bsp/config.json"
ln -sf "${sourcekit_bazel_bsp_path}" "$BUILD_WORKSPACE_DIRECTORY/.bsp/sourcekit-bazel-bsp"
