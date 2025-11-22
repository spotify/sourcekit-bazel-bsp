import json
import os
import pathlib
import sys
import lldb

def run_command(command: str) -> None:
    print(f"(lldb) {command}", flush=True)
    result = lldb.SBCommandReturnObject()
    lldb.debugger.GetCommandInterpreter().HandleCommand(command, result)
    if result.Succeeded():
        output = result.GetOutput()
        if output:
            print(output, flush=True)
    else:
        output = result.GetError()
        if output:
            print(output, file=sys.stderr, flush=True)
        msg = "Command failed. See above for any error messages."
        raise RuntimeError(msg)

launch_info_path = pathlib.Path("/tmp/lldb-bridge/launch_info")

# We check for existence of `launch_info_path` as a way to not throw a bunch of
# errors when the `preLaunchTask` fails. Ideally we wouldn't get here, but
# `lldb-dap` has a bug where background tasks don't prevent debugging from
# starting.
if not launch_info_path.exists():
    print("Launch info file not found. Exiting.", file=sys.stderr, flush=True)
    lldb.SBDebugger.Terminate()
    os._exit(0)

# Load in all of variables.
output_base = pathlib.Path("/tmp/lldb-bridge/output_base").read_text().strip()
launch_info = json.loads(launch_info_path.read_text())
device_platform = launch_info["platform"]
device_udid = launch_info["udid"]
debug_pid = str(launch_info["pid"])

# Set `CWD` to the Bazel execution root so relative paths in binaries work.
#
# This is needed because we use the `oso_prefix_is_pwd` feature, which makes the
# paths to archives relative to the exec root.
run_command(
    f'platform settings -w "{output_base}/execroot/_main"',
)

# Adjust the source map.
#
# The source map will be initialized to the workspace. Need to resolve external
# paths to the stable external directory. Then need to resolve generated files
# to the execution root. We set it for `./` instead of `./bazel-out/` to allow
# the convenience symlink to be used if it exists.
run_command(
    'settings insert-before target.source-map 0 "./external/" '
    f'"{output_base}/external/"',
)
run_command(
    f'settings append target.source-map "./" "{output_base}/execroot/_main/"',
)
