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
cat >"$TMP/registry.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = sys.argv[1]

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

server = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[2], "w") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
PY
printf '1.9.0\n' >"$TMP/latest"
python3 "$TMP/registry.py" "$TMP/latest" "$TMP/port" &
SRV_PID=$!
for _ in $(seq 1 40); do
  [[ -s $TMP/port ]] && break
  sleep 0.25
done
[[ -s $TMP/port ]] || { printf 'mock registry failed to start\n' >&2; exit 1; }
PORT=$(<"$TMP/port")

printf 'self-update workflow\n'

# ---------------------------------------------------------------------------
# load the agent
# ---------------------------------------------------------------------------
export HYN_ETC="$TMP/etc" HYN_VAR="$TMP/var" HYN_UNIT_DIR="$TMP/units"
export HYN_PROC="$TMP/proc" HYN_SYS="$TMP/sys"
export XDG_CONFIG_HOME="$TMP/xdg" XDG_STATE_HOME="$TMP/xdgstate"
export HYN_CONFIG=''
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_UNIT_DIR" "$HYN_PROC" "$HYN_SYS" \
         "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT"
export TERM=dumb
for m in core notify update; do
  # shellcheck source=/dev/null
  source "$HYN_LIB/$m.sh" || { printf 'cannot source %s\n' "$m" >&2; exit 1; }
done
cfg_load
# Exercise an actual advisory lock on macOS as well as Ubuntu, without adding
# a runtime dependency to the Linux CLI.
if ! command -v flock >/dev/null; then
  flock() {
    python3 - "$@" <<'PY'
import fcntl, sys
try:
    fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(1)
PY
  }
  _HAVE[flock]=1
fi

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
falsy 'invalid leading-zero versions are rejected by the registry parser' \
  '_upd_parse_latest '\''{"dist-tags":{"latest":"1.09.0"}}'\'''

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

UPD_AVAILABLE=1
falsy 'a failed registry check clears an old install decision' 'update_check_now 2>/dev/null'
eq 'no stale install is available after the failed check' 0 "$UPD_AVAILABLE"
truthy 'only dist-tags.latest selects a release' \
  '_upd_parse_latest '\''{"latest":"8.0.0","dist-tags":{"latest":"1.9.0"}}'\'' && [[ $UPD_PARSED == 1.9.0 ]]'
falsy 'a latest key outside dist-tags is not a release' \
  '_upd_parse_latest '\''{"versions":{"latest":"8.0.0"}}'\'''
falsy 'an unrelated dist-tags value is not a release' \
  '_upd_parse_latest '\''{"dist-tags":null,"latest":"8.0.0"}'\'''

curl -s "http://127.0.0.1:$PORT/set/1.9.0" >/dev/null
CFG[auto_update]=check
_update_cache_write "$((EPOCHSECONDS + 86400))" 1.0.0
_UPD_PID=0
update_check_async
truthy 'a future cache timestamp does not suppress checking' '((_UPD_PID > 0))'
((_UPD_PID == 0)) || wait "$_UPD_PID"
update_read
eq 'a corrected clock refreshes the cached release' 1.9.0 "$UPD_LATEST"

