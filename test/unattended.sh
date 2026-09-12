#!/usr/bin/env bash
# Exercise queued maintenance, configuration application and boot recovery
# without installing a package or changing this computer's services.
set -uo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT" HYN_ETC="$WORK/etc" HYN_VAR="$WORK/state" HYN_UNIT_DIR="$WORK/units"
export XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/user-state" HYN_CONFIG=''
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_UNIT_DIR"
for module in core notify update cloud setup; do source "$HYN_LIB/$module.sh"; done
is_root() { return 0; }
cfg_load
# macOS has flock(2), but does not ship the util-linux CLI. Exercise the real
# advisory lock through Python there; supported Ubuntu uses its native binary.
if ! command -v flock >/dev/null && command -v python3 >/dev/null; then
  flock() {
    python3 - "$@" <<'PY'
import fcntl, sys, time
deadline = time.monotonic() + (float(sys.argv[2]) if sys.argv[1] == '-w' else 0)
while True:
    try:
        fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline: sys.exit(1)
        time.sleep(.01)
PY
  }
  _HAVE[flock]=1
fi
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else printf 'FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); fi; }
systemctl() { printf '%s\n' "$*" >>"$WORK/systemctl"; return 0; }
_HAVE[systemctl]=1
cloud_linked() { return 0; }
cloud_configured() { return 0; }
cloud_config_pull() { CLOUD_NODE_STATUS=active; return 0; }

config_set record_interval_min 7 report_at 09:30
check 'grouped properties persist together' '[[ $(<"$HYN_ETC/config") == *record_interval_min=7* && $(<"$HYN_ETC/config") == *report_at=09:30* ]]'
before=$(<"$HYN_ETC/config")
check 'a bad property aborts the complete batch' '! config_set record_interval_min 8 report_at 77:00 2>/dev/null && [[ $(<"$HYN_ETC/config") == "$before" ]]'
check 'an odd property list fails without writing' '! config_set report_at 10:00 keep_awake 2>/dev/null && [[ $(<"$HYN_ETC/config") == "$before" ]]'
check 'sleep policy remains explicit and bounded' '! config_set keep_awake "on;reboot" 2>/dev/null'
config_set auto_update install

if have flock; then
  _update_apply() { touch "$WORK/installing"; sleep 1; return 0; }
  update_apply 1 & updating=$!
  for i in {1..100}; do [[ -f $WORK/installing ]] && break; sleep .01; done
  check 'a concurrent installer is refused by the operating-system lock' '! update_apply 1 && [[ $UPD_LAST_ERR == *already* ]]'
  wait "$updating"
  check 'installer lock is released on completion' 'update_apply 1'
fi

job=$(cloud_pending_file)
cloud_command_execute() {
  printf '%s\t%s\n' "$CLOUD_COMMAND_ID" "$1" >>"$WORK/executed"
  [[ -s $job ]] || return 8 # A crash must leave the job recoverable.
  return "${EXEC_RC:-0}"
}
check 'automatic update with empty command id can be handed off' 'cloud_handoff_command "" update'
check 'pending job is private' '[[ $(find "$job" -perm -004 | wc -l) -eq 0 ]]'
check 'a second job cannot overwrite the saved job' '! cloud_handoff_command 11111111-1111-4111-8111-111111111111 update && [[ $(cat "$job") == $'"'"'\tupdate'"'"' ]]'
check 'automatic maintenance survives parsing and is cleared on success' 'cloud_run_pending 1 && [[ $(<"$WORK/executed") == $'"'"'\tupdate'"'"' && ! -e $job ]]'
check 'restarting an empty maintenance unit is a no-op' 'cloud_run_pending 1 && [[ $(wc -l <"$WORK/executed") -eq 1 ]]'

EXEC_RC=1
cloud_handoff_command '' update
check 'failed unattended install releases the slot for portal commands' '! cloud_run_pending 1 && [[ ! -f $job && -f $HYN_VAR/automatic-update-attempt ]]'
update_read() { UPD_AVAILABLE=1; }
update_check_async() { :; }
CLOUD_IN_MAINTENANCE=0
check 'automatic recovery backs off instead of looping installs' 'update_startup && [[ ! -e $job ]]'
printf '%s\n' "$((EPOCHSECONDS - 901))" >"$HYN_VAR/automatic-update-attempt"
EXEC_RC=0
check 'automatic recovery retries after its delay and completes' 'update_startup && cloud_run_pending 1 && [[ $(wc -l <"$WORK/executed") -eq 3 && ! -e $job ]]'
cloud_handoff_command '' update
CFG[auto_update]=off
check 'turning automatic updates off cancels a saved automatic job' 'cloud_run_pending 1 && [[ ! -e $job && $(wc -l <"$WORK/executed") -eq 3 ]]'
CFG[auto_update]=install

