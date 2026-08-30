#!/usr/bin/env bash
# hyn-view :: system integration
#
# `hyn setup` is the apt-style half of the install that npm cannot do: the
# config file under /etc, the state directory under /var/lib, and the systemd
# timer for scheduled speed tests. It is a separate, explicit, root-run step on
# purpose -- an npm postinstall script that silently wrote systemd units and
# enabled timers would be doing something the user did not ask for, at a
# privilege level they did not expect.
#
# This never touches anything belonging to Highway.

SVC_NAME='hyn-speedtest'
SVC_PATH="$HYN_UNIT_DIR/$SVC_NAME.service"
TMR_PATH="$HYN_UNIT_DIR/$SVC_NAME.timer"

# What the managed units are allowed to do, and what they are held back from.
#
# hyn has FULL WRITE ACCESS to the filesystem. That is deliberate and it is a
# reversal: these units used to run under ProtectSystem=strict with
# ReadWritePaths limited to one state directory, which read well in a README and
# in practice meant the agent could not install its own updates, could not
# rewrite its own units, and could not repair itself -- every one of those needs
# /usr and /etc. A monitor that cannot fix itself on an unattended box is worse
# than one with a wide mount namespace.
#
# What is kept is the part that actually protects the node, which was never the
# mount namespace:
#
#   * CPUWeight/IOWeight far below the default 100, plus Nice and idle I/O, so
#     the relayer always wins a contended scheduler. Monitoring must never be
#     the reason a validator misses a block.
#   * MemoryMax caps the agent well below anything that could pressure a relayer
#     holding ~1.5 GiB, and OOMScoreAdjust makes the kernel choose hyn first if
#     it ever has to choose. Bash needs ~12 MiB; 256 MiB is already generous.
#   * TimeoutStartSec on every unit, so a wedged collector is reaped instead of
#     accumulating.
#
# None of the dropped options ever prevented hyn from stopping another service.
# Stopping a unit takes a systemctl call, which is a property of the code, not of
# a sandbox -- so that guarantee lives in the code and in test/selfcheck.sh,
# which greps every source file for a systemctl verb aimed at anything that is
# not hyn's own unit. That check is the real protection and it cannot regress
# quietly.
_unit_hardening() {
  cat <<EOF
# Full filesystem write access: the agent installs its own updates and rewrites
# its own units. See the comment above _unit_hardening in lib/setup.sh.
# Always yield to the node. These are the limits that matter on a relay box.
CPUWeight=20
IOWeight=20
MemoryMax=256M
OOMScoreAdjust=500
EOF
}

# generic_unit <description> <exec> <extra-service-lines> <timeout-seconds>
_generic_service() {
  local desc=$1 exec=$2 extra=${3:-} timeout=${4:-180}
  cat <<EOF
[Unit]
Description=$desc
Documentation=https://github.com/AryanVBW/HYN-view
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$exec
# HOME is not set by systemd for a system service without User=, and this tool
# runs under `set -u`. lib/core.sh now defaults it, but it is stated here too so
# a unit written by this release keeps working if the package is ever rolled back
# to a build without that fix.
Environment=HOME=/root
Nice=15
IOSchedulingClass=idle
CPUSchedulingPolicy=batch
TimeoutStartSec=$timeout
$(_unit_hardening)
$extra

[Install]
WantedBy=multi-user.target
EOF
}

# The maintenance unit: a package install, `hyn setup`, and a verification push.
#
# Since every unit now has full write access this no longer exists to escape a
# sandbox. It stays a separate unit for a different reason that is just as real:
# a check-in that fires every sixty seconds must not be the process holding an
# npm install open for a minute, and MemoryMax=256M is correct for a bash
# collector but too tight for node. So the install gets its own unit, its own
# memory limit and its own long timeout, and the check-in hands off and returns.
#
# No [Install] section on purpose. It is started by name, never enabled.
_maintenance_service() {
  local exec=$1
  cat <<EOF
[Unit]
Description=hyn-view portal maintenance command
Documentation=https://github.com/AryanVBW/HYN-view
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$exec
Environment=HOME=/root
# Politeness, not restriction: npm may run for a minute and must not do it at
# the expense of the node.
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=6
CPUWeight=30
IOWeight=30
# node needs considerably more than the collector's 256M.
MemoryMax=1G
OOMScoreAdjust=500
# npm install, then hyn setup, then a verification push. Generous, because a
# slow registry is normal; bounded, because a wedged update must not hold the
# unit for ever.
TimeoutStartSec=900
EOF
}