_update_cache_write "$EPOCHSECONDS" 'not-a-version'
falsy 'a corrupt cached release is rejected' 'update_read'
eq 'a corrupt cache cannot trigger an install' 0 "$UPD_AVAILABLE"
eq 'a corrupt cache is immediately eligible for rechecking' 0 "$UPD_CHECKED"

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
npm() {
  printf '%s\n' "$*" >>"$NPM_LOG"
  if ((NPM_RESULT)); then
    # Model the npm failure that matters: the old package was already removed.
    rm -rf "$HYN_ROOT"
    rm -f "$TMP/npm/bin/hyn" "$TMP/npm/bin/hyn-view"
    return "$NPM_RESULT"
  fi
  cp "$TMP/installed" "$HYN_ROOT/VERSION"
  cp "$TMP/cli-template" "$HYN_ROOT/bin/hyn"
  [[ ${NPM_BAD_CLI:-0} == 0 ]] || printf '\nexit 9\n' >>"$HYN_ROOT/bin/hyn"
  return 0
}
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
HYN_ROOT="$TMP/npm/lib/node_modules/hyn-view"
mkdir -p "$HYN_ROOT/bin"
mkdir -p "$TMP/npm/bin"
ln -s ../lib/node_modules/hyn-view/bin/hyn "$TMP/npm/bin/hyn"
ln -s ../lib/node_modules/hyn-view/bin/hyn "$TMP/npm/bin/hyn-view"
# Stands in for the newly installed CLI: it reports the version npm "installed".
cat >"$TMP/cli-template" <<EOS
#!/usr/bin/env bash
version=\$(cat "\${BASH_SOURCE[0]%/bin/hyn}/VERSION")
case \${1:-} in
  --version) printf 'hyn-view %s\nCopyright HYN-view contributors\n' "\$version" ;;
  setup)
    printf 'setup %s\n' "\$version" >>"$TMP/setup.log"
    if [[ \$version == 1.9.0 && -f "$TMP/setup-fail" ]]; then exit 1; fi
    ;;
esac
EOS
chmod +x "$TMP/cli-template"
cp "$TMP/cli-template" "$HYN_ROOT/bin/hyn"
printf '1.8.0\n' >"$HYN_ROOT/VERSION"
printf '1.9.0\n' >"$TMP/installed"

# Lock coverage uses two real processes sharing the kernel lock. No package
# mutation is permitted while another updater owns it.
(
  state_dir_v
  exec {held_fd}>"$STATE_DIR/update.lock"
  flock -n "$held_fd" || exit 1
  touch "$TMP/lock-held"
  while [[ ! -e $TMP/release-lock ]]; do sleep .02; done
) &
LOCK_PID=$!
for _ in {1..100}; do [[ -f $TMP/lock-held ]] && break; sleep .02; done
falsy 'a concurrent package update is refused' 'update_apply 0'
contains 'contention reports the active installer' 'already running' "$UPD_LAST_ERR"
truthy 'a contended install does not invoke npm' '[[ ! -s $NPM_LOG ]]'
touch "$TMP/release-lock"
wait "$LOCK_PID"
_HAVE[flock]=0
falsy 'an unavailable lock tool cannot silently disable locking' 'update_apply 0'
contains 'missing locking support explains the prerequisite' 'flock is required' "$UPD_LAST_ERR"
_HAVE[flock]=1

truthy 'the update applies' 'update_apply 0'
eq 'the running version becomes the installed one' '1.9.0' "$HYN_VERSION"
eq 'and no update is outstanding afterwards' 0 "$UPD_AVAILABLE"
contains 'npm was asked for the exact version' 'install -g hyn-view@1.9.0' "$(<"$NPM_LOG")"
contains 'npm updates the prefix containing this CLI' "--prefix $TMP/npm" "$(<"$NPM_LOG")"
contains 'npm uses the same registry as the checked version' "--registry $UPD_REGISTRY" "$(<"$NPM_LOG")"
contains 'setup is deferred until after package verification' '--ignore-scripts' "$(<"$NPM_LOG")"
truthy  'setup was reapplied so units and config are migrated' '[[ -s $TMP/setup.log ]]'
contains 'systemd was reloaded' 'daemon-reload' "$(<"$SYSCTL_LOG")"
# Every managed timer is restarted so a changed schedule takes effect, and each is
# then verified as active rather than assumed.
for u in hyn-speedtest.timer hyn-record.timer hyn-alerts.timer hyn-report.timer hyn-push.timer hyn-update.timer; do
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
printf '1.8.0\n' >"$HYN_ROOT/VERSION"
update_check_now >/dev/null
NPM_RESULT=1
: >"$NPM_LOG"
falsy    'a failed npm install is a failed update' 'update_apply 0 2>/dev/null'
contains 'a failed install restores the previous package' 'previous package restored' "$UPD_LAST_ERR"
truthy 'the previous CLI still starts after npm removed its directory' \
  '_update_installed_version && [[ $UPD_INSTALLED == 1.8.0 ]]'
truthy 'the npm command links survive a failed installation too' \
  '[[ -x $TMP/npm/bin/hyn && -x $TMP/npm/bin/hyn-view ]]'
