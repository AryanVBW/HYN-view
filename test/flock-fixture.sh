#!/usr/bin/env bash
# Supported Ubuntu hosts ship util-linux flock. Use the same kernel advisory
# lock from Python when running these persistence tests on a macOS workstation.
if ! command -v flock >/dev/null && command -v python3 >/dev/null; then
  flock() {
    python3 -c 'import fcntl, sys, time
deadline = time.monotonic() + (float(sys.argv[2]) if sys.argv[1] == "-w" else 0)
while True:
    try:
        fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline: sys.exit(1)
        time.sleep(.01)' "$@"
  }
  _HAVE[flock]=1
fi
