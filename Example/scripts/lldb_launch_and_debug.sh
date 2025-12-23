#!/bin/bash

source "scripts/lldb_build_common.sh"

echo "Starting launch task..."

function emit_launcher_error() {
  echo "launcher_error in ${BASH_SOURCE[0]}: ${1}"
  exit 1
}

# Read information regarding the user's selected simulator.
SIMULATOR_INFO_FILE=${WORKSPACE_ROOT}/.bsp/skbsp_generated/simulator_info.txt
SIMULATOR_INFO=""
if [ -f "${SIMULATOR_INFO_FILE}" ]; then
  SIMULATOR_INFO=$(cat "${SIMULATOR_INFO_FILE}")
  echo "Will use simulator: ${SIMULATOR_INFO}"
else
  emit_launcher_error "No simulator selected! You need to first run the 'Select Simulator for Apple Development' task before being able to run this script."
fi

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

# We need --remote_download_regex because the files that lldb needs won't usually be downloaded by Bazel
# when using flags like --remote_download_toplevel and the such.
ADDITIONAL_FLAGS+=("--remote_download_regex=.*\.indexstore/.*|.*\.(a|cfg|c|C|cc|cl|cpp|cu|cxx|c++|def|h|H|hh|hpp|hxx|h++|hmap|ilc|inc|inl|ipp|tcc|tlh|tli|tpp|m|modulemap|mm|pch|swift|swiftdoc|swiftmodule|swiftsourceinfo|yaml)$")
ADDITIONAL_FLAGS+=("--@build_bazel_rules_apple//apple/build_settings:ios_device=${SIMULATOR_INFO}")

# Remove the default lldbinit file created by rules_xcodeproj if it exists.
# This prevents Xcode details from leaking over to our builds.
# It's safe to delete this because rules_xcodeproj creates it on every build.
RULES_XCODEPROJ_LLDBINIT_FILE=${HOME}/.lldbinit-rules_xcodeproj
if [ -f "${RULES_XCODEPROJ_LLDBINIT_FILE}" ]; then
  echo "Removing rules_xcodeproj's lldbinit file..."
  rm -f "${RULES_XCODEPROJ_LLDBINIT_FILE}" || true
fi

BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
BAZEL_APPLE_LAUNCH_INFO_PATH="${LAUNCH_INFO_JSON}" \
BAZEL_SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --console-pty" \
run_bazel "run"