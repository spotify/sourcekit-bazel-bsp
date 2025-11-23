
from lldb_common import load_launch_info, load_output_base, run_command

launch_info = load_launch_info()
output_base = load_output_base()
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

if device_platform == "device":
    run_command(f"device select {device_udid}")
else:
    run_command(f"platform select {device_platform}")
    run_command(f"platform connect {device_udid}")

if device_platform == "device":
    run_command(f"device process attach --pid {debug_pid}")
else:
    run_command(f"process attach --pid {debug_pid}")
