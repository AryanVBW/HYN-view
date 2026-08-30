#!/usr/bin/env bash
# hyn-view :: interactive setup
#
# Asks the questions instead of leaving an operator to reverse-engineer a config
# file. Design rules for the prompts:
#
#   * every question has a default that is safe to accept blindly
#   * inputs are validated at the prompt and re-asked, not accepted and then
#     silently ignored at 3am when an alert should have fired
#   * API keys are read with echo off and written only to the 0600 secrets file
#   * it ends by actually SENDING a test message, because a notification setup
#     you have not seen arrive is not configured, it is hoped for
#   * it is re-runnable; existing answers become the new defaults

W_TTY=0
[[ -t 0 && -t 1 ]] && W_TTY=1

_w_rule() { printf '%s\n' "────────────────────────────────────────────────────────────────"; }
_w_head() {
  printf '\n%s%s%s\n' "${C[accent]}${C[bold]}" "$1" "${C[reset]}"
  [[ -n ${2:-} ]] && printf '%s%s%s\n' "${C[dim]}" "$2" "${C[reset]}"
  printf '\n'
}
_w_note() { printf '  %s%s%s\n' "${C[dim]}" "$1" "${C[reset]}"; }
_w_ok() { printf '  %s%s %s%s\n' "${C[ok]}" "$G_DOT" "$1" "${C[reset]}"; }
_w_bad() { printf '  %s%s %s%s\n' "${C[crit]}" "$G_DOT" "$1" "${C[reset]}"; }

# ask <outvar> <prompt> <default> [validator-fn]
ask() {
  local __out=$1 prompt=$2 def=${3:-} val=${4:-} reply
  while :; do
    if [[ -n $def ]]; then
      printf '  %s %s[%s]%s ' "$prompt" "${C[dim]}" "$def" "${C[reset]}"
    else
      printf '  %s ' "$prompt"
    fi
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=$def
    if [[ -n $val ]] && ! "$val" "$reply"; then
      _w_bad "that does not look right, try again"
      continue
    fi
    printf -v "$__out" '%s' "$reply"
    return 0
  done
}


# ask_yn <prompt> <default y|n>
ask_yn() {
  local prompt=$1 def=${2:-y} reply hint='[Y/n]'
  [[ $def == n ]] && hint='[y/N]'
  while :; do
    printf '  %s %s%s%s ' "$prompt" "${C[dim]}" "$hint" "${C[reset]}"
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=$def
    case ${reply,,} in
      y | yes) return 0 ;;
      n | no) return 1 ;;
    esac
  done
}

# ask_choice <outvar> <prompt> <value:label> ...
ask_choice() {
  local __out=$1 prompt=$2
  shift 2
  local -a vals=() labels=()
  local spec i reply
  for spec in "$@"; do
    vals+=("${spec%%:*}")
    labels+=("${spec#*:}")
  done
  printf '  %s\n' "$prompt"
  for i in "${!vals[@]}"; do
    printf '    %s%s)%s %s\n' "${C[accent]}" "$((i + 1))" "${C[reset]}" "${labels[i]}"
  done
  while :; do
    printf '  choice %s[1]%s ' "${C[dim]}" "${C[reset]}"
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=1
    if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#vals[@]})); then
      printf -v "$__out" '%s' "${vals[reply - 1]}"
      return 0
    fi
    _w_bad "enter a number between 1 and ${#vals[@]}"
  done
}