cloud_handoff_command 11111111-1111-4111-8111-111111111111 update
cloud_config_pull() { CLOUD_NODE_STATUS=suspended; return 0; }
check 'recovered portal job rechecks permissions before installing' '! cloud_run_pending 1 2>/dev/null && [[ ! -e $job && $(wc -l <"$WORK/executed") -eq 3 ]]'
systemctl() { [[ $1 != start ]]; }
check 'a failed service trigger retains the job for the recovery timer' 'cloud_handoff_command "" update 2>/dev/null && [[ -s $job ]]'
rm -f "$job" "$job.retry"

# Reconciliation writes and applies new timers once, and keeps retrying a
# failed restart. All systemctl calls below are recorded rather than executed.
st_calendar() { printf '*-*-* 00:00:00'; }
systemd-inhibit() { :; }
_HAVE[systemd-inhibit]=1
systemctl() {
  printf '%s\n' "$*" >>"$WORK/systemctl"
  [[ $* == 'restart hyn-record.timer' && ${RESTART_FAIL:-0} == 1 ]] && return 1
  [[ $1 == is-active ]] && printf 'active\n'
  return 0
}
touch "$HYN_UNIT_DIR/hyn-agent.service"
cfg_load
check 'changed properties produce active schedules' 'setup_reconcile && [[ $(<"$HYN_UNIT_DIR/hyn-record.timer") == *OnUnitActiveSec=7min* && $(<"$HYN_UNIT_DIR/hyn-report.timer") == *09:30:00* ]]'
before_calls=$(wc -l <"$WORK/systemctl")
check 'unchanged settings avoid all service operations' 'setup_reconcile && [[ $(wc -l <"$WORK/systemctl") -eq $before_calls ]]'
rm "$HYN_UNIT_DIR/hyn-record.timer"
check 'missing startup units are recreated without a setting change' 'setup_reconcile && [[ -s $HYN_UNIT_DIR/hyn-record.timer ]]'
check 'recovery timer is enabled at boot' '[[ $(<"$HYN_UNIT_DIR/hyn-update.timer") == *OnBootSec=1min* && $(<"$WORK/systemctl") == *"enable --now hyn-update.timer"* ]]'
check 'keep-awake blocks sleep and lid handling without blocking shutdown' '[[ $(<"$HYN_UNIT_DIR/hyn-awake.service") == *--what=sleep:idle:handle-lid-switch* && $(<"$HYN_UNIT_DIR/hyn-awake.service") != *--what=shutdown* ]]'
prior_applied=$(<"$HYN_VAR/applied-schedule")
CFG[record_interval_min]=9; RESTART_FAIL=1
check 'failed schedule application is not acknowledged as complete' '! setup_reconcile && [[ $(<"$HYN_VAR/applied-schedule") == "$prior_applied" ]]'
RESTART_FAIL=0
check 'next maintenance pass retries and acknowledges the settings' 'setup_reconcile && [[ $(<"$HYN_VAR/applied-schedule") != "$prior_applied" ]]'
CFG[keep_awake]=off
check 'disabling keep-awake releases only the HYN inhibitor service' 'setup_reconcile && [[ $(<"$WORK/systemctl") == *"disable --now hyn-awake.service"* ]]'

# A running service which has lost its enablement must survive the next boot.
systemctl() {
  printf '%s\n' "$*" >>"$WORK/boot-repair"
  case $1 in
    is-active) printf 'active\n' ;;
    is-enabled) return 1 ;;
  esac
  return 0
}
HYN_IN_AGENT=1
setup_self_heal
check 'running timers are re-enabled for the next boot' '[[ $(<"$WORK/boot-repair") == *"enable hyn-record.timer"* ]]'
check 'no unrelated services are stopped, masked or rebooted' '! grep -Eq "(^| )(mask|reboot|poweroff)|hway|nebula" "$WORK/systemctl" "$WORK/boot-repair"'

