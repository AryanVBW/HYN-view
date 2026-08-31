#!/usr/bin/env bash
# hyn-view :: the resident agent
#
# Everything else in this tool is a one-shot: a timer fires, a short bash process
# reads /proc, sends something, and exits. That is the right shape for sampling
# and for a daily report, and it is the wrong shape for a heartbeat.
#
# A heartbeat is the one thing the portal reads as *proof of life*, and the
# portal is the only thing on earth that can notice this machine has stopped --
# nothing running on a box can report that the box is off. So the beat has to be
# the most reliable part of the agent, and a systemd timer is not that: the
# minimum useful timer cadence still pays a whole process start per beat, and
# `AccuracySec` plus `RandomizedDelaySec` coalescing means a "24 second" timer is
# a 24-to-50 second timer. Three of those in a row and a healthy machine is
# reported as gone.
#
# So this is a single long-lived bash process that sleeps between beats:
#
#   * ~11 MiB RSS, which is the bash interpreter, and one fork per beat for
#     sleep plus one curl. Nothing is parsed and no collector runs, so the beat
#     costs orders of magnitude less than the check-in it sits alongside.
#   * `Restart=always` in the unit makes systemd the supervisor. A crash, an OOM
#     kill or an exit for any reason is followed by a restart in RestartSec, so
#     "keep it running" is not code we have to write or get right.
#   * A wedged loop -- running but not beating -- is the failure a restart policy
#     cannot see. So every tick stamps a file, and setup_self_heal restarts this
#     unit when that stamp goes stale. See agent_stamp_stale.
#   * A resident process holds the code it started with, for ever. That is a new
#     failure mode this codebase did not have before: an update installed
#     underneath it would leave last week's loop beating happily. So it checks
#     the version on disk and exits when it changes, and systemd starts the new
#     one. Exiting IS the upgrade path.
#
# It deliberately does not collect or push telemetry. That stays in
# hyn-push.service, one-shot, isolated: an expensive collector that leaks or
# wedges must not be able to take the heartbeat down with it. Two units, one job
# each.

AGENT_STOP=0
AGENT_SLEEP_PID=0
AGENT_BEATS=0
AGENT_BEAT_OK=0
AGENT_BEAT_FAIL=0
AGENT_INTERVAL=24
# Set only by `hyn agent --interval=N`, and re-applied after every config reload
# so a debugging override is not thrown away by the first maintenance pass.
AGENT_INTERVAL_ARG=''

agent_stamp() {
  state_dir_v
  printf '%s/agent-alive' "$STATE_DIR"
}

# True when the resident loop should be considered wedged rather than merely
# unlucky. The stamp is written every tick whether or not the beat reached the
# portal, so a stale stamp means the loop itself stopped making progress -- which
# a restart fixes and a restart policy alone never notices.
#
# Three intervals of slack, and never less than 120s, so a slow beat or a busy
# box is not mistaken for a wedge.
agent_stamp_stale() {
  local f ts='' now=${EPOCHSECONDS:-0} interval slack
  f=$(agent_stamp)
  # Never seen it run: not stale, just absent. The caller decides what to do
  # about a unit that has never started.
  [[ -r $f ]] || return 1
  read -r ts <"$f" 2>/dev/null
  [[ $ts =~ ^[0-9]+$ ]] || return 0
  interval=${CFG[heartbeat_sec]:-24}
  [[ $interval =~ ^[0-9]+$ ]] || interval=24
  slack=$((interval * 3))
  ((slack < 120)) && slack=120
  ((now - ts > slack))
}

# heartbeat_sec, clamped. A 1-second beat would be a denial of service against
# our own API and a 0 would spin; anything past an hour is not a heartbeat.
agent_interval_v() {
  AGENT_INTERVAL=${CFG[heartbeat_sec]:-24}
  [[ $AGENT_INTERVAL =~ ^[1-9][0-9]{0,4}$ ]] || AGENT_INTERVAL=24
  ((AGENT_INTERVAL < 5)) && AGENT_INTERVAL=5
  ((AGENT_INTERVAL > 3600)) && AGENT_INTERVAL=3600
  return 0
}