# The resident agent: the one unit that is not a one-shot.
#
# `Restart=always` is the whole point. Everything else in this file is scheduled
# by a timer and cannot be "not running" for longer than its own interval, but a
# heartbeat that stops is indistinguishable to the portal from a machine that
# stopped -- so the supervisor has to be systemd, not a timer and not us.
#
# It keeps the same politeness limits as the collectors, because it runs beside a
# relayer for months: the beat is one curl, so 128 MiB is generous for a bash
# loop that parses nothing.
_agent_service() {
  local exec=$1
  cat <<EOF
[Unit]
Description=hyn-view resident agent (heartbeat, self-update, self-repair)
Documentation=https://github.com/AryanVBW/HYN-view
After=network-online.target
Wants=network-online.target
# Nothing here can fix a machine that has no clock, and a beat stamped with 1970
# reads as three days of silence on the dashboard.
After=time-sync.target
# systemd gives up on a restart loop by default (5 starts in 10s). A beat every
# 24s must never be permanently abandoned because of a bad ten seconds, so the
# rate limit is lifted rather than the restart made conditional. This key belongs
# to [Unit], not [Service], however much it reads like a service property.
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$exec agent
Environment=HOME=/root
# Always. A crash, an OOM kill, a wedge cleared by self-heal, or a deliberate
# exit after installing a new version all end the same way: the loop comes back.
Restart=always
RestartSec=5s
# A stop must not wait out a sleep. The loop traps TERM and exits immediately;
# this is the backstop if it ever cannot.
TimeoutStopSec=30
KillSignal=SIGTERM
Nice=15
IOSchedulingClass=idle
CPUSchedulingPolicy=batch
CPUWeight=20
IOWeight=20
MemoryMax=128M
OOMScoreAdjust=500

[Install]
WantedBy=multi-user.target
EOF
}

_generic_timer() {
  local desc=$1 spec=$2 unit=$3 jitter=${4:-60} accuracy=${5:-30s} extra=${6:-}
  cat <<EOF
[Unit]
Description=$desc
Documentation=https://github.com/AryanVBW/HYN-view

[Timer]
$spec
RandomizedDelaySec=$jitter
AccuracySec=$accuracy
Persistent=true
Unit=$unit
$extra

[Install]
WantedBy=timers.target
EOF
}

