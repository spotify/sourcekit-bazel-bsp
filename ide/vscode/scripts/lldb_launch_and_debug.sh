#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lldb_build_common.sh"

echo "Starting launch task..."

set_launch_info

if [ -n "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING}" ]; then
    SIMCTL_LAUNCH_FLAGS="--console-pty"
else
    SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --console-pty"
fi

if [ -n "${BAZEL_TEST_FILTER:-}" ]; then
    BAZEL_TEST_FILTER_ARG="--test_filter='${BAZEL_TEST_FILTER}'"
    ADDITIONAL_FLAGS+=("${BAZEL_TEST_FILTER_ARG}")
fi

if [ "${BAZEL_RUN_MODE}" = "test" ]; then
    ADDITIONAL_FLAGS+=("--local_test_jobs=1")
fi

BAZEL_APPLE_SIMULATOR_UDID="${SIMULATOR_INFO}" \
BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
BAZEL_APPLE_LAUNCH_INFO_PATH="${LAUNCH_INFO_JSON}" \
BAZEL_SIMCTL_LAUNCH_FLAGS="${SIMCTL_LAUNCH_FLAGS}" \
run_bazel "${BAZEL_RUN_MODE}"