# The version of the code on disk, which is not necessarily the version this
# process is running. Read from lib/core.sh rather than package.json because
# core.sh is the file that actually defines HYN_VERSION, so the two cannot
# disagree. No fork: this is a builtin read of the first matching line.
AGENT_DISK_VERSION=''
agent_disk_version_v() {
  local line
  AGENT_DISK_VERSION=''
  [[ -r $HYN_ROOT/lib/core.sh ]] || return 1
  while IFS= read -r line; do
    [[ $line == HYN_VERSION=* ]] || continue
    line=${line#HYN_VERSION=}
    line=${line//\"/}
    line=${line//\'/}
    line=${line%%[[:space:]]*}
    [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || return 1
    AGENT_DISK_VERSION=$line
    return 0
  done <"$HYN_ROOT/lib/core.sh"
  return 1
}

_agent_wake() {
  AGENT_STOP=1
  ((AGENT_SLEEP_PID > 0)) && kill "$AGENT_SLEEP_PID" 2>/dev/null
  return 0
}

# Interruptible sleep. `sleep` in the foreground would defer a SIGTERM until it
# returned, so `systemctl stop hyn-agent` would take up to a full interval and
# look like a hung unit; backgrounding it and waiting makes the trap immediate.
_agent_sleep() {
  local secs=$1
  ((secs < 1)) && secs=1
  sleep "$secs" &
  AGENT_SLEEP_PID=$!
  wait "$AGENT_SLEEP_PID" 2>/dev/null || true
  AGENT_SLEEP_PID=0
  return 0
}

# One beat. Silent on the happy path: this runs 3600 times a day, and a line per
# beat in the journal would bury everything else on the box. Only transitions are
# reported, which is the same reason the alert engine has hysteresis.
agent_beat() {
  local before=$AGENT_BEAT_OK
  if ! cloud_configured || ! cloud_linked; then
    # Not an error. An unpaired machine is a working local monitor; the loop
    # stays up for the update and repair duties below and starts beating the
    # moment `hyn link` writes a token, with no restart needed.
    return 0
  fi
  AGENT_BEATS=$((AGENT_BEATS + 1))
  if cloud_heartbeat 1; then
    AGENT_BEAT_OK=$((AGENT_BEAT_OK + 1))
    if ((AGENT_BEAT_FAIL > 0)); then
      printf 'hyn-agent: heartbeat restored after %d failed beat(s)\n' "$AGENT_BEAT_FAIL"
      AGENT_BEAT_FAIL=0
    fi
    ((before == 0)) && printf 'hyn-agent: heartbeat established with %s every %ss\n' \
      "$(cloud_url)" "$AGENT_INTERVAL"
    return 0
  fi
  AGENT_BEAT_FAIL=$((AGENT_BEAT_FAIL + 1))
  # Once, on the transition. Repeating an unreachable endpoint every 24 seconds
  # for a week is how a journal becomes useless.
  ((AGENT_BEAT_FAIL == 1)) && warn "heartbeat failed: ${CLOUD_LAST_ERR:-unknown error}"
  return 1
}

# Everything that is not a beat, on a much slower cadence: pick up config
# changes, look for a release, and re-arm anything that has drifted.
#
# This is the only place on an *unpaired* machine where either of the last two
# happen at all -- hyn-push.timer is disabled without a node token, so a box
# nobody linked and nobody logs into would otherwise never look for a fix again.
agent_maintain() {
  # Config first: heartbeat_sec, auto_update and the portal-managed cache can
  # all have changed since the last pass, and a resident process that never
  # re-reads them would need a restart to notice.
  cfg_load
  # cfg_load reloads from the shipped defaults by design, which silently threw
  # away a `--interval=` given on the command line -- the first maintenance pass
  # runs on the first tick, so the flag appeared to do nothing at all.
  [[ -n $AGENT_INTERVAL_ARG ]] && CFG[heartbeat_sec]=$AGENT_INTERVAL_ARG
  agent_interval_v
  # Honours auto_update and its own 12-hour cache, so this is nearly always a
  # cache read. When an install is due it is handed to hyn-update.service --
  # a separate cgroup, which is what keeps npm from being killed when this
  # process is restarted by the very update it started.
  update_startup
  if declare -F setup_self_heal >/dev/null 2>&1; then
    # HYN_IN_AGENT (set in agent_run) stops self-heal from restarting the unit
    # it is running inside; every other drifted unit is re-armed here.
    setup_self_heal
  fi
  return 0
}

# agent_run [--once] [--interval N]
agent_run() {
  local once=0 a
  local now beat_at=0 maint_at=0 maint_every=300 spent
  for a in "$@"; do
    case $a in
      --once) once=1 ;;
      --interval=*) AGENT_INTERVAL_ARG=${a#*=}; CFG[heartbeat_sec]=$AGENT_INTERVAL_ARG ;;
      -h | --help)
        printf 'usage: hyn agent [--once] [--interval=SECONDS]\n'
        printf '  Resident loop: beats every heartbeat_sec (default 24), keeps the\n'
        printf '  package updated and re-arms drifted timers. Installed and\n'
        printf '  supervised as hyn-agent.service; run by hand only to debug.\n'
        return 0 ;;
      *) die "agent: unknown option $a" ;;
    esac
  done

  agent_interval_v
  # Once, before HYN_IN_AGENT silences the per-read check below: a secrets file
  # others can read is worth saying out loud, and startup is the one place in a
  # months-long process where saying it costs a single line rather than 15,600 a
  # day. The timers and `hyn doctor` still report it if it breaks later.
  secrets_load >/dev/null || true
  # Read by update_refresh_services and setup_heal_agent, both of which restart
  # hyn-agent.service: from inside the loop that is self-destruction, and both
  # have a better answer available (exit on the version change; trust the beat).
  HYN_IN_AGENT=1
  # Loaded here rather than at the top of bin/hyn: the dashboard and every
  # one-shot pay for what they source, and nothing but this loop needs it.
  if [[ -r $HYN_LIB/setup.sh ]]; then
    # shellcheck source=/dev/null
    source "$HYN_LIB/setup.sh" 2>/dev/null || true
  fi
  agent_disk_version_v || AGENT_DISK_VERSION=$HYN_VERSION
  local started=$AGENT_DISK_VERSION
  local stamp
  stamp=$(agent_stamp)

  trap '_agent_wake' TERM INT HUP

  printf 'hyn-agent: %s resident, beating every %ss%s\n' "$HYN_VERSION" "$AGENT_INTERVAL" \
    "$(cloud_linked || printf ' (unpaired: no beats until `sudo hyn link`)')"

  while :; do
    now=${EPOCHSECONDS:-0}
    # Written before the work, not after: the stamp answers "is this loop making
    # progress", and a beat that blocks for its full curl timeout is progress.
    printf '%s\n' "$now" >"$stamp.tmp" 2>/dev/null && mv -f "$stamp.tmp" "$stamp" 2>/dev/null || true

    # The beat goes FIRST, before any maintenance.
    #
    # This used to be the other way round, and it was wrong in the one case that
    # matters most: a machine that has just booted. Maintenance walks six units
    # with systemctl, and on a box where the whole unit graph is still starting
    # those calls are slow -- measured at 3.3s with a 250ms systemctl, all of it
    # spent before the portal heard anything at all. The portal's entire job is
    # knowing this machine is alive, so nothing gets to queue ahead of saying so.
    beat_at=$now
    agent_beat || true

    if ((now - maint_at >= maint_every)); then
      maint_at=$now
      agent_maintain
    fi

    ((once)) && break
    ((AGENT_STOP)) && break

    # A new version landed underneath us. Exit and let systemd start the loop
    # that shipped with it; an npm install has already replaced these files, so
    # this process is the only stale thing left on the box.
    if agent_disk_version_v && [[ -n $AGENT_DISK_VERSION && $AGENT_DISK_VERSION != "$started" ]]; then
      printf 'hyn-agent: %s installed (was %s); exiting so systemd starts the new agent\n' \
        "$AGENT_DISK_VERSION" "$started"
      break
    fi

    # Sleep the remainder of the interval rather than a flat interval, so a beat
    # that took 8 seconds does not turn a 24s heartbeat into 32s. Drift there is
    # cumulative and it is what eventually trips the portal's quiet threshold on
    # a machine that is perfectly healthy.
    spent=$((${EPOCHSECONDS:-0} - beat_at))
    ((spent < 0)) && spent=0
    _agent_sleep $((AGENT_INTERVAL - spent))
    ((AGENT_STOP)) && break
  done

  ((AGENT_STOP)) && printf 'hyn-agent: stopping on signal after %d beat(s)\n' "$AGENT_BEATS"
  return 0
}
