#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lldb_build_common.sh"

echo "Starting launch task..."

function set_launch_info() {
  if [ "${BAZEL_PLATFORM_TYPE}" = "darwin" ]; then
    return
  fi

  # Read information regarding the user's selected simulator.
  SIMULATOR_INFO_FILE=${WORKSPACE_ROOT}/.bsp/skbsp_generated/simulator_info.txt
  if [ -f "${SIMULATOR_INFO_FILE}" ]; then
    SIMULATOR_INFO=$(cat "${SIMULATOR_INFO_FILE}")
    echo "Will use simulator: ${SIMULATOR_INFO}"
  else
    emit_launcher_error "No simulator selected! You need to first run the 'Select Simulator for Apple Development' task before being able to run this script. You can find it in the 'SourceKit Bazel BSP' tab of the IDE."
  fi

  if [ -n "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING}" ]; then
    return
  fi

  # When asking Bazel to launch a simulator, we need to intercept
  # the launched process' PID to be able to debug it later on.
  # We do this by asking it to write this info to a file.
  # These paths are also hardcoded in the lldb_attach.py and lldb_kill_app.py scripts.
  LAUNCH_INFO_JSON=${WORKSPACE_ROOT}/.bsp/skbsp_generated/lldb.json
  rm -f ${LAUNCH_INFO_JSON} || true
  OUTPUT_BASE=$($BAZEL_EXECUTABLE info output_base)
  EXECUTION_ROOT=$($BAZEL_EXECUTABLE info execution_root)
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

  # Remove the default lldbinit file created by rules_xcodeproj if it exists.
  # This prevents Xcode details from leaking over to our builds.
  # It's safe to delete this because rules_xcodeproj creates it on every build.
  RULES_XCODEPROJ_LLDBINIT_FILE=${HOME}/.lldbinit-rules_xcodeproj
  if [ -f "${RULES_XCODEPROJ_LLDBINIT_FILE}" ]; then
    echo "Removing rules_xcodeproj's lldbinit file..."
    rm -f "${RULES_XCODEPROJ_LLDBINIT_FILE}" || true
  fi
}

set_launch_info

if [ "${BAZEL_RUN_MODE}" != "test" ]; then
    if [ "${BAZEL_PLATFORM_TYPE}" = "ios" ]; then
        ADDITIONAL_FLAGS+=("--@${BAZEL_RULES_APPLE_NAME}//apple/build_settings:ios_device=${SIMULATOR_INFO}")
    fi
    if [ -n "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING}" ]; then
        SIMCTL_LAUNCH_FLAGS="--console-pty"
    else
        SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --console-pty"
    fi
    BAZEL_APPLE_SIMULATOR_UDID="${SIMULATOR_INFO}" \
    BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
    BAZEL_APPLE_LAUNCH_INFO_PATH="${LAUNCH_INFO_JSON}" \
    BAZEL_SIMCTL_LAUNCH_FLAGS="${SIMCTL_LAUNCH_FLAGS}" \
    run_bazel "${BAZEL_RUN_MODE}"
else
    if [ -n "${BAZEL_TEST_FILTER:-}" ]; then
        BAZEL_TEST_FILTER_ARG="--test_filter=${BAZEL_TEST_FILTER}"
        ADDITIONAL_FLAGS+=("${BAZEL_TEST_FILTER_ARG}")
    fi
    ADDITIONAL_FLAGS+=("--test_env=BAZEL_APPLE_SIMULATOR_UDID=${SIMULATOR_INFO}")
    ADDITIONAL_FLAGS+=("--test_env=BUILD_WORKSPACE_DIRECTORY=${WORKSPACE_ROOT}")
    ADDITIONAL_FLAGS+=("--local_test_jobs=1")
    if [ "${BAZEL_PLATFORM_TYPE}" = "ios" ]; then
        if [ "${BAZEL_SDK_NAME}" = "iphonesimulator" ]; then
            ADDITIONAL_FLAGS+=("--test_arg=--destination=platform=ios_simulator,id=${SIMULATOR_INFO}")
        fi
    fi
    run_bazel "${BAZEL_RUN_MODE}"
fi
