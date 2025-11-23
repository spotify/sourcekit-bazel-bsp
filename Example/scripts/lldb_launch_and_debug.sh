#!/bin/bash

set -e

echo "Building ${BAZEL_LABEL_TO_RUN}..."

WORKSPACE_ROOT=$(pwd)

# When asking Bazel to launch a simulator, we need to intercept
# the launched process' PID to be able to debug it later on.
# We do this by asking it to write this info to a file.
# These two paths are also hardcoded in the lldb_attach.py and lldb_kill_app.py scripts.
INFO_JSON=${WORKSPACE_ROOT}/.bsp/skbsp_generated/lldb.json
rm -f ${INFO_JSON} || true
OUTPUT_BASE=$(bazelisk info output_base)
OUTPUT_BASE_INFO_PATH=${WORKSPACE_ROOT}/.bsp/skbsp_generated/output_base.txt
rm -f ${OUTPUT_BASE_INFO_PATH} || true
mkdir -p ${WORKSPACE_ROOT}/.bsp/skbsp_generated
echo "${OUTPUT_BASE}" > ${OUTPUT_BASE_INFO_PATH}

# FIXME: Could not figure out how to make the output show up on the dedicated
# debug console. So we need to keep this script alive and display it here in the meantime.
BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
BAZEL_APPLE_LAUNCH_INFO_PATH=${INFO_JSON} \
BAZEL_SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --stdout=$(tty) --stderr=$(tty)" \
bazelisk run "${BAZEL_LABEL_TO_RUN}"

PID=$(jq -r '.pid' "${INFO_JSON}")

echo "Launched with PID: ${PID}"

# Keep the terminal alive until the app is killed.
# FIXME: Only necessary because of the stdout-related FIXME mentioned above
lsof -p ${PID} +r 1 &>/dev/null