setup_config_template() {
  cat <<EOF
# hyn-view configuration
# Every key from \`hyn config show\` can be set here. Values shown are defaults.
# Reload happens on next start; there is no daemon to restart.

# --- appearance ---------------------------------------------------------------
# best        gradient braille graphs, time axis, 1s refresh. Looks best.
# performance block graphs, 2s refresh. Roughly a third less CPU.
# A profile only fills in keys you have NOT set below, so an explicit
# graph=/interval= line always wins. Toggle live with the p key.
profile=${CFG[profile]}
theme=${CFG[theme]}
# dash (default, the full multi-panel dashboard) or simple (the premium
# glance view: node status, speed now + today's high, cpu temp, essentials).
# hyn net/proc/node still override this on launch.
default_view=${CFG[default_view]}
# refresh interval in seconds. 1.0 is comfortable; 2.0 or 3.0 is lighter still
# on a box where you care about every last cycle.
interval=${CFG[interval]}
# bits (default, matches how links are sold) or bytes
net_unit=${CFG[net_unit]}
# braille (highest resolution) | block (cheaper, coarser) | off
graph=${CFG[graph]}
# Colour graph rows by height so a plot reads as a vertical ramp.
graph_gradient=${CFG[graph_gradient]}
# Time ruler and avg annotation under the network graph.
graph_axis=${CFG[graph_axis]}
graph_stats=${CFG[graph_stats]}
# Show SSID / connection name / local address / gateway / DNS.
net_identity=${CFG[net_identity]}
# force a colour depth instead of detecting: auto | 24 | 256 | 16 | none
color_depth=${CFG[color_depth]}
# on = draw with ASCII only, for consoles without a UTF-8 locale
ascii=${CFG[ascii]}
panels=${CFG[panels]}
proc_rows=${CFG[proc_rows]}
proc_sort=${CFG[proc_sort]}
# Mount points kept out of the disk panel and out of disk alerts. Snap mounts are
# read-only squashfs and therefore permanently 100% full, so a box with twenty
# snaps would otherwise show twenty filesystems and fire twenty disk-full alerts
# that could never clear.
hide_mount=${CFG[hide_mount]}
# Keep more history for the network graph than the visible width, so widening the
# terminal does not blank the plot.
net_history_detail=${CFG[net_history_detail]}

# --- network -----------------------------------------------------------------
# auto follows the default route, which is almost always what you want
wan_iface=${CFG[wan_iface]}
hide_iface=${CFG[hide_iface]}
# probe targets for internet latency, comma separated
latency_targets=${CFG[latency_targets]}
latency_interval=${CFG[latency_interval]}
# also measure the first hop, which separates "my link is bad" from
# "the internet is bad"
latency_gateway=${CFG[latency_gateway]}
dns_probe=${CFG[dns_probe]}
dns_probe_host=${CFG[dns_probe_host]}
public_ip=${CFG[public_ip]}
# the socket state histogram walks /proc/net/tcp, so it runs on its own cadence
tcp_states=${CFG[tcp_states]}
tcp_states_interval=${CFG[tcp_states_interval]}

# --- speed test --------------------------------------------------------------
# how many times a day the timer runs
speedtest_per_day=${CFG[speedtest_per_day]}
speedtest_down_mb=${CFG[speedtest_down_mb]}
speedtest_up_mb=${CFG[speedtest_up_mb]}
speedtest_timeout=${CFG[speedtest_timeout]}
# skip a scheduled test when the link is already busier than this percentage of
# its measured capacity. Protects a live node from being disturbed by its own
# monitoring. Manual \`hyn speedtest\` ignores it.
speedtest_guard_pct=${CFG[speedtest_guard_pct]}
# auto | ookla | speedtest-cli | curl
speedtest_provider=${CFG[speedtest_provider]}
speedtest_history=${CFG[speedtest_history]}

# --- Highway node tracking ---------------------------------------------------
# All of this is read-only. hyn never starts, stops or reconfigures the node.
highway_track=${CFG[highway_track]}
highway_update_check=${CFG[highway_update_check]}
highway_units=${CFG[highway_units]}
# off (default) | exec. 'exec' allows running \`highway --version\` to identify
# the build. Left off because that means executing a validator's own binary
# beside a running instance; version is otherwise read from files, unit
# metadata and the journal.
highway_version_probe=${CFG[highway_version_probe]}

# --- notifications -----------------------------------------------------------
# There is nothing to configure here. Recipients, the provider account, the
# schedule and the message templates all live in the web portal; pair this machine
# with \`sudo hyn link\` and set them on its Account page. No API key, sender
# address or mailing list is stored on this server.
#
# Hard backstop against a flapping condition burning the portal's provider quota.
# Also settable from the portal.
notify_max_per_day=${CFG[notify_max_per_day]}
notify_timeout=${CFG[notify_timeout]}
# off (default). Set on only to include run-as/session usernames, session source
# IP addresses and the worst rejected-login address in notifications. That is
# identity-bearing data: make sure you have a lawful basis before enabling it.
# The portal cannot set this key; it is local-only on purpose.
notify_access_details=${CFG[notify_access_details]}

# --- alerting ----------------------------------------------------------------
alert_enabled=${CFG[alert_enabled]}
# warn (default) | crit | info
alert_min_severity=${CFG[alert_min_severity]}
alert_interval_min=${CFG[alert_interval_min]}
# A condition that is still true is re-notified at most this often.
alert_repeat_hours=${CFG[alert_repeat_hours]}
alert_notify_resolved=${CFG[alert_notify_resolved]}
# Set any threshold to 0 to switch that rule off completely.
alert_mem_pct=${CFG[alert_mem_pct]}
alert_mem_crit_pct=${CFG[alert_mem_crit_pct]}
alert_swap_pct=${CFG[alert_swap_pct]}
alert_disk_pct=${CFG[alert_disk_pct]}
alert_disk_crit_pct=${CFG[alert_disk_crit_pct]}
# Load as a percentage of ONE core, so it means the same on 2 cores and 64.
alert_load_per_core=${CFG[alert_load_per_core]}
alert_steal_pct=${CFG[alert_steal_pct]}
alert_iowait_pct=${CFG[alert_iowait_pct]}
alert_temp_c=${CFG[alert_temp_c]}
alert_net_err_rate=${CFG[alert_net_err_rate]}
# Retransmits in per-mille of segments sent: 50 is 5%.
alert_retrans_pm=${CFG[alert_retrans_pm]}
alert_listen_drops=${CFG[alert_listen_drops]}
alert_conntrack_pct=${CFG[alert_conntrack_pct]}
alert_latency_ms=${CFG[alert_latency_ms]}
alert_loss_pct=${CFG[alert_loss_pct]}
alert_speed_min_pct=${CFG[alert_speed_min_pct]}
alert_fd_pct=${CFG[alert_fd_pct]}
alert_hw_restarts=${CFG[alert_hw_restarts]}
alert_hw_journal_err=${CFG[alert_hw_journal_err]}

# --- daily report ------------------------------------------------------------
report_enabled=${CFG[report_enabled]}
# Server local time, 24h.
report_at=${CFG[report_at]}
report_hours=${CFG[report_hours]}
report_busy_cpu_pct=${CFG[report_busy_cpu_pct]}
report_busy_mem_pct=${CFG[report_busy_mem_pct]}
# How often metrics are sampled for the report, and how long they are kept.
record_interval_min=${CFG[record_interval_min]}
metrics_keep_days=${CFG[metrics_keep_days]}

# --- self update -------------------------------------------------------------
# off | check (tell before installing) | install (managed default)
auto_update=${CFG[auto_update]}
update_check_hours=${CFG[update_check_hours]}

# --- first run ---------------------------------------------------------------
# The install configures itself, so nothing is offered on first launch. Set on to
# be asked instead; \`hyn onboard\` runs the guided setup at any time.
onboarding=${CFG[onboarding]}

# --- web portal --------------------------------------------------------------
# cloud_enabled and cloud_node_id are written by \`sudo hyn link\`. The node token
# itself is the real credential and lives in $HYN_ETC/secrets at 0600, never here.
cloud_enabled=${CFG[cloud_enabled]}
cloud_node_id=${CFG[cloud_node_id]}
# The hosted agent API. Normal installs never change this.
cloud_api_url=${CFG[cloud_api_url]}
# Where \`hyn link\` tells you to open a browser. The agent never contacts it.
cloud_portal_url=${CFG[cloud_portal_url]}
# Minutes between full portal readings. The heartbeat and settings check stay at
# one minute regardless. Also settable from the portal, which wins.
cloud_push_min=${CFG[cloud_push_min]}
# Seconds between liveness beats from the resident agent (hyn-agent.service).
# One small POST that proves this machine is alive; telemetry still follows
# cloud_push_min. Clamped to 5..3600. The portal cannot set this key.
heartbeat_sec=${CFG[heartbeat_sec]}
cloud_timeout=${CFG[cloud_timeout]}
# Self-hosters only: a direct Supabase URL plus its PUBLIC anon key, used instead
# of the hosted API above. Leave both empty for the normal hosted setup.
cloud_url=${CFG[cloud_url]}
cloud_anon_key=${CFG[cloud_anon_key]}
EOF
}

