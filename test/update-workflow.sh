#!/usr/bin/env bash
# hyn-view :: self-update workflow check
#
#   bash test/update-workflow.sh
#
# This covers the one path that cannot be allowed to rot.
#
# A monitored box is configured once and then nobody logs into it again. Every
# future fix reaches it through exactly one mechanism: the agent notices a newer
# release on the npm registry and installs it. If that mechanism breaks, the box
# is stranded on whatever version it happens to be running, and no later release
# can rescue it -- because the code that would do the rescuing is the code that is
# broken.
#
# So this drives the REAL update functions -- update_check_now, update_apply,
# update_refresh_services -- against a mock registry over real HTTP, with only
# `npm` and `systemctl` stubbed. It asserts the whole sequence and, just as
# importantly, that a failed or partial install is reported as a failure rather
# than silently treated as success.
#
# Needs python3 for the mock registry. No network.

set -uo pipefail

HERE=$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)
ROOT=$(cd -P "$HERE/.." && pwd)

PASS=0 FAIL=0
declare -a FAILURES=()
ok() { ((PASS++)); }
bad() { ((FAIL++)); FAILURES+=("$1"); printf '  FAIL  %s\n' "$1" >&2; }
eq() { if [[ $2 == "$3" ]]; then ok; else bad "$1: expected [$2] got [$3]"; fi; }
contains() { if [[ $3 == *"$2"* ]]; then ok; else bad "$1: [${3:0:200}] lacks [$2]"; fi; }
missing() { if [[ $3 != *"$2"* ]]; then ok; else bad "$1: [${3:0:200}] must not contain [$2]"; fi; }
truthy() { if eval "$2" >/dev/null 2>&1; then ok; else bad "$1: expected success from: $2"; fi; }
falsy() { if eval "$2" >/dev/null 2>&1; then bad "$1: expected failure from: $2"; else ok; fi; }

