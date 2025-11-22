#!/bin/zsh

set -e

# When asking Bazel to launch a simulator, we need to intercept
# the launched process' PID to be able to debug it later on.
# We do this by asking it to write this info to a file.
# These two paths are also hardcoded in the lldb_inject_settings.py script.
pid_json=/tmp/lldb-bridge/launch_info
output_base_path=/tmp/lldb-bridge/output_base

rm ${pid_json} > /dev/null 2>&1 || true
rm ${output_base_path} > /dev/null 2>&1 || true

# lldb_inject_settings.py reads this to to run some necessary lldb commands in advance.
bazelisk info output_base > ${output_base_path}

BAZEL_APPLE_PREFER_PERSISTENT_SIMS=1 \
BAZEL_APPLE_LAUNCH_INFO_PATH=${pid_json} \
BAZEL_SIMCTL_LAUNCH_FLAGS="--wait-for-debugger --stdout=$(tty) --stderr=$(tty)" \
bazelisk run //HelloWorld:HelloWorld

pid=$(jq -r '.pid' "${pid_json}")

xcode_path=$(xcode-select -p)
debugserver_path="${xcode_path}/../SharedFrameworks/LLDB.framework/Versions/A/Resources/debugserver"

# Just for sanity, kill any other debugservers that might be running
pgrep -lfa Resources/debugserver | awk '{print $1}' | xargs kill -9

# Launch the debugserver. The output of this command will signal the IDE to launch the lldb extension,
# which is hardcoded to connect to port 6667.
${debugserver_path} "localhost:6667" --attach ${pid}

# Kill the app when debugging ends, just like in Xcode.
kill -9 ${pid} > /dev/null 2>&1 || true