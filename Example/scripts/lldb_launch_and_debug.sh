#!/bin/bash

set -e

echo "Building ${BAZEL_LABEL_TO_RUN}..."

WORKSPACE_ROOT=$(pwd)

# When asking Bazel to launch a simulator, we need to intercept
# the launched process' PID to be able to debug it later on.
# We do this by asking it to write this info to a file.
# These paths are also hardcoded in the lldb_attach.py and lldb_kill_app.py scripts.
LAUNCH_INFO_JSON=${WORKSPACE_ROOT}/.bsp/skbsp_generated/lldb.json
rm -f ${LAUNCH_INFO_JSON} || true
OUTPUT_BASE=$(bazelisk info output_base)
EXECUTION_ROOT=$(bazelisk info execution_root)
BAZEL_INFO_JSON=${WORKSPACE_ROOT}/.bsp/skbsp_generated/bazel_info.json
rm -f ${BAZEL_INFO_JSON} || true
mkdir -p ${WORKSPACE_ROOT}/.bsp/skbsp_generated
cat > ${BAZEL_INFO_JSON} <<EOF
{
  "output_base": "${OUTPUT_BASE}",
  "execution_root": "${EXECUTION_ROOT}"
}
EOF

ADDITIONAL_FLAGS=()
ADDITIONAL_FLAGS+=("--keep_going")
ADDITIONAL_FLAGS+=("--color=yes")
# We need --remote_download_regex because the files that lldb needs won't usually be downloaded by Bazel
# when using flags like --remote_download_toplevel and the such.
ADDITIONAL_FLAGS+=("--remote_download_regex=.*\.indexstore/.*|.*\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$")

BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
BAZEL_APPLE_LAUNCH_INFO_PATH=${LAUNCH_INFO_JSON} \
BAZEL_SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --stdout=$(tty) --stderr=$(tty)" \
bazelisk run "${BAZEL_LABEL_TO_RUN}" "${ADDITIONAL_FLAGS[@]}"

PID=$(jq -r '.pid' "${LAUNCH_INFO_JSON}")

echo "Launched with PID: ${PID}"

# Keep the terminal alive until the app is killed.
# FIXME: This is only necessary because I couldn't figure out how to make the app's output
# show up on the dedicated debug console. So we need to keep this script alive and
# display it here in the meantime.
lsof -p ${PID} +r 1 &>/dev/null
