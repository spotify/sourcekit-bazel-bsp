from lldb_common import load_launch_info, load_bazel_info, run_command, load_additional_lldb_commands
import os

launch_info = load_launch_info()
bazel_info = load_bazel_info()
output_base = bazel_info["output_base"]
execution_root = bazel_info["execution_root"]
workspace_root = os.getcwd()
device_platform = launch_info["platform"]
device_udid = launch_info["udid"]
debug_pid = str(launch_info["pid"])

# Set `CWD` to the Bazel execution root so relative paths in binaries work.
#
# This is needed because we use the `oso_prefix_is_pwd` feature, which makes the
# paths to archives relative to the exec root.
run_command(
    f'platform settings -w "{execution_root}"',
)

# Adjust the source map.
#
# By default, breakpoints will move the IDE to the file within the execution root.
# We need to map them to their real location in the workspace root to fix that.
# The only exception is the the `external` folder, which only exists within the execution root.
run_command(
    'settings append target.source-map "." "{}"'.format(workspace_root),
)
run_command(
    'settings insert-before target.source-map 0 "./external/" '
    f'"{output_base}/external/"',
)

# Helps lldb to not timeout on large projects
run_command(
    'settings set plugin.process.gdb-remote.packet-timeout 300',
)

# Execute additional LLDB commands before attaching
for cmd in load_additional_lldb_commands():
    run_command(cmd)

if device_platform == "device":
    # For physical devices, select the device using CoreDevice ID
    # This may fail if lldb-dap already selected it, which is fine
    try:
        run_command(f"device select {device_udid}")
    except RuntimeError:
        # Device already selected by lldb-dap, continue
        print(f"Device {device_udid} already selected", flush=True)
    run_command(f"device process attach --pid {debug_pid}")
else:
    # For simulators
    run_command(f"platform select {device_platform}")
    run_command(f"platform connect {device_udid}")
    run_command(f"process attach --pid {debug_pid}")