# Values that were shipped as defaults, written verbatim into every config file
# by `hyn setup`, and later found to be wrong. Changing the default in core.sh
# does nothing for a box that already has one of these on disk, and on an
# unattended fleet that is every box.
#
# Only an EXACT match on a known-bad shipped default is replaced. A value the
# operator actually chose does not look like one of these, so it is kept -- the
# config file stays authoritative, which is the same reason the portal is not
# allowed to write these keys either.
#
# Format: key<TAB>stale-value<TAB>corrected-value
_setup_migrations() {
  cat <<'EOF'
highway_units	highway*,hw-*,nebula*,mosaic*	highway*,hway*,hw-*,nebula*,mosaic*
EOF
}

# Applies the table above to $HYN_ETC/config in place, and strips settings that
# no longer exist. Reports what it changed, because a monitoring tool silently
# editing its own configuration is worse than the stale value.
setup_migrate_config() {
  local f="$HYN_ETC/config" key stale new line changed=0 tmp
  [[ -f $f && -w $f ]] || return 0

  # Retired keys first: the six local email providers and the ping URL are gone,
  # and their lines are dead weight that would otherwise produce a note on every
  # launch. Dropped rather than commented out, because a commented-out recipient
  # address is still a recipient address sitting on the box.
  local -a keep=()
  local dropped=0
  while IFS= read -r line || [[ -n $line ]]; do
    key=${line%%=*}
    key=${key//[[:space:]]/}
    if [[ $line == *=* ]] && _cfg_retired "$key"; then
      dropped=$((dropped + 1))
      continue
    fi
    keep+=("$line")
  done <"$f"
  if ((dropped > 0)); then
    tmp="$f.mig.$$"
    printf '%s\n' "${keep[@]}" >"$tmp" || { rm -f -- "$tmp"; warn "could not rewrite $f"; return 1; }
    chmod 0644 "$tmp"
    mv -f "$tmp" "$f" || { rm -f -- "$tmp"; warn "could not replace $f"; return 1; }
    printf '  %-34s removed %d retired email setting(s); delivery is the portal'"'"'s\n' \
      "$f" "$dropped"
  fi
  while IFS=$'\t' read -r key stale new; do
    [[ -n $key ]] || continue
    grep -qxF "$key=$stale" "$f" 2>/dev/null || continue
    tmp="$f.mig.$$"
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$key=$stale" ]]; then
        printf '%s=%s\n' "$key" "$new"
      else
        printf '%s\n' "$line"
      fi
    done <"$f" >"$tmp" || { rm -f -- "$tmp"; warn "could not rewrite $f"; return 1; }
    chmod 0644 "$tmp"
    mv -f "$tmp" "$f" || { rm -f -- "$tmp"; warn "could not replace $f"; return 1; }
    printf '  %-34s %s -> %s\n' "$key" "$stale" "$new"
    CFG[$key]=$new
    changed=1
  done < <(_setup_migrations)
  ((changed)) && printf '  %-34s corrected outdated shipped defaults\n' "$f"
  return 0
}

setup_run() {
  local no_timer=0 wizard=1 integration_ok=1 a
  for a in "$@"; do
    case $a in
      --no-timer) no_timer=1 ;;
      --no-wizard) wizard=0 ;;
      --wizard) wizard=1 ;;
      *) die "setup: unknown option $a" ;;
    esac
  done
  is_root || die 'setup needs root: sudo hyn setup'
  local exe="$HYN_ROOT/bin/hyn"
  [[ -x $exe ]] || die "cannot find my own executable at $exe"

  printf 'hyn: installing system integration\n'

  install -d -m 0755 "$HYN_ETC" "$HYN_ETC/themes" || die "cannot create $HYN_ETC"
  printf '  %-34s ok\n' "$HYN_ETC/"
  install -d -m 0755 "$HYN_VAR" || die "cannot create $HYN_VAR"
  printf '  %-34s ok\n' "$HYN_VAR/"

  if [[ -f $HYN_ETC/config ]]; then
    printf '  %-34s kept (already present)\n' "$HYN_ETC/config"
    setup_migrate_config
  else
    setup_config_template >"$HYN_ETC/config.tmp" && mv -f "$HYN_ETC/config.tmp" "$HYN_ETC/config" \
      || die "cannot write $HYN_ETC/config"
    chmod 0644 "$HYN_ETC/config"
    printf '  %-34s written\n' "$HYN_ETC/config"
  fi

  # Secrets file: created empty at 0600 so the wizard has somewhere safe to put
  # an API key, and so the restrictive mode is set before any key exists.
  if [[ ! -f $HYN_ETC/secrets ]]; then
    ( umask 077; printf '# hyn-view secrets. Mode 0600, root only. Do not commit this file.\n' >"$HYN_ETC/secrets" )
    chmod 0600 "$HYN_ETC/secrets"
    printf '  %-34s created (0600)\n' "$HYN_ETC/secrets"
  else
    chmod 0600 "$HYN_ETC/secrets"
    printf '  %-34s kept (0600 enforced)\n' "$HYN_ETC/secrets"
  fi

  # A convenience symlink so `hyn` works for every user even when npm's global
  # bin dir is not on root's PATH (a very common sudo surprise).
  if [[ ! -e /usr/local/bin/hyn ]]; then
    ln -s "$exe" /usr/local/bin/hyn 2>/dev/null \
      && printf '  %-34s linked\n' '/usr/local/bin/hyn'
  fi

  if ((no_timer)); then
    printf '\nhyn: skipped the timers (--no-timer)\n'
  elif ! have systemctl; then
    printf '\nhyn: no systemd here, skipping the timers\n'
  else
    setup_timers "$exe" || integration_ok=0
  fi

  # There is no notification setup left to run. `--wizard` is accepted so an old
  # script or unit file does not break, and says where the settings went.
  if ((wizard)) && [[ -t 0 && -t 1 ]]; then
    printf '\nhyn: nothing to configure interactively.\n'
    printf '     delivery is the portal'"'"'s: pair with `sudo hyn link`, then set the\n'
    printf '     recipient and schedule on its Account page.\n'
    printf '     for local display and threshold options: hyn onboard\n'
  fi

  if ((integration_ok == 0)); then
    warn 'one or more managed timers could not be enabled; inspect systemctl status for the failed HYN unit'
    return 1
  fi

  printf '\nhyn: done. Next steps:\n'
  printf '  hyn                 open the dashboard\n'
  printf '  hyn doctor          verify the environment end to end\n'
  printf '  hyn alerts check    evaluate every alert rule right now\n'
  printf '  hyn report          print the daily report without sending it\n'
  if ! ((no_timer)) && have systemctl; then
    printf '  systemctl list-timers "hyn-*"\n'
  fi
  return 0
}