command -v python3 >/dev/null || { printf 'update-workflow: python3 not found, skipping\n'; exit 0; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/hyn-upd.XXXXXX") || exit 1
trap 'rm -rf "$TMP"; [[ -n ${SRV_PID:-} ]] && kill "$SRV_PID" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# a mock npm registry
# ---------------------------------------------------------------------------
# Serves the same shape registry.npmjs.org does for the abbreviated metadata
# document the agent asks for, so the real parser is exercised rather than a
# fixture of what we hope it returns.
PORT=54331
cat >"$TMP/registry.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = sys.argv[2]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith("/set/"):
            open(STATE, "w").write(self.path.rsplit("/", 1)[-1])
            self.send_response(200); self.send_header("Content-Length", "2")
            self.end_headers(); self.wfile.write(b"ok"); return
        latest = open(STATE).read().strip() if os.path.exists(STATE) else "1.9.0"
        if latest == "BROKEN":
            self.send_response(500); self.end_headers(); return
        if latest == "GARBAGE":
            body = b'{"name":"hyn-view","dist-tags":{"latest":"not-a-version"}}'
        else:
            body = json.dumps({
                "name": "hyn-view",
                "dist-tags": {"latest": latest},
                "versions": {latest: {"name": "hyn-view", "version": latest}},
            }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.npm.install-v1+json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
printf '1.9.0\n' >"$TMP/latest"
python3 "$TMP/registry.py" "$PORT" "$TMP/latest" &
SRV_PID=$!
for _ in $(seq 1 40); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/hyn-view" && break
  sleep 0.25
done

printf 'self-update workflow\n'

# ---------------------------------------------------------------------------
# load the agent
# ---------------------------------------------------------------------------
export HYN_ETC="$TMP/etc" HYN_VAR="$TMP/var" HYN_UNIT_DIR="$TMP/units"
export HYN_PROC="$TMP/proc" HYN_SYS="$TMP/sys"
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" XDG_STATE_HOME="$TMP/xdgstate"
export HYN_CONFIG=''
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_UNIT_DIR" "$HYN_PROC" "$HYN_SYS" \
         "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT"
export TERM=dumb
for m in core notify update; do
  # shellcheck source=/dev/null
  source "$HYN_LIB/$m.sh" || { printf 'cannot source %s\n' "$m" >&2; exit 1; }
done
cfg_load

# Point the real checker at the mock. This is a variable precisely so it can be
# aimed somewhere else in a test.
UPD_REGISTRY="http://127.0.0.1:$PORT"

# ---------------------------------------------------------------------------
# noticing a new release
# ---------------------------------------------------------------------------
HYN_VERSION=1.8.0
truthy 'the registry check succeeds'      'update_check_now'
eq     'it reads dist-tags.latest'  '1.9.0' "$UPD_LATEST"
eq     'and sees an update is available' 1 "$UPD_AVAILABLE"
truthy 'the result is cached for the UI' '[[ -s $(update_cache_file) ]]'

# The cache must survive a process that cannot reach the registry, so a launch
# during an outage still shows what it last knew instead of nothing.
UPD_LATEST='' UPD_AVAILABLE=0
truthy 'a cached answer is readable without the network' 'update_read'
eq     'the cached version is the one served' '1.9.0' "$UPD_LATEST"

# Same major, higher minor across the 9 -> 10 boundary: the case a string compare
# gets wrong, which would silently strand every box at 1.9.x for ever.
curl -s "http://127.0.0.1:$PORT/set/1.10.0" >/dev/null
HYN_VERSION=1.9.0
update_check_now >/dev/null
eq 'a 1.10 release is newer than 1.9'  1 "$UPD_AVAILABLE"
eq 'and is reported as the target' '1.10.0' "$UPD_LATEST"

# Already current: must not install, and must not claim an update exists.
HYN_VERSION=1.10.0
update_check_now >/dev/null
eq 'being current is not an update' 0 "$UPD_AVAILABLE"

# A registry that is down or lying must fail closed -- never install something
# unparsed, never report a bogus version as available.
curl -s "http://127.0.0.1:$PORT/set/BROKEN" >/dev/null
falsy  'a 500 from the registry fails the check' 'update_check_now 2>/dev/null'
contains 'and says the registry was unreachable' 'could not reach' "$UPD_LAST_ERR"
curl -s "http://127.0.0.1:$PORT/set/GARBAGE" >/dev/null
falsy  'a non-version string is refused' 'update_check_now 2>/dev/null'
contains 'and is named as a bad version' 'bad version' "$UPD_LAST_ERR"

# ---------------------------------------------------------------------------
# installing it
# ---------------------------------------------------------------------------
# npm and systemctl are the only stubs. Everything else is the real code path a
# box will take, including `hyn setup` rewriting its own units.
curl -s "http://127.0.0.1:$PORT/set/1.9.0" >/dev/null
HYN_VERSION=1.8.0
update_check_now >/dev/null

# Logged to files, not arrays: update_refresh_services reads `systemctl is-active`
# through a command substitution, which runs in a subshell, so an array would
# silently lose exactly the calls this test cares most about proving.
NPM_LOG=$TMP/npm.log SYSCTL_LOG=$TMP/systemctl.log
: >"$NPM_LOG"; : >"$SYSCTL_LOG"
NPM_RESULT=0
npm() { printf '%s\n' "$*" >>"$NPM_LOG"; return "$NPM_RESULT"; }
SYSCTL_ACTIVE=active
systemctl() {
  printf '%s\n' "$*" >>"$SYSCTL_LOG"
  case $1 in
    is-enabled) return 0 ;;
    is-active) printf '%s\n' "$SYSCTL_ACTIVE"; return 0 ;;
  esac
  return 0
}
_HAVE[npm]=1 _HAVE[systemctl]=1
is_root() { return 0; }
# The install is detected by where the code lives; pretend to be an npm global.
HYN_ROOT="$TMP/node_modules/hyn-view"
mkdir -p "$HYN_ROOT/bin"
# Stands in for the newly installed CLI: it reports the version npm "installed".
cat >"$HYN_ROOT/bin/hyn" <<EOS
#!/usr/bin/env bash
case \${1:-} in
  --version) printf 'hyn-view %s\n' "\$(cat "$TMP/installed")" ;;
  setup) printf 'setup ran\n' >>"$TMP/setup.log" ;;
esac
exit 0
EOS
chmod +x "$HYN_ROOT/bin/hyn"
printf '1.9.0\n' >"$TMP/installed"

