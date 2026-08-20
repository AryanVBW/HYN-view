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
SVC_PATH="/etc/systemd/system/$SVC_NAME.service"
TMR_PATH="/etc/systemd/system/$SVC_NAME.timer"

# Shared hardening for every timer unit. These are monitoring one-shots: they
# read /proc, write one state directory, and talk to one API. Everything else
# root can normally do is taken away.
_unit_hardening() {
  cat <<EOF
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$HYN_VAR
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectClock=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
NoNewPrivileges=yes
EOF
}

# generic_unit <description> <exec> <extra-service-lines>
_generic_service() {
  local desc=$1 exec=$2 extra=${3:-}
  cat <<EOF
[Unit]
Description=$desc
Documentation=https://github.com/AryanVBW/HYN-view
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$exec
Nice=15
IOSchedulingClass=idle
CPUSchedulingPolicy=batch
TimeoutStartSec=180
$(_unit_hardening)
$extra

[Install]
WantedBy=multi-user.target
EOF
}

_generic_timer() {
  local desc=$1 spec=$2 unit=$3 jitter=${4:-60} extra=${5:-}
  cat <<EOF
[Unit]
Description=$desc
Documentation=https://github.com/AryanVBW/HYN-view

[Timer]
$spec
RandomizedDelaySec=$jitter
AccuracySec=30s
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
# Comma separated, tried in order, all of them are attempted:
#   resend | brevo | smtp | telegram | ntfy | webhook | stdout
# API keys and tokens do NOT go here. They live in $HYN_ETC/secrets (mode 0600).
# Run \`sudo hyn setup\` for the guided version of all of this.
notify_channels=${CFG[notify_channels]}
notify_to=${CFG[notify_to]}
notify_from=${CFG[notify_from]}
notify_from_name=${CFG[notify_from_name]}
# Hard backstop against a flapping condition burning a provider's daily quota.
notify_max_per_day=${CFG[notify_max_per_day]}
notify_timeout=${CFG[notify_timeout]}
smtp_host=${CFG[smtp_host]}
smtp_port=${CFG[smtp_port]}
telegram_chat_id=${CFG[telegram_chat_id]}
ntfy_topic=${CFG[ntfy_topic]}
ntfy_server=${CFG[ntfy_server]}

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
# off | check (default, tells you) | install (unattended npm i -g as root)
auto_update=${CFG[auto_update]}
update_check_hours=${CFG[update_check_hours]}
EOF
}

setup_run() {
  local no_timer=0 wizard=1 a
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
    setup_timers "$exe"
  fi

  # The wizard runs last, so a failure in it leaves a working install behind.
  if ((wizard)) && [[ -t 0 && -t 1 ]]; then
    source "$HYN_LIB/wizard.sh" 2>/dev/null || warn 'could not load the setup wizard'
    if declare -F wizard_run >/dev/null; then
      wizard_run || warn 'wizard did not complete; run `sudo hyn setup` again to finish'
      setup_apply_schedule "$exe"
    fi
  elif ((wizard)); then
    printf '\nhyn: not a terminal, so the guided setup was skipped.\n'
    printf '     run `sudo hyn setup` from a shell to configure notifications.\n'
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

# Installs all four timers. Split out so `hyn setup` and a schedule change after
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
  _write_unit /etc/systemd/system/hyn-alerts.service \
    "$(_generic_service 'hyn-view alert evaluation' "$exe alerts check --quiet")"
  _write_unit /etc/systemd/system/hyn-alerts.timer \
    "$(_generic_timer 'hyn-view alert evaluation' \
      "OnBootSec=3min"$'\n'"OnUnitActiveSec=${CFG[alert_interval_min]}min" 'hyn-alerts.service' 20)"

  # Metric recording for the daily report.
  _write_unit /etc/systemd/system/hyn-record.service \
    "$(_generic_service 'hyn-view metric sampling' "$exe record")"
  _write_unit /etc/systemd/system/hyn-record.timer \
    "$(_generic_timer 'hyn-view metric sampling' \
      "OnBootSec=2min"$'\n'"OnUnitActiveSec=${CFG[record_interval_min]}min" 'hyn-record.service' 20)"

  # Daily report.
  _write_unit /etc/systemd/system/hyn-report.service \
    "$(_generic_service 'hyn-view daily report' "$exe report --send")"
  _write_unit /etc/systemd/system/hyn-report.timer \
    "$(_generic_timer 'hyn-view daily report' \
      "OnCalendar=*-*-* ${CFG[report_at]}:00" 'hyn-report.service' 300)"

  # Web portal push. Same cadence as recording by default: the dashboard is only
  # as fresh as this timer, and a 5 minute lag is what the report timer already
  # accepts as the resolution worth keeping.
  _write_unit /etc/systemd/system/hyn-push.service \
    "$(_generic_service 'hyn-view web portal push' "$exe push")"
  _write_unit /etc/systemd/system/hyn-push.timer \
    "$(_generic_timer 'hyn-view web portal push' \
      "OnBootSec=4min"$'\n'"OnUnitActiveSec=${CFG[cloud_push_min]}min" 'hyn-push.service' 30)"

  systemctl daemon-reload
  setup_apply_schedule "$exe"
  return 0
}

_write_unit() {
  local path=$1 content=$2
  printf '%s\n' "$content" >"$path.tmp" && mv -f "$path.tmp" "$path" || die "cannot write $path"
  chmod 0644 "$path"
  printf '  %-34s written\n' "$path"
  return 0
}

# Enables or disables each timer according to config. Called again after the
# wizard so answering "no daily report" actually stops the timer.
setup_apply_schedule() {
  have systemctl || return 0
  systemctl daemon-reload
  _toggle_timer "$SVC_NAME.timer" 1
  _toggle_timer hyn-record.timer 1
  _toggle_timer hyn-alerts.timer "$(cfg_on alert_enabled && [[ -n ${CFG[notify_channels]} ]] && printf 1 || printf 0)"
  _toggle_timer hyn-report.timer "$(cfg_on report_enabled && [[ -n ${CFG[notify_channels]} ]] && printf 1 || printf 0)"
  # Only if the node is actually paired. An enabled push timer on an unlinked
  # node would fail every few minutes and fill the journal with noise that looks
  # like a bug rather than an unfinished setup step.
  _toggle_timer hyn-push.timer "$(cfg_on cloud_enabled && cloud_linked && printf 1 || printf 0)"
  return 0
}

_toggle_timer() {
  local unit=$1 want=${2:-0}
  if [[ $want == 1 ]]; then
    if systemctl enable --now "$unit" >/dev/null 2>&1; then
      printf '  %-34s enabled\n' "$unit"
    else
      printf '  %-34s could not enable (systemctl status %s)\n' "$unit" "$unit"
    fi
  else
    systemctl disable --now "$unit" >/dev/null 2>&1
    printf '  %-34s disabled (not configured)\n' "$unit"
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
    for u in "$SVC_NAME.timer" hyn-alerts.timer hyn-record.timer hyn-report.timer hyn-push.timer; do
      systemctl disable --now "$u" >/dev/null 2>&1 && printf '  %-24s disabled\n' "$u"
    done
    rm -f "$SVC_PATH" "$TMR_PATH" \
      /etc/systemd/system/hyn-alerts.service /etc/systemd/system/hyn-alerts.timer \
      /etc/systemd/system/hyn-record.service /etc/systemd/system/hyn-record.timer \
      /etc/systemd/system/hyn-report.service /etc/systemd/system/hyn-report.timer \
      /etc/systemd/system/hyn-push.service /etc/systemd/system/hyn-push.timer
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