# Installs all five timers. Split out so `hyn setup` and a schedule change after
# the wizard both go through the same code.
setup_timers() {
  local exe=$1
  local cal
  cal=$(st_calendar "${CFG[speedtest_per_day]}")

  _write_unit "$SVC_PATH" "$(_generic_service 'hyn-view scheduled throughput measurement' \
    "$exe speedtest --respect-guard --json")"
  _write_unit "$TMR_PATH" "$(_generic_timer 'hyn-view scheduled throughput measurement' \
    "OnCalendar=$cal" "$SVC_NAME.service" 900)"

  # Alerts: the one that actually has to be reliable.
  _write_unit "$HYN_UNIT_DIR/hyn-alerts.service" \
    "$(_generic_service 'hyn-view alert evaluation' "$exe alerts check --quiet")"
  _write_unit "$HYN_UNIT_DIR/hyn-alerts.timer" \
    "$(_generic_timer 'hyn-view alert evaluation' \
      "OnBootSec=3min"$'\n'"OnUnitActiveSec=${CFG[alert_interval_min]}min" 'hyn-alerts.service' 20)"

  # Metric recording for the daily report.
  _write_unit "$HYN_UNIT_DIR/hyn-record.service" \
    "$(_generic_service 'hyn-view metric sampling' "$exe record")"
  _write_unit "$HYN_UNIT_DIR/hyn-record.timer" \
    "$(_generic_timer 'hyn-view metric sampling' \
      "OnBootSec=2min"$'\n'"OnUnitActiveSec=${CFG[record_interval_min]}min" 'hyn-record.service' 20)"

  # Daily report.
  _write_unit "$HYN_UNIT_DIR/hyn-report.service" \
    "$(_generic_service 'hyn-view daily report' "$exe report --send")"
  _write_unit "$HYN_UNIT_DIR/hyn-report.timer" \
    "$(_generic_timer 'hyn-view daily report' \
      "OnCalendar=*-*-* ${CFG[report_at]}:00" 'hyn-report.service' 300)"

  # Wake every minute to pull account settings quickly. `hyn push --scheduled`
  # performs the full telemetry collection only when cloud_push_min is due, so
  # the managed ten-minute default does not run expensive probes every minute.
  #
  # Timeout is 120s, not the shared 180s: the portal calls a node quiet after
  # three missed minutes, so one run allowed to hang for the full 180s would
  # trip that warning by itself. 120s leaves a whole spare interval.
  _write_unit "$HYN_UNIT_DIR/hyn-push.service" \
    "$(_generic_service 'hyn-view web portal push' "$exe push --scheduled" '' 120)"
  # No jitter and 1s accuracy on this one. Jitter exists to stop a fleet
  # hammering an endpoint at the same second, which is worth 15 minutes of slack
  # on a daily report and is actively harmful on a 60s heartbeat with a 180s
  # budget: 15s of jitter plus 30s of timer coalescing turned a "one minute"
  # check-in into up to 105s, and two of those read as a dead machine. The
  # per-node cost is one small HTTPS POST, so spreading it buys nothing.
  _write_unit "$HYN_UNIT_DIR/hyn-push.timer" \
    "$(_generic_timer 'hyn-view web portal push' \
      "OnBootSec=20s"$'\n'"OnUnitActiveSec=1min" 'hyn-push.service' 0 1s)"

  # The resident agent. Not a timer, and the only unit here that stays running:
  # see _agent_service.
  _write_unit "$HYN_UNIT_DIR/hyn-agent.service" "$(_agent_service "$exe")"

  # Started on demand by the check-in, never enabled. See _maintenance_service.
  _write_unit "$HYN_UNIT_DIR/hyn-update.service" \
    "$(_maintenance_service "$exe cloud run-command")"

  systemctl daemon-reload || {
    warn 'systemd daemon reload failed'
    return 1
  }
  # Clear the failed latch on our own units before re-enabling them. A unit that
  # died repeatedly stays in `failed` after the cause is fixed, and on a box where
  # every hyn service had been failing for a day that latch is the difference
  # between "repaired" and "repaired and still shown as broken".
  #
  # Named one by one, never with a glob: another failed unit on the same box is
  # somebody else's to reset, and hway-logrotate.service sitting in `failed` is
  # information the operator needs, not litter for hyn to tidy.
  local u
  for u in "$SVC_NAME.service" hyn-record.service hyn-alerts.service \
           hyn-report.service hyn-push.service hyn-agent.service hyn-update.service; do
    systemctl reset-failed "$u" >/dev/null 2>&1 || true
  done
  setup_apply_schedule "$exe"
}

