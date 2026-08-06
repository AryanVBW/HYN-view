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

setup_config_template() {
  cat <<EOF
# hyn-view configuration
# Every key from \`hyn config show\` can be set here. Values shown are defaults.
# Reload happens on next start; there is no daemon to restart.

# --- appearance ---------------------------------------------------------------
theme=${CFG[theme]}
# refresh interval in seconds. 1.0 is comfortable; 2.0 or 3.0 is lighter still
# on a box where you care about every last cycle.
interval=${CFG[interval]}
# bits (default, matches how links are sold) or bytes
net_unit=${CFG[net_unit]}
# braille (highest resolution) | block (cheaper, coarser) | off
graph=${CFG[graph]}
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
EOF
}

setup_service_unit() {
  local exe=$1
  cat <<EOF
[Unit]
Description=hyn-view scheduled throughput measurement
Documentation=https://github.com/AryanVBW/HYN-view
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$exe speedtest --respect-guard --json
# Deprioritised on every axis. This is monitoring; it yields to the workload
# the machine actually exists to run.
Nice=15
IOSchedulingClass=idle
CPUSchedulingPolicy=batch
TimeoutStartSec=180

# Runs as root so that the scheduled result and a manual \`sudo hyn speedtest\`
# write the same history file with the same ownership. Everything root does not
# need is taken away below.
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$HYN_VAR
PrivateTmp=yes
PrivateDevices=yes
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
CapabilityBoundingSet=
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF
}

setup_timer_unit() {
  local cal=$1
  cat <<EOF
[Unit]
Description=hyn-view scheduled throughput measurement
Documentation=https://github.com/AryanVBW/HYN-view

[Timer]
OnCalendar=$cal
# Spread across a 15 minute window. A lot of operators run the same installer;
# a fleet all testing at the same second is a self-inflicted traffic spike.
RandomizedDelaySec=900
AccuracySec=1min
Persistent=true
Unit=$SVC_NAME.service

[Install]
WantedBy=timers.target
EOF
}

setup_run() {
  local no_timer=0 a
  for a in "$@"; do
    case $a in
      --no-timer) no_timer=1 ;;
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

  # A convenience symlink so `hyn` works for every user even when npm's global
  # bin dir is not on root's PATH (a very common sudo surprise).
  if [[ ! -e /usr/local/bin/hyn ]]; then
    ln -s "$exe" /usr/local/bin/hyn 2>/dev/null \
      && printf '  %-34s linked\n' '/usr/local/bin/hyn'
  fi

  if ((no_timer)); then
    printf '\nhyn: skipped the timer (--no-timer)\n'
  elif ! have systemctl; then
    printf '\nhyn: no systemd here, skipping the timer\n'
  else
    local cal
    cal=$(st_calendar "${CFG[speedtest_per_day]}")
    setup_service_unit "$exe" >"$SVC_PATH.tmp" && mv -f "$SVC_PATH.tmp" "$SVC_PATH" || die "cannot write $SVC_PATH"
    setup_timer_unit "$cal" >"$TMR_PATH.tmp" && mv -f "$TMR_PATH.tmp" "$TMR_PATH" || die "cannot write $TMR_PATH"
    chmod 0644 "$SVC_PATH" "$TMR_PATH"
    printf '  %-34s written\n' "$SVC_PATH"
    printf '  %-34s written\n' "$TMR_PATH"
    systemctl daemon-reload
    systemctl enable --now "$SVC_NAME.timer" >/dev/null 2>&1 \
      && printf '  %-34s enabled (%s)\n' "$SVC_NAME.timer" "$cal" \
      || printf '  %-34s %s\n' "$SVC_NAME.timer" 'could not enable -- see: systemctl status hyn-speedtest.timer'
  fi

  printf '\nhyn: done. Next steps:\n'
  printf '  hyn                 open the dashboard\n'
  printf '  hyn doctor          verify the environment\n'
  printf '  hyn speedtest       take the first measurement now\n'
  if ! ((no_timer)) && have systemctl; then
    printf '  systemctl list-timers %s.timer\n' "$SVC_NAME"
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
    systemctl disable --now "$SVC_NAME.timer" >/dev/null 2>&1 && printf '  timer disabled\n'
    rm -f "$SVC_PATH" "$TMR_PATH"
    systemctl daemon-reload
    printf '  units removed\n'
  fi
  [[ -L /usr/local/bin/hyn ]] && rm -f /usr/local/bin/hyn && printf '  /usr/local/bin/hyn unlinked\n'

  if ((purge)); then
    # Only with --purge, and only these two paths: config and recorded history
    # are the user's data, not ours to delete by default.
    rm -rf "$HYN_ETC" "$HYN_VAR"
    printf '  %s and %s removed\n' "$HYN_ETC" "$HYN_VAR"
  else
    printf '  kept %s and %s (use --purge to remove)\n' "$HYN_ETC" "$HYN_VAR"
  fi
  printf '\nhyn: the command itself is managed by npm: npm rm -g hyn-view\n'
  return 0
}