# Missing stamps need a startup grace period, then the same recovery as a
# stalled loop. These calls only log to this test directory.
source "$HYN_LIB/agent.sh"
HYN_IN_AGENT=0
CFG[heartbeat_sec]=60
stamp=$(agent_stamp)
systemctl() {
  printf '%s\n' "$*" >>"$WORK/agent-repair"
  case $1 in
    is-active) printf 'active\n' ;;
    restart) return "${AGENT_RESTART_FAIL:-0}" ;;
  esac
  return 0
}
check 'a new agent without a stamp gets time for its first tick' 'setup_heal_agent && [[ -r $stamp.missing-since ]] && ! grep -q "^restart " "$WORK/agent-repair"'
printf '%s\n' "$((EPOCHSECONDS - 181))" >"$stamp.missing-since"
AGENT_RESTART_FAIL=1
check 'failed recovery preserves the expired grace period for retry' 'setup_heal_agent && [[ -r $stamp.missing-since ]]'
AGENT_RESTART_FAIL=0
check 'an active agent that never produces a stamp is restarted' 'setup_heal_agent 2>/dev/null && [[ ! -e $stamp.missing-since ]] && grep -q "^restart hyn-agent.service$" "$WORK/agent-repair"'
printf '%s\n' "$EPOCHSECONDS" >"$stamp.missing-since"
printf '%s\n' "$EPOCHSECONDS" >"$stamp"
: >"$WORK/agent-repair"
check 'a fresh tick clears missing-stamp tracking without a restart' 'setup_heal_agent && [[ ! -e $stamp.missing-since ]] && ! grep -q "^restart " "$WORK/agent-repair"'
printf '%s\n' "$((EPOCHSECONDS + 3600))" >"$stamp"
check 'a future stamp cannot hide a wedge after a clock correction' 'agent_stamp_stale'
CFG[heartbeat_sec]=99999
printf '%s\n' "$((EPOCHSECONDS - 12000))" >"$stamp"
check 'the watchdog uses the same maximum interval as the loop' 'agent_stamp_stale'
CFG[heartbeat_sec]=60
printf '%012d\n' "$EPOCHSECONDS" >"$stamp"
check 'a padded timestamp is decimal instead of invalid shell octal' '! agent_stamp_stale'
printf '9999999999999999999999999999999999999\n' >"$stamp"
check 'an oversized corrupted stamp cannot overflow watchdog arithmetic' 'agent_stamp_stale'

# An update may already have replaced core.sh by the time the loaded old
# process enters its loop. It must compare disk against its in-memory version.
mkdir -p "$WORK/new-package/lib"
printf 'HYN_VERSION="99.0.0"\n' >"$WORK/new-package/lib/core.sh"
(
  HYN_ROOT="$WORK/new-package"
  agent_beat() { :; }
  agent_maintain() { :; }
  _agent_sleep() { touch "$WORK/stale-agent-slept"; AGENT_STOP=1; }
  agent_run >"$WORK/version-change"
)
check 'an update during startup replaces the old in-memory agent' '[[ ! -e $WORK/stale-agent-slept ]] && grep -q "99.0.0 installed" "$WORK/version-change"'

# Simulate NTP correcting the clock backwards without touching the host clock
# or waiting real intervals. Both retries and maintenance must become due.
(
  unset EPOCHSECONDS
  EPOCHSECONDS=5000
  sleeps=0
  agent_beat() { printf '%s:%s\n' "$EPOCHSECONDS" "$AGENT_RETRY_AT" >>"$WORK/clock-beats"; }
  agent_maintain() { printf '%s\n' "$EPOCHSECONDS" >>"$WORK/clock-maintenance"; AGENT_RETRY_AT=$((EPOCHSECONDS + 600)); }
  _agent_sleep() { sleeps=$((sleeps + 1)); EPOCHSECONDS=1000; ((sleeps >= 2)) && AGENT_STOP=1; return 0; }
  agent_run >/dev/null
)
check 'clock rollback clears a future heartbeat retry deadline' 'grep -q "^1000:0$" "$WORK/clock-beats"'
check 'clock rollback does not defer maintenance until the old time' '[[ $(wc -l <"$WORK/clock-maintenance") -eq 2 ]]'
printf '%s checks passed; %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