_write_unit() {
  local path=$1 content=$2
  printf '%s\n' "$content" >"$path.tmp" && mv -f "$path.tmp" "$path" || die "cannot write $path"
  chmod 0644 "$path"
  printf '  %-34s written\n' "$path"
  return 0
}

# Enables or disables each timer according to config.
#
# One rule, applied to all five: a timer is enabled if its job can ever do
# something useful. Nothing is gated on a *delivery destination* any more, because
# every job now treats "nowhere to send" as a no-op and exits 0 (see
# notify_configured). That removes the state that was impossible to explain --
# a correctly installed machine showing two disabled timers and a doctor full of
# warnings, with nothing actually wrong.
#
# The one genuine exception is the portal push. Without a node token every run is
# a guaranteed failure, so an enabled push timer on an unpaired machine would
# write a failure to the journal every sixty seconds. That is not a monitor
# reporting a problem, it is a monitor being the problem.
setup_apply_schedule() {
  have systemctl || return 0
  local rc=0
  systemctl daemon-reload || return 1
  # Sampling and measurement: always. The portal's charts and the daily report's
  # trend lines are drawn from these, so a machine that is monitored but not
  # sampled shows an operator nothing.
  _toggle_timer "$SVC_NAME.timer" 1 || rc=1
  _toggle_timer hyn-record.timer 1 || rc=1
  # Alert evaluation: data collection, not delivery. Every push payload carries
  # the currently firing rules and the portal's event log is built from them.
  _toggle_timer hyn-alerts.timer "$(cfg_on alert_enabled && printf 1 || printf 0)" || rc=1
  # The daily report: on unless switched off. With no channel it prints a line
  # saying so and exits 0; linking gives it the managed `web` channel.
  _toggle_timer hyn-report.timer "$(cfg_on report_enabled && printf 1 || printf 0)" || rc=1
  # The portal push: only once there is a credential to push with.
  _toggle_timer hyn-push.timer "$(cfg_on cloud_enabled && cloud_linked && printf 1 || printf 0)" || rc=1
  # The resident agent: always, paired or not.
  #
  # It is tempting to gate this on being linked, since the heartbeat is the
  # visible half of its job. That would be wrong: the loop is also the only thing
  # on an unpaired machine that looks for a release or re-arms a drifted timer --
  # hyn-push.timer is off without a token, so gating the agent the same way would
  # leave exactly the boxes nobody logs into with no route in for a fix. It beats
  # when a token appears and costs a sleeping bash process when there is not one.
  #
  # `enable --now` on an already-running service is a no-op, so a repeated
  # `hyn setup` does not interrupt the beat.
  _toggle_timer hyn-agent.service 1 || rc=1
  return "$rc"
}

