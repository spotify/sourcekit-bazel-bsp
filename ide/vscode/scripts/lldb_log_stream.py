"""Streams the attached iOS simulator app's unified log (os_log) into LLDB's
stdout, which lldb-dap forwards to VSCode's Debug Console."""

import atexit
import subprocess
import sys

_PREDICATE = 'NOT subsystem BEGINSWITH "com.apple"'

_stream_proc = None


def _terminate() -> None:
    global _stream_proc
    if _stream_proc is not None:
        try:
            _stream_proc.terminate()
        except Exception:
            pass
        _stream_proc = None


def start(udid: str, pid: str) -> None:
    """Start the log stream subprocess for the given simulator/pid."""
    global _stream_proc
    sys.stdout.flush()
    _stream_proc = subprocess.Popen(
        [
            "xcrun", "simctl", "spawn", udid,
            "log", "stream",
            "--level=debug",
            "--style=compact",
            "--predicate", f"processIdentifier == {pid} AND ({_PREDICATE})",
        ],
        stdout=sys.stdout.fileno(),
        stderr=subprocess.STDOUT,
    )
    atexit.register(_terminate)
    print(f"[skbsp] Streaming os_log for pid {pid}", flush=True)