truthy 'the update applies' 'update_apply 0'
eq 'the running version becomes the installed one' '1.9.0' "$HYN_VERSION"
eq 'and no update is outstanding afterwards' 0 "$UPD_AVAILABLE"
contains 'npm was asked for the exact version' 'install -g hyn-view@1.9.0' "$(<"$NPM_LOG")"
truthy  'setup was reapplied so units and config are migrated' '[[ -s $TMP/setup.log ]]'
contains 'systemd was reloaded' 'daemon-reload' "$(<"$SYSCTL_LOG")"
# Every managed timer is restarted so a changed schedule takes effect, and each is
# then verified as active rather than assumed.
for u in hyn-speedtest.timer hyn-record.timer hyn-alerts.timer hyn-report.timer hyn-push.timer; do
  contains "restarted $u" "restart $u" "$(<"$SYSCTL_LOG")"
  contains "verified $u"  "is-active $u" "$(<"$SYSCTL_LOG")"
done
# Nothing that is not ours may be touched, however the update goes.
missing 'no Highway unit was touched'  'hway'   "$(<"$SYSCTL_LOG")"
missing 'no Nebula unit was touched'   'nebula' "$(<"$SYSCTL_LOG")"
missing 'no glob was ever used'        '*'      "$(<"$SYSCTL_LOG")"

# ---------------------------------------------------------------------------
# failing safely
# ---------------------------------------------------------------------------
# The install must fail loudly. A box that reports success while running the old
# code is worse than one that reports failure, because the portal then shows a
# version that is not what is running.
HYN_VERSION=1.8.0
update_check_now >/dev/null
NPM_RESULT=1
: >"$NPM_LOG"
falsy    'a failed npm install is a failed update' 'update_apply 0 2>/dev/null'
contains 'and says nothing was changed' 'nothing was changed' "$UPD_LAST_ERR"
eq       'the running version is unchanged' '1.8.0' "$HYN_VERSION"

# npm succeeds but installs the wrong thing: caught by verifying afterwards.
NPM_RESULT=0
printf '1.8.0\n' >"$TMP/installed"
HYN_VERSION=1.8.0
update_check_now >/dev/null
falsy    'installing the wrong version is caught' 'update_apply 0 2>/dev/null'
contains 'and both versions are named' 'expected 1.9.0 but found 1.8.0' "$UPD_LAST_ERR"

# A timer that will not come back is a failure too: the package is new but the
# box has stopped monitoring, which is the state that must never be silent.
printf '1.9.0\n' >"$TMP/installed"
HYN_VERSION=1.8.0
update_check_now >/dev/null
SYSCTL_ACTIVE=failed
falsy    'a timer that does not come back fails the update' 'update_apply 0 2>/dev/null'
contains 'and the dead timer is named' 'after restart' "$UPD_LAST_ERR"

# ---------------------------------------------------------------------------
# the policy that decides whether any of this happens unattended
# ---------------------------------------------------------------------------
CFG[auto_update]=off
UPD_STATE=''
update_startup
eq 'auto_update=off installs nothing' '' "$UPD_STATE"
CFG[auto_update]=check
UPD_STATE=''
_UPD_PID=0
update_startup
missing 'auto_update=check never installs' 'installing' "$UPD_STATE"

# ---------------------------------------------------------------------------
# the route in, on a box nobody logs into
# ---------------------------------------------------------------------------
# update_startup used to be reached only from an interactive launch and from the
# portal check-in. An installed-but-unpaired machine therefore never looked for a
# release again, and there is no second mechanism that could reach it. The record
# timer is the only one enabled unconditionally, so the check belongs there too.
truthy 'the record job also checks for updates' \
  'grep -A9 "^    record)" "$ROOT/bin/hyn" | grep  update_startup'
truthy 'the record timer is enabled unconditionally' \
  'grep  "_toggle_timer hyn-record.timer 1" "$HYN_LIB/setup.sh"'
# ...and doctor must say so when the policy would stop it anyway.
truthy 'doctor reports the update policy' \
  'grep  "update policy" "$ROOT/bin/hyn"'
truthy 'doctor calls out a policy that never installs' \
  'grep  "will NOT install fixes by itself" "$ROOT/bin/hyn"'

printf '\n'
if ((FAIL == 0)); then
  printf '%d checks passed\n' "$PASS"
  exit 0
fi
printf '%d passed, %d FAILED\n' "$PASS" "$FAIL"
printf '\nfailures:\n'
for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
exit 1