# Why a timer is not running, in the words an operator needs. Empty output means
# "it should be running", which is what `hyn doctor` treats as a problem.
setup_timer_reason() {
  case ${1:-} in
    hyn-alerts.timer)
      cfg_on alert_enabled || { printf 'alert_enabled=off in %s/config\n' "$HYN_ETC"; return 0; } ;;
    hyn-report.timer)
      cfg_on report_enabled || { printf 'report_enabled=off in %s/config\n' "$HYN_ETC"; return 0; } ;;
    hyn-push.timer)
      cfg_on cloud_enabled || { printf 'not paired with the portal yet: sudo hyn link\n'; return 0; }
      cloud_linked || { printf 'no node token; pair again with: sudo hyn link\n'; return 0; } ;;
  esac
  return 1
}

# Runs from `hyn record`, which is the one timer enabled unconditionally on
# every installed machine (see its caller for why that makes it the right home
# for a check that must run even on a box nobody has ever logged into).
#
# A timer that should be running and is not usually means a bad `npm install`
# left units half-written, a reboot raced systemd before the timer was armed, or
# an interrupted update left daemon-reload unrun -- none of which the operator
# caused or can be expected to notice. `hyn doctor --fix` already repairs this;
# the only thing missing was something that runs it without being asked. This
# is the minimal version of that: re-enable just the one unit that drifted,
# never a full `setup_run`, so a machine mid-onboarding is not reconfigured by a
# background timer.
#
# ponytail: only the five hyn-* timers and hyn-agent.service are touched, matching
# the systemctl verbs `test/selfcheck.sh` already enforces are aimed at nothing
# else. If re-enabling fails twice in a row this stays silent rather than
# escalating -- `hyn doctor` still reports it as a warning either way, so nothing
# is hidden, only handled.
setup_self_heal() {
  have systemctl || return 0
  is_root || return 0
  local u want st
  for u in hyn-record.timer hyn-alerts.timer hyn-report.timer hyn-push.timer hyn-speedtest.timer; do
    systemctl cat "$u" >/dev/null 2>&1 || continue
    case $u in
      hyn-alerts.timer) want=$(cfg_on alert_enabled && printf 1 || printf 0) ;;
      hyn-report.timer) want=$(cfg_on report_enabled && printf 1 || printf 0) ;;
      hyn-push.timer) want=$(cfg_on cloud_enabled && cloud_linked && printf 1 || printf 0) ;;
      *) want=1 ;;
    esac
    [[ $want == 1 ]] || continue
    st=$(systemctl is-active "$u" 2>/dev/null)
    [[ $st == active ]] && continue
    systemctl reset-failed "$u" >/dev/null 2>&1 || true
    systemctl enable --now "$u" >/dev/null 2>&1 || true
  done
  setup_heal_agent
  return 0
}

