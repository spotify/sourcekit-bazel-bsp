#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lldb_build_common.sh"

echo "Starting launch task..."

function set_launch_info() {
  if [ "${BAZEL_PLATFORM_TYPE}" = "darwin" ]; then
    return
  fi

  # Read information regarding the user's selected device.
  # Format: UDID:deviceType (e.g., "12345678-1234-1234-1234-123456789012:physical")
  DEVICE_INFO_FILE=${WORKSPACE_ROOT}/.bsp/skbsp_generated/simulator_info.txt
  if [ -f "${DEVICE_INFO_FILE}" ]; then
    DEVICE_INFO_RAW=$(cat "${DEVICE_INFO_FILE}")
    DEVICE_INFO="${DEVICE_INFO_RAW%%:*}"
    DEVICE_TYPE="${DEVICE_INFO_RAW##*:}"
    echo "Will use device: ${DEVICE_INFO}"
  else
    emit_launcher_error "No device selected! You need to first run the 'Select Device for Apple Development' task before being able to run this script. You can find it in the 'SourceKit Bazel BSP' tab of the IDE."
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

# Determine if device is simulator or physical based on stored device type.
if [ "${DEVICE_TYPE}" = "physical" ]; then
    IS_PHYSICAL_DEVICE=true
else
    IS_PHYSICAL_DEVICE=false
fi

if [ "${BAZEL_RUN_MODE}" != "test" ]; then
    if [ "${IS_PHYSICAL_DEVICE}" = "true" ]; then
        # Physical device: use bazel run with device-specific flags and env vars
        ADDITIONAL_FLAGS+=("--ios_multi_cpus=arm64")
        ADDITIONAL_FLAGS+=("--platforms=@build_bazel_apple_support//platforms:ios_arm64")
        # Pass device ID via build setting (same as simulator)
        ADDITIONAL_FLAGS+=("--@${BAZEL_RULES_APPLE_NAME}//apple/build_settings:ios_device=${DEVICE_INFO}")

        if [ -n "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING}" ]; then
            DEVICECTL_LAUNCH_FLAGS="--console"
        else
            DEVICECTL_LAUNCH_FLAGS="--start-stopped"
        fi

        BAZEL_APPLE_DEVICE_UDID="${DEVICE_INFO}" \
        BAZEL_APPLE_LAUNCH_INFO_PATH="${LAUNCH_INFO_JSON}" \
        BAZEL_DEVICECTL_LAUNCH_FLAGS="${DEVICECTL_LAUNCH_FLAGS}" \
        run_bazel "${BAZEL_RUN_MODE}"
    else
        # Simulator or non-iOS platform
        if [ "${BAZEL_PLATFORM_TYPE}" = "ios" ]; then
            ADDITIONAL_FLAGS+=("--@${BAZEL_RULES_APPLE_NAME}//apple/build_settings:ios_device=${DEVICE_INFO}")
        fi

        if [ -n "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING}" ]; then
            SIMCTL_LAUNCH_FLAGS="--console-pty"
        else
            SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --console-pty"
        fi
        BAZEL_APPLE_SIMULATOR_UDID="${DEVICE_INFO}" \
        BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
        BAZEL_APPLE_LAUNCH_INFO_PATH="${LAUNCH_INFO_JSON}" \
        BAZEL_SIMCTL_LAUNCH_FLAGS="${SIMCTL_LAUNCH_FLAGS}" \
        run_bazel "${BAZEL_RUN_MODE}"
    fi
else
    # Test mode
    if [ -n "${BAZEL_TEST_FILTER:-}" ]; then
        ADDITIONAL_FLAGS+=("--test_filter=${BAZEL_TEST_FILTER}")
    fi

    if [ "${IS_PHYSICAL_DEVICE}" = "true" ]; then
        ADDITIONAL_FLAGS+=("--ios_multi_cpus=arm64")
        ADDITIONAL_FLAGS+=("--platforms=@build_bazel_apple_support//platforms:ios_arm64")
        ADDITIONAL_FLAGS+=("--test_arg=--destination=platform=iOS,id=${DEVICE_INFO}")
    else
        ADDITIONAL_FLAGS+=("--test_env=BAZEL_APPLE_SIMULATOR_UDID=${DEVICE_INFO}")
        if [ "${BAZEL_PLATFORM_TYPE}" = "ios" ] && [ "${BAZEL_SDK_NAME}" = "iphonesimulator" ]; then
            ADDITIONAL_FLAGS+=("--test_arg=--destination=platform=ios_simulator,id=${DEVICE_INFO}")
        fi
    fi

    # Debug mode: pass launch info path to test runner for debugger attachment,
    # and disable test caching so the test actually executes (otherwise bazel
    # serves a cached result and the test runner never runs).
    if [ -z "${BAZEL_APPLE_RUN_WITHOUT_DEBUGGING:-}" ] && [ -n "${LAUNCH_INFO_JSON:-}" ]; then
        ADDITIONAL_FLAGS+=("--test_env=BAZEL_APPLE_LAUNCH_INFO_PATH=${LAUNCH_INFO_JSON}")
        ADDITIONAL_FLAGS+=("--cache_test_results=no")
    fi

    ADDITIONAL_FLAGS+=("--test_env=BUILD_WORKSPACE_DIRECTORY=${WORKSPACE_ROOT}")
    ADDITIONAL_FLAGS+=("--local_test_jobs=1")
    run_bazel "${BAZEL_RUN_MODE}"
fi
