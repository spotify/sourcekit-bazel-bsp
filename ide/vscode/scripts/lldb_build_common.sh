#!/bin/bash

# Stores common functionality for build and launch tasks.

set -e

export SIMULATOR_INFO
SIMULATOR_INFO=""
export LAUNCH_INFO_JSON
LAUNCH_INFO_JSON=""
export WORKSPACE_ROOT
WORKSPACE_ROOT=$(pwd)

export ADDITIONAL_FLAGS
ADDITIONAL_FLAGS=()

if [ -n "${BAZEL_EXTRA_BUILD_FLAGS:-}" ]; then
  read -ra BAZEL_EXTRA_BUILD_FLAGS_ARRAY <<< "$BAZEL_EXTRA_BUILD_FLAGS"
  ADDITIONAL_FLAGS+=("${BAZEL_EXTRA_BUILD_FLAGS_ARRAY[@]}")
fi

if [ -n "${BAZEL_BEP_FILE:-}" ]; then
  mkdir -p "$(dirname "${BAZEL_BEP_FILE}")"
  : > "${BAZEL_BEP_FILE}"
  ADDITIONAL_FLAGS+=("--build_event_json_file=${BAZEL_BEP_FILE}")
fi

LAUNCH_ARGS_ARRAY=()
if [ -n "${BAZEL_LAUNCH_ARGS:-}" ]; then
  read -ra LAUNCH_ARGS_ARRAY <<< "$BAZEL_LAUNCH_ARGS"
fi

function emit_launcher_error() {
  echo -e "\033[0;31mlauncher_error in ${BASH_SOURCE[0]}: ${1}\033[0m"
  exit 1
}

function run_bazel() {
  local command="$1"
  $BAZEL_EXECUTABLE "${command}" "${BAZEL_LABEL_TO_RUN}" "${ADDITIONAL_FLAGS[@]}" ${LAUNCH_ARGS_ARRAY[@]:+-- "${LAUNCH_ARGS_ARRAY[@]}"}
}
