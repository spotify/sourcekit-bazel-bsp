import os
import signal

from lldb_common import load_launch_info

# The purpose of this script is to replicate Xcode's behavior of killing the app
# whenever the debug session is terminated. We fetch the same info used to launch the app
# to determine which process to kill.

launch_info = load_launch_info()
debug_pid = int(launch_info["pid"])
try:
    os.kill(debug_pid, signal.SIGKILL)
except Exception:
    pass