# The resident agent needs a different check from a timer, and it is the reason
# this function exists at all.
#
# `Restart=always` already covers the agent dying, so a dead loop is systemd's
# problem and it solves it in five seconds. What systemd cannot see is a loop
# that is *running and not beating*: a curl wedged on a half-open socket, a
# filesystem that stopped accepting the stamp, a bug of ours. To the dashboard
# that is identical to a machine that has been switched off, which is the single
# worst thing this tool can get wrong. So progress is measured, not assumed, and
# a loop that has stopped making it is restarted.
#
# Deliberately never called from inside the loop itself: agent_maintain sets
# HYN_IN_AGENT so the agent cannot kill the process it is running in.
setup_heal_agent() {
  have systemctl || return 0
  is_root || return 0
  [[ ${HYN_IN_AGENT:-0} == 1 ]] && return 0
  systemctl cat hyn-agent.service >/dev/null 2>&1 || return 0
  local st
  st=$(systemctl is-active hyn-agent.service 2>/dev/null)
  if [[ $st != active ]]; then
    systemctl reset-failed hyn-agent.service >/dev/null 2>&1 || true
    systemctl enable --now hyn-agent.service >/dev/null 2>&1 || true
    return 0
  fi
  # Running. Is it beating? agent_stamp_stale lives in the agent library, which
  # nothing else sources, so load it on demand -- and if it cannot be loaded,
  # leave the running service alone rather than guessing.
  declare -F agent_stamp_stale >/dev/null 2>&1 || {
    [[ -r $HYN_LIB/agent.sh ]] || return 0
    # shellcheck source=/dev/null
    source "$HYN_LIB/agent.sh" 2>/dev/null || return 0
  }
  if agent_stamp_stale; then
    warn 'hyn-agent.service is running but has not beaten recently; restarting it'
    systemctl restart hyn-agent.service >/dev/null 2>&1 || true
  fi
  return 0
}

_toggle_timer() {
  # Named for its only caller until the resident agent arrived; the body is
  # unit-generic, so it takes hyn-agent.service too rather than growing a
  # near-identical twin.
  local unit=$1 want=${2:-0}
  if [[ $want == 1 ]]; then
    if systemctl enable --now "$unit" >/dev/null 2>&1; then
      printf '  %-34s enabled\n' "$unit"
    else
      printf '  %-34s could not enable (systemctl status %s)\n' "$unit" "$unit"
      return 1
    fi
  else
    if systemctl disable --now "$unit" >/dev/null 2>&1; then
      printf '  %-34s disabled (not configured)\n' "$unit"
    else
      printf '  %-34s could not disable (systemctl status %s)\n' "$unit" "$unit"
      return 1
    fi
  fi
  return 0
}

setup_uninstall() {
  local purge=0 a
  for a in "$@"; do
    case $a in
      --purge) purge=1 ;;
      *) die "uninstall: unknown option $a" ;;
    esac
  done
  is_root || die 'uninstall needs root: sudo hyn uninstall'

  printf 'hyn: removing system integration\n'
  if have systemctl; then
    local u
    for u in "$SVC_NAME.timer" hyn-alerts.timer hyn-record.timer hyn-report.timer hyn-push.timer \
             hyn-agent.service; do
      systemctl disable --now "$u" >/dev/null 2>&1 && printf '  %-24s disabled\n' "$u"
    done
    rm -f "$SVC_PATH" "$TMR_PATH" \
      "$HYN_UNIT_DIR/hyn-alerts.service" "$HYN_UNIT_DIR/hyn-alerts.timer" \
      "$HYN_UNIT_DIR/hyn-record.service" "$HYN_UNIT_DIR/hyn-record.timer" \
      "$HYN_UNIT_DIR/hyn-report.service" "$HYN_UNIT_DIR/hyn-report.timer" \
      "$HYN_UNIT_DIR/hyn-push.service" "$HYN_UNIT_DIR/hyn-push.timer" \
      "$HYN_UNIT_DIR/hyn-agent.service" \
      "$HYN_UNIT_DIR/hyn-update.service"
    systemctl daemon-reload
    printf '  units removed\n'
  fi
  [[ -L /usr/local/bin/hyn ]] && rm -f /usr/local/bin/hyn && printf '  /usr/local/bin/hyn unlinked\n'

  if ((purge)); then
    # Only with --purge, and only these two paths: config, credentials and
    # recorded history are the user's data, not ours to delete by default.
    rm -rf "$HYN_ETC" "$HYN_VAR"
    printf '  %s and %s removed\n' "$HYN_ETC" "$HYN_VAR"
  else
    printf '  kept %s (config + secrets) and %s (history)\n' "$HYN_ETC" "$HYN_VAR"
    printf '  use --purge to remove them too\n'
  fi
  printf '\nhyn: the command itself is managed by npm: npm rm -g hyn-view\n'
  return 0
}
