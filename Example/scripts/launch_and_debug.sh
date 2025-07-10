#!/bin/zsh

set -e

# We don't use bazelisk run because it does a bunch of things we don't want in this case.
# Instead, we have our own script for launching the simulator and lldb.
# Ideally we should upstream these changes back to rules_apple since they should be useful for everyone.

echo "Building..."
bazelisk build //HelloWorld
chmod -R 777 ./bazel-bin/HelloWorld

tmp_file=$(pwd)/bazel-bin/HelloWorld/pid.txt
rm ${tmp_file} > /dev/null 2>&1 || true
touch ${tmp_file}
cp ./scripts/HelloWorld ./bazel-bin/HelloWorld/HelloWorld

pushd ./bazel-bin
python3 ./HelloWorld/HelloWorld --wait-for-debugger --stdout=$(tty) --stderr=$(tty) > ${tmp_file}
popd

# Get pid from the tmp_file
echo "$(cat "${tmp_file}" | awk -F': ' '{print $2}')" > ${tmp_file}
# Ugly hack to remove the newline from the file
pid=$(tr -d '\n' < ${tmp_file})
echo "Launched app's pid: ${pid}"

xcode_path=$(xcode-select -p)
debugserver_path="${xcode_path}/../SharedFrameworks/LLDB.framework/Versions/A/Resources/debugserver"

# Just for sanity, kill any other debugservers that might be running
pgrep -lfa Resources/debugserver | awk '{print $1}' | xargs kill -9

# Launch the debugserver. The output of this command will signal the IDE to launch the lldb extension,
# which is hardcoded to connect to port 6667.
${debugserver_path} "localhost:6667" --attach ${pid}

# Kill the app when debugging ends, just like in Xcode.
kill -9 ${pid} > /dev/null 2>&1 || true