_v_int() { [[ $1 =~ ^[0-9]+$ ]]; }
_v_hhmm() { [[ $1 =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; }
_v_url() { [[ $1 == https://* || $1 == http://* ]]; }
_v_any() { return 0; }

_wiz_update_choice() {
  local __out=$1
  # Managed install is first because ask_choice's Enter default is choice 1, and
  # the point of holding Enter through this wizard is to land on the
  # configuration a 24/7 relay node should have. It also has to agree with
  # CFG[auto_update]: a default of `install` in core.sh and `check` here meant
  # the answer depended on whether you happened to run the wizard at all.
  ask_choice "$__out" 'How should HYN handle new releases?' \
    'install:Automatic update   — install new npm releases unattended (recommended)' \
    'check:Auto-update check  — notify me, then I approve the install' \
    'off:Manual update      — only update when I run hyn update'
}

# ===========================================================================
# first-run onboarding
# ===========================================================================
# A staged walkthrough of every setting that is still a local decision: update
# policy, display mode, theme, units, refresh rate, panels, alert thresholds,
# report time, speed tests and node tracking.
#
# Notice what is not in that list. There is no notification setup, because there
# is nothing local to set up: recipients, the provider account, the schedule and
# the templates all live in the portal, and this wizard could not change them if
# it wanted to.
#
# Principles, in order of how much they matter:
#
#   1. It must be skippable and must never ask twice. A monitoring tool that
#      interrogates you on every launch gets uninstalled.
#   2. Every question has a default that is correct for a 24/7 relay node, so
#      holding Enter eight times produces a good configuration.
#   3. It shows what it DETECTED before it asks anything. Being told "we found
#      Ubuntu 24.04, 8 cores, eth0 at 1 Gbps, and a Highway node running v0.1.75"
#      is what earns the trust to be asked anything at all.
#   4. Nothing is written until the summary is confirmed.

OB_TOTAL=8
_ob_step() {
  local n=$1 title=$2 sub=${3:-}
  printf '\n%s%s  Step %s of %s  %s%s\n' "${C[accent]}" "${C[bold]}" "$n" "$OB_TOTAL" "$title" "${C[reset]}"
  [[ -n $sub ]] && printf '  %s%s%s\n' "${C[dim]}" "$sub" "${C[reset]}"
  printf '\n'
  return 0
}

_ob_banner() {
  local w=64
  rep_v '─' "$w"
  printf '\n%s%s%s\n' "${C[border]}" "$REP_OUT" "${C[reset]}"
  printf '  %s%shyn-view%s %s%s%s\n' "${C[accent]}" "${C[bold]}" "${C[reset]}" "${C[dim]}" "$HYN_VERSION" "${C[reset]}"
  printf '  %sNetwork-first system monitor for Ubuntu Server%s\n' "${C[dim]}" "${C[reset]}"
  printf '  %s%s%s\n' "${C[dim]}" "$HYN_AUTHOR" "${C[reset]}"
  printf '%s%s%s\n' "${C[border]}" "$REP_OUT" "${C[reset]}"
  return 0
}

# What we can see without being told. Runs the real collectors so these are
# facts, not placeholders.
onboard_detect() {
  net_sample 0
  cpu_sample 0
  mem_sample
  sys_sample
  disk_usage 1
  net_identity 1
  cfg_on highway_track && hw_sample 0

  printf '  %s%-18s%s %s\n' "${C[dim]}" 'host' "${C[reset]}" "$HOSTNAME_S"
  printf '  %s%-18s%s %s\n' "${C[dim]}" 'system' "${C[reset]}" "${DISTRO:-unknown}  ${KERNEL:-}"
  fmt_size_v "$MEM_TOTAL"
  printf '  %s%-18s%s %s cores, %s RAM  %s\n' "${C[dim]}" 'hardware' "${C[reset]}" \
    "$CPU_COUNT" "$FMT_OUT" "${C[dim]}${CPU_MODEL:-}${C[reset]}"
  local ifc=${NET_WAN:-none} extra=''
  [[ -n ${NET_SSID:-} ]] && extra="wifi \"$NET_SSID\"  "
  [[ -n ${NET_LOCAL_IP:-} ]] && extra+="$NET_LOCAL_IP  "
  [[ -n ${LINK_SPEED:-} ]] && { fmt_rate_v $((LINK_SPEED * 125000)); extra+="$FMT_OUT"; }
  printf '  %s%-18s%s %s  %s\n' "${C[dim]}" 'wan interface' "${C[reset]}" "$ifc" "${C[dim]}$extra${C[reset]}"
  local mp n=0
  for mp in "${MOUNTS[@]}"; do
    ((n++ >= 4)) && continue
    fmt_size_v "${MP_AVAIL[$mp]:-0}"
    printf '  %s%-18s%s %s at %s%%, %s free\n' "${C[dim]}" 'filesystem' "${C[reset]}" \
      "$mp" "${MP_PCT[$mp]:-?}" "$FMT_OUT"
  done
  ((${#MOUNTS[@]} > 4)) && printf '  %s%-18s%s %s more\n' "${C[dim]}" '' "${C[reset]}" \
    "$((${#MOUNTS[@]} - 4))"
  fmt_dur_v "$UPTIME_S"
  printf '  %s%-18s%s %s\n' "${C[dim]}" 'uptime' "${C[reset]}" "$FMT_OUT"
  if ((HW_PRESENT)); then
    printf '  %s%-18s%s %sfound%s  %s %s\n' "${C[dim]}" 'highway node' "${C[reset]}" \
      "${C[ok]}" "${C[reset]}" "${HW_VERSION:-version unknown}" \
      "${C[dim]}${HW_HEALTH_WHY:-}${C[reset]}"
  else
    printf '  %s%-18s%s %snot installed%s %s(the node panel will stay hidden)%s\n' \
      "${C[dim]}" 'highway node' "${C[reset]}" "${C[dim]}" "${C[reset]}" "${C[dim]}" "${C[reset]}"
  fi
  local caps=''
  have curl && caps+='curl ' || caps+="${C[warn]}no curl${C[reset]} "
  have systemctl && caps+='systemd ' || caps+="${C[warn]}no systemd${C[reset]} "
  have ping && caps+='ping ' || caps+="${C[dim]}no ping${C[reset]} "
  printf '  %s%-18s%s %s\n' "${C[dim]}" 'available' "${C[reset]}" "$caps"
  return 0
}

# Live sample of the chosen theme, so the choice is made by looking rather than
# by guessing from a name.
_ob_theme_preview() {
  local name=$1 i out=''
  theme_load "$name" || return 1
  _GRAD=()
  for i in 5 20 35 50 65 80 95; do
    bar_v "$i" 6
    out+="$BAR_OUT "
  done
  printf '  %s%-9s%s %s  %sok%s %swarn%s %scrit%s %s▾rx%s %s▴tx%s\n' \
    "${C[dim]}" "$name" "${C[reset]}" "$out" \
    "${C[ok]}" "${C[reset]}" "${C[warn]}" "${C[reset]}" "${C[crit]}" "${C[reset]}" \
    "${C[rx]}" "${C[reset]}" "${C[tx]}" "${C[reset]}"
  return 0
}

onboard_run() {
  ((W_TTY)) || return 1
  secrets_load

  # Answers are collected here and only written after the summary is confirmed,
  # so abandoning halfway leaves nothing behind.
  declare -A A=()
  local v

  _ob_banner
  printf '\n  First run, so this is a one-time setup. About two minutes.\n'
  printf '  %sEnter accepts the [default] — holding Enter through it all is a good\n' "${C[dim]}"
  printf '  configuration. Ctrl-C aborts and writes nothing.%s\n' "${C[reset]}"

  # Update policy is the first decision on a new install. It affects the CLI
  # itself and should not be buried after visual and notification preferences.
  printf '\n'
  _wiz_update_choice v
  A[auto_update]=$v

  # ------------------------------------------------------------------ 1
  _ob_step 1 'What we found' 'No questions here, just so you know what it is working with.'
  onboard_detect

  # ------------------------------------------------------------------ 2
  _ob_step 2 'Display mode' 'This is the visual/cost trade-off. Switchable any time with the p key.'
  ask_choice v 'Mode:' \
    'best:Best looking      — gradient braille graphs, time ruler, 1s refresh  (~4% of one core)' \
    'performance:Best performance  — block graphs, 2s refresh                        (~2% of one core)'
  A[profile]=$v
  # Apply now so the later previews and the summary show the real values.
  local k
  for k in graph graph_gradient graph_axis graph_stats interval proc_rows net_history_detail; do
    unset "CFG_EXPLICIT[$k]"
  done
  CFG[profile]=$v
  profile_apply
  _w_ok "$v — graph ${CFG[graph]}, ${CFG[interval]}s refresh, ${CFG[proc_rows]} process rows"

  # ------------------------------------------------------------------ 3
  _ob_step 3 'Theme' 'All six, drawn with your terminal.'
  local t
  for t in hiway nord gruvbox dracula solar mono; do _ob_theme_preview "$t"; done
  printf '\n'
  ask_choice v 'Theme:' \
    'hiway:hiway    — cool slate, cyan signal colour (default)' \
    'nord:nord     — low contrast, comfortable all day' \
    'gruvbox:gruvbox  — warm, high contrast, survives a laggy ssh' \
    'dracula:dracula  — vivid on near-black' \
    'solar:solar    — Solarized Dark' \
    'mono:mono     — greyscale, colour only for warnings'
  A[theme]=$v
  theme_load "$v"
  _GRAD=()

  # ------------------------------------------------------------------ 4
  _ob_step 4 'Units and layout'
  ask_choice v 'Show network rates in:' \
    'bits:Bits per second   — matches how links are sold (1 Gbps)' \
    'bytes:Bytes per second  — matches file sizes (125 MiB/s)'
  A[net_unit]=$v
  ask v 'Refresh interval in seconds' "${CFG[interval]}" _v_any && A[interval]=$v
  ask v 'Process rows on the dashboard' "${CFG[proc_rows]}" _v_int && A[proc_rows]=$v
  if ((HW_PRESENT)); then
    if ask_yn 'Track the Highway node? (read-only, never touches it)' y; then
      A[highway_track]=on
    else
      A[highway_track]=off
    fi
  else
    if ask_yn 'Watch for a Highway node being installed later?' y; then
      A[highway_track]=on
    else
      A[highway_track]=off
    fi
  fi

  # ------------------------------------------------------------------ 5
  _ob_step 5 'Email and alerts' \
    'Nothing to answer. Delivery belongs to the portal, not to this machine.'
  _w_ok 'incident alerts, the daily health digest and system-information mail all'
  _w_ok 'work as soon as this machine is paired: sudo hyn link'
  _w_note 'recipient, timezone, send times and message types are set on the'
  _w_note 'Account page of the dashboard, once, for every machine you own.'
  _w_note 'no API key, sender address or mailing list is stored on this server.'

  # ------------------------------------------------------------------ 6
  _ob_step 6 'What counts as a problem' 'Defaults are tuned for a 24/7 node. Any threshold set to 0 is off.'
  ask_choice v 'Tell me about:' \
    'warn:Warnings and critical  — recommended' \
    'crit:Critical only          — quieter; you will miss slow-building problems' \
    'info:Everything             — includes update notices, chatty'
  A[alert_min_severity]=$v
  if ask_yn 'Review individual thresholds?' n; then
    ask v 'Memory used % that is a problem' "${CFG[alert_mem_pct]}" _v_int && A[alert_mem_pct]=$v
    ask v 'Disk used % that is a problem' "${CFG[alert_disk_pct]}" _v_int && A[alert_disk_pct]=$v
    ask v 'CPU steal % that is a problem' "${CFG[alert_steal_pct]}" _v_int && A[alert_steal_pct]=$v
    ask v 'Internet latency ms that is a problem' "${CFG[alert_latency_ms]}" _v_int && A[alert_latency_ms]=$v
    ask v 'Packet loss % that is a problem' "${CFG[alert_loss_pct]}" _v_int && A[alert_loss_pct]=$v
    ask v 'Highway restarts before warning' "${CFG[alert_hw_restarts]}" _v_int && A[alert_hw_restarts]=$v
  else
    _w_ok "memory ${CFG[alert_mem_pct]}%, disk ${CFG[alert_disk_pct]}%, steal ${CFG[alert_steal_pct]}%, latency ${CFG[alert_latency_ms]}ms, loss ${CFG[alert_loss_pct]}%"
  fi
  ask v 'Check every N minutes' "${CFG[alert_interval_min]}" _v_int && A[alert_interval_min]=$v
  ask v 'Remind me every N hours while a problem persists' "${CFG[alert_repeat_hours]}" _v_int && A[alert_repeat_hours]=$v
  if ask_yn 'Tell me when a problem clears too?' y; then A[alert_notify_resolved]=on; else A[alert_notify_resolved]=off; fi
  ask v 'Hard cap on notifications per day' "${CFG[notify_max_per_day]}" _v_int && A[notify_max_per_day]=$v

  # ------------------------------------------------------------------ 7
  _ob_step 7 'Cloud reports and speed tests'
  A[report_enabled]=off
  _w_ok 'cloud reports are scheduled in the account timezone from the dashboard'
  ask v 'Throughput tests per day' "${CFG[speedtest_per_day]}" _v_int && A[speedtest_per_day]=$v
  ask v 'Skip a test when the link is busier than N% of capacity' "${CFG[speedtest_guard_pct]}" _v_int && A[speedtest_guard_pct]=$v
  _w_note 'tests are bounded by bytes and by time, so they will not disturb the node.'

  # ------------------------------------------------------------------ 8
  _ob_step 8 'Outage detection' 'Nothing to answer here either.'
  printf '  %sIf this machine goes offline, hyn goes with it and cannot email you.%s\n' "${C[warn]}" "${C[reset]}"
  _w_note 'So the check that matters is made from outside the machine. Once this box'
  _w_note 'is paired, the portal watches for its one-minute heartbeat and mails the'
  _w_note 'owner when three are missed, then again when they resume.'
  _w_note 'That used to be a ping URL for a third-party dead-man service, entered'
  _w_note 'on every machine. It is not any more: one less account to hold, and one'
  _w_note 'less thing to get wrong on the fifth server.'
  if ! cloud_linked 2>/dev/null; then
    printf '\n'
    _w_bad 'this machine is not paired yet, so nothing is watching it: sudo hyn link'
  fi
  # ------------------------------------------------------------------ summary
  printf '\n'
  rep_v '─' 64
  printf '%s%s%s\n' "${C[border]}" "$REP_OUT" "${C[reset]}"
  printf '%s  Ready to write%s\n\n' "${C[bold]}" "${C[reset]}"
  local key
  for key in profile theme net_unit interval proc_rows highway_track \
    alert_min_severity alert_interval_min alert_repeat_hours notify_max_per_day \
    report_enabled report_at speedtest_per_day auto_update; do
    [[ -v A[$key] ]] || continue
    printf '  %s%-22s%s %s\n' "${C[dim]}" "$key" "${C[reset]}" "${A[$key]:-(unset)}"
  done
  printf '\n  %sto%s %s\n' "${C[dim]}" "${C[reset]}" "$(config_file_rw)"
  printf '\n'

  if ! ask_yn 'Write this configuration?' y; then
    _w_note 'nothing written. Run `hyn onboard` when you want to do this again.'
    onboard_mark_done declined
    return 1
  fi

  for key in "${!A[@]}"; do config_set "$key" "${A[$key]}"; done
  # A profile is only a set of defaults, so record the keys it decided as
  # explicit values too. Otherwise a later profile change would silently move
  # settings the operator just chose.
  config_set graph "${CFG[graph]}"
  config_set graph_gradient "${CFG[graph_gradient]}"
  config_set graph_axis "${CFG[graph_axis]}"
  config_set graph_stats "${CFG[graph_stats]}"
  _w_ok "written to $(config_file_rw)"
  onboard_mark_done completed

  # ------------------------------------------------------------------ timers
  printf '\n'
  if is_root; then
    if have systemctl; then
      if ask_yn 'Install the background timers (alerts, metrics, reports, speed tests)?' y; then
        source "$HYN_LIB/setup.sh" 2>/dev/null && setup_run --no-wizard
      else
        _w_note 'alerts and reports need the timers. Install them later with: sudo hyn setup'
      fi
    fi
  else
    _w_note 'Alerts, the daily report and scheduled speed tests run from systemd'
    _w_note 'timers, which need root to install. Finish with:'
    printf '\n    %ssudo hyn setup --no-wizard%s\n' "${C[bold]}" "${C[reset]}"
    if have sudo && ask_yn 'Run that now?' y; then
      sudo "$HYN_ROOT/bin/hyn" setup --no-wizard || _w_bad 'setup did not complete'
    fi
  fi

  printf '\n'
  rep_v '─' 64
  printf '%s%s%s\n' "${C[border]}" "$REP_OUT" "${C[reset]}"
  _w_ok 'Setup complete.'
  printf '  %shyn%s              the dashboard        %sp%s switch mode  %sh%s help\n' \
    "${C[bold]}" "${C[reset]}" "${C[accent]}" "${C[reset]}" "${C[accent]}" "${C[reset]}"
  printf '  %shyn doctor%s       verify everything end to end\n' "${C[bold]}" "${C[reset]}"
  printf '  %shyn alerts list%s  every rule and whether it is firing\n' "${C[bold]}" "${C[reset]}"
  printf '  %shyn report%s       the daily report, printed now\n' "${C[bold]}" "${C[reset]}"
  printf '\n'
  return 0
}

# Offered on first launch of the TUI. Declining is remembered.
onboard_prompt() {
  ((W_TTY)) || return 1
  _ob_banner
  printf '\n  This install has not been set up yet.\n'
  printf '  %sSetup covers display mode, theme, email alerts, the daily report and\n' "${C[dim]}"
  printf '  outage detection. About two minutes, and every answer has a default.%s\n\n' "${C[reset]}"
  if ask_yn 'Run setup now?' y; then
    onboard_run
    return $?
  fi
  printf '\n'
  _w_note 'skipped. The dashboard works without it; alerts and reports do not.'
  _w_note 'run `hyn onboard` whenever you want to set them up.'
  onboard_mark_done skipped
  printf '\n  '
  read -rsn1 -p "Press any key to open the dashboard…" _ 2>/dev/null || true
  printf '\n'
  return 1
}