eq       'the running version is unchanged' '1.8.0' "$HYN_VERSION"

# npm succeeds but installs the wrong thing: caught by verifying afterwards.
NPM_RESULT=0
printf '1.8.0\n' >"$TMP/installed"
HYN_VERSION=1.8.0
update_check_now >/dev/null
: >"$TMP/setup.log"; : >"$SYSCTL_LOG"
falsy    'installing the wrong version is caught' 'update_apply 0 2>/dev/null'
contains 'and both versions are named' 'expected 1.9.0 but found 1.8.0' "$UPD_LAST_ERR"
truthy 'a wrong version is rejected before setup or restarts' '[[ ! -s $TMP/setup.log && ! -s $SYSCTL_LOG ]]'

printf '1.9.0\n' >"$TMP/installed"
NPM_BAD_CLI=1
falsy 'version output from a crashing command is not success' 'update_apply 0 2>/dev/null'
contains 'a crashing command is rolled back' 'previous package restored' "$UPD_LAST_ERR"
NPM_BAD_CLI=0

touch "$TMP/setup-fail"
falsy 'a new release with broken setup fails the update' 'update_apply 0 2>/dev/null'
contains 'setup failure restores the previous package and integration' 'previous package and services restored' "$UPD_LAST_ERR"
truthy 'setup rollback runs the old CLI again' '_update_installed_version && [[ $UPD_INSTALLED == 1.8.0 ]]'
rm -f "$TMP/setup-fail"

# A timer that will not come back is a failure too: the package is new but the
# box has stopped monitoring, which is the state that must never be silent.
printf '1.9.0\n' >"$TMP/installed"
HYN_VERSION=1.8.0
update_check_now >/dev/null
SYSCTL_ACTIVE=failed
falsy    'a timer that does not come back fails the update' 'update_apply 0 2>/dev/null'
contains 'and the dead timer is named' 'after restart' "$UPD_LAST_ERR"
contains 'unsuccessful service recovery is actionable' 'service recovery needs sudo hyn doctor --fix' "$UPD_LAST_ERR"
SYSCTL_ACTIVE=active

: >"$NPM_LOG"
HYN_VERSION=1.10.0
falsy 'portal repair cannot downgrade a newer loaded release' 'update_apply 1 2>/dev/null'
contains 'downgrade refusal explains why' 'refusing to downgrade' "$UPD_LAST_ERR"
truthy 'downgrade refusal never runs npm' '[[ ! -s $NPM_LOG ]]'
HYN_VERSION=1.8.0
printf '1.10.0\n' >"$HYN_ROOT/VERSION"
falsy 'a stale process cannot downgrade a newer release on disk' 'update_apply 1 2>/dev/null'
truthy 'disk version is checked before invoking npm' '[[ ! -s $NPM_LOG ]]'
printf '1.8.0\n' >"$HYN_ROOT/VERSION"

saved_root=$HYN_ROOT
HYN_ROOT="$TMP/project/node_modules/hyn-view"
update_detect_method
eq 'a project dependency is not mistaken for a global installation' unknown "$UPD_METHOD"
HYN_ROOT="$TMP/linked-checkout"
mkdir -p "$HYN_ROOT"; touch "$HYN_ROOT/.git"
update_detect_method
eq 'linked git worktrees are detected too' git "$UPD_METHOD"
HYN_ROOT=$saved_root

(
  CFG[auto_update]=install
  HYN_IN_AGENT=0 INVOCATION_ID=''
  update_read() { UPD_AVAILABLE=1; }
  update_check_async() { :; }
  update_apply() { printf 'attempt\n' >>"$TMP/detached-attempts"; return 1; }
  update_startup
  wait
  update_startup
  wait
)
truthy 'repeated interactive launches back off failing automatic installs' \
  '[[ -s $TMP/detached-attempts && $(wc -l <"$TMP/detached-attempts") -eq 1 ]]'
state_dir_v
rm -f "$STATE_DIR/automatic-update-attempt"

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
  'sed -n "/^    record)/,/^    notify)/p" "$ROOT/bin/hyn" | grep update_startup'
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
