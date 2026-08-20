#!/usr/bin/env bash
# hyn-view :: alert engine
#
# Runs headless from a systemd timer, so alerting works whether or not anyone
# has the dashboard open. That is the whole point: a monitor you have to be
# watching is not a monitor.
#
# Three behaviours do the heavy lifting, and all three exist because the naive
# version of this feature is worse than no feature at all:
#
#   1. HYSTERESIS. A rule fires at its threshold and clears at a lower one. A
#      single threshold means a value sitting on the line flaps firing/clear/
#      firing and mails you every cycle.
#   2. COOLDOWN. A condition that is still true is re-notified at most once per
#      alert_repeat (default 6h), not once per run.
#   3. DIGEST. One run sends ONE message listing everything, not one message per
#      rule. A server with a full disk usually trips several rules at once, and
#      six emails about one incident trains you to ignore them.
#
# State lives in $STATE/alert-state as TSV: id, state, since, last_notified, value

declare -a AL_ID=() AL_SEV=() AL_MSG=() AL_NEW=() AL_VAL=()
declare -a AL_RESOLVED=()
declare -A _AL_PREV_STATE=() _AL_PREV_SINCE=() _AL_PREV_NOTIFIED=()
declare -A _AL_SEEN=()
AL_CRIT=0 AL_WARN=0 AL_INFO=0 AL_FIRING=0 AL_NOTIFY=0

_sev_rank() {
  case $1 in
    crit) printf 3 ;;
    warn) printf 2 ;;
    info) printf 1 ;;
    *) printf 0 ;;
  esac
}

alert_state_file() {
  state_dir_v
  printf '%s/alert-state' "$STATE_DIR"
}

alerts_state_load() {
  local f id st since notified val
  f=$(alert_state_file)
  _AL_PREV_STATE=() _AL_PREV_SINCE=() _AL_PREV_NOTIFIED=()
  [[ -r $f ]] || return 0
  while IFS=$'\t' read -r id st since notified val; do
    [[ -n $id ]] || continue
    _AL_PREV_STATE[$id]=$st
    _AL_PREV_SINCE[$id]=${since:-0}
    _AL_PREV_NOTIFIED[$id]=${notified:-0}
  done <"$f"
  return 0
}

alerts_state_save() {
  local f tmp i id
  f=$(alert_state_file)
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  tmp="$f.tmp.$$"
  : >"$tmp" || return 1
  for ((i = 0; i < ${#AL_ID[@]}; i++)); do
    id=${AL_ID[i]}
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" firing \
      "${_AL_PREV_SINCE[$id]:-${EPOCHSECONDS:-0}}" \
      "${_AL_PREV_NOTIFIED[$id]:-0}" "${AL_VAL[i]}" >>"$tmp"
  done
  # Keep a short memory of resolved rules so a recovery is reported once and not
  # on every subsequent run.
  for id in "${!_AL_PREV_STATE[@]}"; do
    [[ -v _AL_SEEN[$id] ]] && continue
    [[ ${_AL_PREV_STATE[$id]} == resolved ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" resolved "${EPOCHSECONDS:-0}" \
      "${_AL_PREV_NOTIFIED[$id]:-0}" '' >>"$tmp"
  done
  mv -f "$tmp" "$f"
  return 0
}

# ---------------------------------------------------------------------------
# rule primitives
# ---------------------------------------------------------------------------
# _check_num <id> <sev> <value> <fire-at> <clear-at> <message>
# "Higher is worse" numeric rule with hysteresis.
_check_num() {
  local id=$1 sev=$2 value=$3 fire=$4 clear=$5 msg=$6
  [[ $value =~ ^-?[0-9]+$ ]] || return 0
  [[ $fire =~ ^-?[0-9]+$ ]] || return 0
  ((fire <= 0)) && return 0
  [[ $clear =~ ^-?[0-9]+$ ]] || clear=$fire
  _AL_SEEN[$id]=1
  local was=${_AL_PREV_STATE[$id]:-ok} firing=0
  if [[ $was == firing ]]; then
    # Already firing: needs to drop below the clear threshold to stand down.
    ((value >= clear)) && firing=1
  else
    ((value >= fire)) && firing=1
  fi
  _record "$id" "$sev" "$firing" "$value" "$msg"
}

# _check_bool <id> <sev> <firing 0|1> <message>
_check_bool() {
  local id=$1 sev=$2 firing=$3 msg=$4
  _AL_SEEN[$id]=1
  _record "$id" "$sev" "$firing" "$firing" "$msg"
}

_record() {
  local id=$1 sev=$2 firing=$3 value=$4 msg=$5
  local was=${_AL_PREV_STATE[$id]:-ok} now=${EPOCHSECONDS:-0}
  if ((firing)); then
    ((AL_FIRING++))
    case $sev in
      crit) ((AL_CRIT++)) ;;
      warn) ((AL_WARN++)) ;;
      *) ((AL_INFO++)) ;;
    esac
    local isnew=0
    [[ $was != firing ]] && isnew=1
    ((isnew)) && _AL_PREV_SINCE[$id]=$now
    AL_ID+=("$id") AL_SEV+=("$sev") AL_MSG+=("$msg") AL_NEW+=("$isnew") AL_VAL+=("$value")
  else
    # firing -> ok is a recovery worth reporting, but only if we told them about
    # it in the first place.
    if [[ $was == firing ]] && ((${_AL_PREV_NOTIFIED[$id]:-0} > 0)); then
      AL_RESOLVED+=("$id|$msg")
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# collection
# ---------------------------------------------------------------------------
# Two samples a second apart, because rates are deltas. Same reason `hyn
# snapshot` does it.
alerts_collect() {
  net_sample 0
  cpu_sample 0
  disk_sample 0
  sleep 1
  net_sample 1000
  net_snmp 1000
  net_sockstat
  cpu_sample 1000
  mem_sample
  sys_sample
  disk_sample 1000
  psi_sample
  thermal_read
  cpu_freq_read
  cpu_freq_all
  sensors_read
  proc_count_read
  disk_usage 1
  net_conntrack
  net_latency_read
  cfg_on tcp_states && net_tcp_states
  sys_failed_units
  cfg_on highway_track && hw_sample 1000
  st_history_read 1
  net_retrans_permille
  sys_whoami
  sys_sessions 1
  return 0
}

# ---------------------------------------------------------------------------
# system probes that only the alert path needs
# ---------------------------------------------------------------------------
# Root filesystem mounted read-only is close to the worst thing that can quietly
# happen to a node: it keeps running and fails every write.
ROOT_RO=0
check_root_ro() {
  local dev mp fstype opts rest
  ROOT_RO=0
  [[ -r $HYN_PROC/mounts ]] || return 0
  while read -r dev mp fstype opts rest; do
    [[ $mp == / ]] || continue
    case ,$opts, in
      *,ro,*) ROOT_RO=1 ;;
    esac
    break
  done <"$HYN_PROC/mounts" 2>/dev/null
  return 0
}

# OOM kills since the last run. The kernel log is the only reliable record, and
# an OOM is worth knowing about even after the box recovered on its own.
OOM_COUNT=0 OOM_LAST=''
check_oom() {
  OOM_COUNT=0 OOM_LAST=''
  have journalctl || return 0
  local since=${CFG[alert_interval_min]:-5}
  [[ $since =~ ^[0-9]+$ ]] || since=5
  local line
  while IFS= read -r line; do
    case $line in
      *'Out of memory'* | *'oom-kill'* | *'Killed process'*)
        ((OOM_COUNT++))
        OOM_LAST=${line:0:160}
        ;;
    esac
  done < <(journalctl -k --since "-$((since + 1)) min" --no-pager -o cat 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# the rules
# ---------------------------------------------------------------------------
# Adding a rule is one line. Thresholds all come from config so an operator can
# retune without editing code.
alerts_evaluate() {
  local t c
  AL_ID=() AL_SEV=() AL_MSG=() AL_NEW=() AL_VAL=() AL_RESOLVED=()
  AL_CRIT=0 AL_WARN=0 AL_INFO=0 AL_FIRING=0
  _AL_SEEN=()

  # --- memory ---
  t=${CFG[alert_mem_pct]}
  fmt_size_v "$MEM_USED"; local mu=$FMT_OUT
  fmt_size_v "$MEM_TOTAL"
  _check_num mem_high warn "$MEM_PCT" "$t" $((t - 8)) \
    "Memory at ${MEM_PCT}% ($mu of $FMT_OUT used)"
  _check_num mem_crit crit "$MEM_PCT" "${CFG[alert_mem_crit_pct]}" $((${CFG[alert_mem_crit_pct]} - 4)) \
    "Memory critically high at ${MEM_PCT}% ($mu of $FMT_OUT)"
  if ((SWAP_TOTAL > 0)); then
    fmt_size_v "$SWAP_USED"
    _check_num swap_high warn "$SWAP_PCT" "${CFG[alert_swap_pct]}" $((${CFG[alert_swap_pct]} - 10)) \
      "Swap at ${SWAP_PCT}% ($FMT_OUT) — the box is under memory pressure"
  fi

  # --- storage ---
  local mp pct
  for mp in "${MOUNTS[@]}"; do
    pct=${MP_PCT[$mp]:-0}
    fmt_size_v "${MP_AVAIL[$mp]:-0}"
    local safe=${mp//[^A-Za-z0-9]/_}
    _check_num "disk_${safe}" warn "$pct" "${CFG[alert_disk_pct]}" $((${CFG[alert_disk_pct]} - 5)) \
      "Disk $mp at ${pct}% ($FMT_OUT free)"
    _check_num "diskcrit_${safe}" crit "$pct" "${CFG[alert_disk_crit_pct]}" $((${CFG[alert_disk_crit_pct]} - 3)) \
      "Disk $mp critically full at ${pct}% (only $FMT_OUT free)"
  done
  check_root_ro
  _check_bool fs_readonly crit "$ROOT_RO" 'Root filesystem is mounted READ-ONLY — writes are failing'

  # --- cpu ---
  # Load is normalised per core, otherwise the threshold is meaningless across
  # a 2-core VPS and a 64-core box.
  if [[ ${LOAD1:-} =~ ^[0-9.]+$ ]] && ((CPU_COUNT > 0)); then
    parse_fixed3_v "$LOAD1"
    local per=$((FIX3 * 100 / 1000 / CPU_COUNT))
    _check_num load_high warn "$per" "${CFG[alert_load_per_core]}" $((${CFG[alert_load_per_core]} - 100)) \
      "Load average ${LOAD1} over ${CPU_COUNT} cores (${per}% per core)"
  fi
  _check_num cpu_steal warn "$CPU_STEAL" "${CFG[alert_steal_pct]}" $((${CFG[alert_steal_pct]} - 5)) \
    "CPU steal at ${CPU_STEAL}% — the hypervisor is not giving us the CPU we pay for"
  _check_num cpu_iowait warn "$CPU_IOWAIT" "${CFG[alert_iowait_pct]}" $((${CFG[alert_iowait_pct]} - 10)) \
    "CPU iowait at ${CPU_IOWAIT}% — storage is the bottleneck"
  if [[ -n ${CPU_TEMP:-} ]]; then
    _check_num temp_high warn "$CPU_TEMP" "${CFG[alert_temp_c]}" $((${CFG[alert_temp_c]} - 6)) \
      "CPU temperature ${CPU_TEMP}°C"
  fi

  # --- network ---
  local ifc=${NET_WAN:-}
  if [[ -n $ifc ]]; then
    net_link "$ifc"
    local down=0
    [[ -n $LINK_STATE && $LINK_STATE != up && $LINK_STATE != unknown ]] && down=1
    _check_bool iface_down crit "$down" "WAN interface $ifc is $LINK_STATE"
    local errs=$((${NET_RERR_R[$ifc]:-0} + ${NET_TERR_R[$ifc]:-0} + ${NET_RDROP_R[$ifc]:-0} + ${NET_TDROP_R[$ifc]:-0}))
    _check_num net_errors warn "$errs" "${CFG[alert_net_err_rate]}" 1 \
      "$ifc reporting $errs errors+drops/s"
  fi
  _check_num tcp_retrans warn "$NET_RETRANS_PM" "${CFG[alert_retrans_pm]}" $((${CFG[alert_retrans_pm]} / 2)) \
    "TCP retransmits at $(fmt_fixed "$NET_RETRANS_PM" 10 1)% of segments sent — packet loss on the path"
  local ld=${SNMPR[TcpExt.ListenDrops.raw]:-0}
  _check_num listen_drops warn "$ld" "${CFG[alert_listen_drops]}" 1 \
    "$ld connections dropped from the listen queue — a service is not accepting fast enough"
  if [[ -n ${CT_PCT:-} ]]; then
    _check_num conntrack crit "$CT_PCT" "${CFG[alert_conntrack_pct]}" $((${CFG[alert_conntrack_pct]} - 10)) \
      "Conntrack table ${CT_PCT}% full ($CT_COUNT/$CT_MAX) — new connections will be dropped at 100%"
  fi

  # Internet reachability and quality, from the latency probe cache.
  local k worst=0 worstname='' loss=0 lossname=''
  for k in "${!LAT_MS[@]}"; do
    [[ $k == gw || $k == 'gw*' || $k == dns || $k == '#ts' ]] && continue
    local us=${LAT_MS[$k]}
    [[ $us =~ ^[0-9]+$ ]] || continue
    ((us > worst)) && { worst=$us; worstname=$k; }
    local l=${LAT_LOSS[$k]:-0}
    [[ $l =~ ^[0-9]+$ ]] && ((l > loss)) && { loss=$l; lossname=$k; }
  done
  if ((worst > 0)); then
    _check_num latency_high warn $((worst / 1000)) "${CFG[alert_latency_ms]}" $((${CFG[alert_latency_ms]} - 50)) \
      "Latency to $worstname is $(fmt_fixed "$worst" 1000 1)ms"
  fi
  _check_num packet_loss crit "$loss" "${CFG[alert_loss_pct]}" 1 \
    "Packet loss ${loss}% to ${lossname:-internet}"

  # --- throughput regression ---
  # Only meaningful against a recorded best; a brand new install has no baseline.
  if ((ST_LAST_DOWN > 0)); then
    local best
    best=$(st_baseline)
    if ((best > 0)); then
      local ratio=$((ST_LAST_DOWN * 100 / best))
      local floor=${CFG[alert_speed_min_pct]}
      [[ $floor =~ ^[0-9]+$ ]] || floor=50
      # Inverted rule: for throughput, lower is worse. Compare the shortfall so
      # the shared "higher is worse" hysteresis logic still applies.
      _check_num speed_drop warn $((100 - ratio)) $((100 - floor)) $((100 - floor - 10)) \
        "Download is $(fmt_rate "$ST_LAST_DOWN"), ${ratio}% of the best recorded $(fmt_rate "$best")"
    fi
  fi

  # --- system hygiene ---
  _check_num failed_units warn "${#FAILED_UNITS[@]}" 1 1 \
    "${#FAILED_UNITS[@]} systemd unit(s) failed: ${FAILED_UNITS[*]}"
  check_oom
  _check_num oom_kill crit "$OOM_COUNT" 1 1 \
    "Kernel OOM killer fired ${OOM_COUNT}x: $OOM_LAST"
  if [[ -n ${FD_USED:-} && -n ${FD_MAX:-} ]] && [[ $FD_MAX =~ ^[0-9]+$ ]] && ((FD_MAX > 0)); then
    _check_num fd_high warn $((FD_USED * 100 / FD_MAX)) "${CFG[alert_fd_pct]}" $((${CFG[alert_fd_pct]} - 10)) \
      "Open file descriptors at $((FD_USED * 100 / FD_MAX))% of the system limit"
  fi
  _check_bool reboot_required info "$REBOOT_REQ" 'A reboot is required to finish applying updates'

  # --- Highway node ---
  if cfg_on highway_track && ((HW_PRESENT)); then
    _check_num hw_failed crit "$HW_FAILED" 1 1 \
      "Highway: $HW_FAILED unit(s) in failed state"
    local inactive=0
    ((HW_UNIT_COUNT > 0 && HW_ACTIVE == 0)) && inactive=1
    _check_bool hw_inactive crit "$inactive" \
      'Highway: no unit is active — the node is not relaying'
    local maxr=0 u r
    for u in "${HW_UNITS[@]}"; do
      r=${HW_RESTARTS[$u]:-0}
      [[ $r =~ ^[0-9]+$ ]] && ((r > maxr)) && maxr=$r
    done
    _check_num hw_restarts warn "$maxr" "${CFG[alert_hw_restarts]}" 1 \
      "Highway: unit has restarted ${maxr}x — likely crash-looping"
    _check_num hw_journal_err warn "$HW_JOURNAL_ERR" "${CFG[alert_hw_journal_err]}" 1 \
      "Highway: $HW_JOURNAL_ERR error(s) in the journal in the last hour"
    local notunnel=0
    ((HW_ACTIVE > 0)) && [[ -z $HW_NEBULA ]] && notunnel=1
    _check_bool hw_tunnel_down warn "$notunnel" \
      'Highway: node is active but no Nebula mesh interface was found'
    _check_bool hw_update info "$HW_UPDATE" \
      "Highway: ${HW_LATEST:-a newer version} is available (installed: ${HW_VERSION:-unknown})"
    local pid_gone=0
    ((HW_UNIT_COUNT == 0 && HW_PID == 0)) && pid_gone=1
    _check_bool hw_not_running warn "$pid_gone" \
      'Highway is installed but no process or unit is running'
  fi
  return 0
}

# ---------------------------------------------------------------------------
# notification decision
# ---------------------------------------------------------------------------
# Decides whether this run has anything worth interrupting someone for, then
# sends at most one message covering all of it.
alerts_notify() {
  local force=${1:-0}
  local minsev=${CFG[alert_min_severity]:-warn}
  local minrank repeat now=${EPOCHSECONDS:-0}
  minrank=$(_sev_rank "$minsev")
  repeat=${CFG[alert_repeat_hours]:-6}
  [[ $repeat =~ ^[0-9]+$ ]] || repeat=6
  local repeat_s=$((repeat * 3600))

  local -a send_new=() send_ongoing=()
  local i id sev rank last
  for ((i = 0; i < ${#AL_ID[@]}; i++)); do
    id=${AL_ID[i]} sev=${AL_SEV[i]}
    rank=$(_sev_rank "$sev")
    ((rank < minrank)) && continue
    last=${_AL_PREV_NOTIFIED[$id]:-0}
    if ((${AL_NEW[i]})); then
      send_new+=("$i")
    elif ((repeat_s > 0 && now - last >= repeat_s)); then
      send_ongoing+=("$i")
    fi
  done

  local nres=${#AL_RESOLVED[@]}
  cfg_on alert_notify_resolved || nres=0

  if ((${#send_new[@]} == 0 && ${#send_ongoing[@]} == 0 && nres == 0 && force == 0)); then
    AL_NOTIFY=0
    return 0
  fi

  # Subject leads with the worst severity and the host, because that is all a
  # phone notification shows.
  local worst=info wr=1
  for i in "${send_new[@]}" "${send_ongoing[@]}"; do
    rank=$(_sev_rank "${AL_SEV[i]}")
    ((rank > wr)) && { wr=$rank; worst=${AL_SEV[i]}; }
  done
  local tag
  case $worst in
    crit) tag='CRITICAL' ;;
    warn) tag='WARNING' ;;
    *) tag='NOTICE' ;;
  esac
  if ((${#send_new[@]} == 0 && ${#send_ongoing[@]} == 0 && nres > 0)); then
    tag='RESOLVED'
  fi

  local n=$((${#send_new[@]} + ${#send_ongoing[@]}))
  local subject
  if ((n == 1)); then
    i=${send_new[0]:-${send_ongoing[0]}}
    subject="[$tag] $HOSTNAME_S: ${AL_MSG[i]}"
    subject=${subject:0:150}
  elif ((n > 1)); then
    subject="[$tag] $HOSTNAME_S: $n issues"
  else
    subject="[RESOLVED] $HOSTNAME_S: $nres issue(s) cleared"
  fi

  local body
  body=$(alerts_body "$(printf '%s\n' "${send_new[@]}")" "$(printf '%s\n' "${send_ongoing[@]}")")
  local html
  html=$(alerts_html "$(printf '%s\n' "${send_new[@]}")" "$(printf '%s\n' "${send_ongoing[@]}")" "$worst")

  if notify_send "$worst" "$subject" "$body" "$html"; then
    for i in "${send_new[@]}" "${send_ongoing[@]}"; do
      _AL_PREV_NOTIFIED[${AL_ID[i]}]=$now
    done
    AL_NOTIFY=1
    return 0
  fi
  AL_NOTIFY=0
  return 1
}

alerts_body() {
  local newlist=$1 onglist=$2 i
  {
    printf 'Host      %s\n' "$HOSTNAME_S"
    [[ -n ${PUB_IP:-} ]] && printf 'Address   %s\n' "$PUB_IP"
    printf 'Time      %(%Y-%m-%d %H:%M:%S %Z)T\n' -1
    fmt_dur_v "$UPTIME_S"; printf 'Uptime    %s\n' "$FMT_OUT"
    printf '\n'
    if [[ -n ${newlist//[[:space:]]/} ]]; then
      printf 'NEW\n'
      for i in $newlist; do
        [[ $i =~ ^[0-9]+$ ]] || continue
        printf '  [%-4s] %s\n' "${AL_SEV[i]}" "${AL_MSG[i]}"
      done
      printf '\n'
    fi
    if [[ -n ${onglist//[[:space:]]/} ]]; then
      printf 'STILL ACTIVE\n'
      for i in $onglist; do
        [[ $i =~ ^[0-9]+$ ]] || continue
        fmt_dur_v $((${EPOCHSECONDS:-0} - ${_AL_PREV_SINCE[${AL_ID[i]}]:-0}))
        printf '  [%-4s] %s (for %s)\n' "${AL_SEV[i]}" "${AL_MSG[i]}" "$FMT_OUT"
      done
      printf '\n'
    fi
    if ((${#AL_RESOLVED[@]} > 0)) && cfg_on alert_notify_resolved; then
      printf 'RESOLVED\n'
      local r
      for r in "${AL_RESOLVED[@]}"; do printf '  [ok  ] %s\n' "${r#*|}"; done
      printf '\n'
    fi
    printf -- '--- current state ---\n'
    alerts_context
    printf '\nSent by hyn-view %s on %s.\n' "$HYN_VERSION" "$HOSTNAME_S"
    printf 'Silence a rule by setting its threshold to 0 in %s/config,\n' "$HYN_ETC"
    printf 'then: systemctl restart hyn-alerts.timer\n'
    printf '%s by %s  <%s>\n' "$HYN_COPYRIGHT" "$HYN_AUTHOR" "$HYN_AUTHOR_URL"
  }
}

# The numbers someone will immediately want after reading the alert, so they do
# not have to ssh in to get context.
alerts_context() {
  printf 'host     %s   running as %s (uid %s)\n' "$HOSTNAME_S" "${RUN_AS:-?}" "${RUN_UID:-?}"
  if ((${#SESS_USER[@]} > 0)); then
    local si out=''
    for ((si = 0; si < ${#SESS_USER[@]} && si < 5; si++)); do
      out+="${out:+, }${SESS_USER[si]}@${SESS_FROM[si]}"
    done
    printf 'logged in %s\n' "$out"
  else
    printf 'logged in nobody\n'
  fi
  fmt_size_v "$MEM_USED"; local mu=$FMT_OUT
  fmt_size_v "$MEM_TOTAL"
  printf 'cpu      %s%%  (usr %s sys %s io %s steal %s)  load %s %s %s\n' \
    "$CPU_PCT" "$CPU_USER" "$CPU_SYS" "$CPU_IOWAIT" "$CPU_STEAL" \
    "${LOAD1:-?}" "${LOAD5:-?}" "${LOAD15:-?}"
  printf 'memory   %s / %s (%s%%)   swap %s%%\n' "$mu" "$FMT_OUT" "$MEM_PCT" "$SWAP_PCT"
  local mp
  for mp in "${MOUNTS[@]}"; do
    fmt_size_v "${MP_AVAIL[$mp]:-0}"
    printf 'disk     %-16s %s%%  %s free\n' "$mp" "${MP_PCT[$mp]}" "$FMT_OUT"
  done
  local ifc=${NET_WAN:-none}
  if [[ $ifc != none ]]; then
    fmt_rate_v "${NET_RXR[$ifc]:-0}"; local rx=$FMT_OUT
    fmt_rate_v "${NET_TXR[$ifc]:-0}"
    printf 'network  %-8s down %s  up %s   retrans %s%%\n' \
      "$ifc" "$rx" "$FMT_OUT" "$(fmt_fixed "$NET_RETRANS_PM" 10 2)"
  fi
  local k
  for k in "${!LAT_MS[@]}"; do
    [[ $k == '#ts' ]] && continue
    [[ ${LAT_MS[$k]} =~ ^[0-9]+$ ]] || continue
    printf 'latency  %-12s %sms  loss %s%%\n' "$k" "$(fmt_fixed "${LAT_MS[$k]}" 1000 1)" "${LAT_LOSS[$k]:-?}"
  done
  net_identity
  [[ -n ${NET_SSID:-} ]] && printf 'wifi     ssid %s\n' "$NET_SSID"
  [[ -n ${NET_LOCAL_IP:-} ]] && printf 'address  %s via %s   dns %s\n' \
    "$NET_LOCAL_IP" "${NET_GW:-?}" "${NET_DNS:-?}"
  if cfg_on highway_track && ((HW_PRESENT)); then
    printf 'highway  %s (%s)   version %s\n' "$HW_HEALTH" "$HW_HEALTH_WHY" "${HW_VERSION:-unknown}"
    if ((HW_PID > 0)); then
      fmt_size_v "$HW_RSS"; local hr=$FMT_OUT
      fmt_dur_v "$HW_UPTIME"
      printf 'highway  pid %s  rss %s  cpu %s%%  up %s  tunnel %s\n' \
        "$HW_PID" "$hr" "$(fmt_fixed "$HW_CPU" 10 1)" "$FMT_OUT" "${HW_NEBULA:-none}"
    fi
    local u
    for u in "${HW_UNITS[@]}"; do
      printf 'highway  %-28s %s/%s  restarts %s\n' \
        "$u" "${HW_STATE[$u]:-?}" "${HW_SUB[$u]:-?}" "${HW_RESTARTS[$u]:-0}"
    done
  fi
  return 0
}

# A deliberately plain HTML email: a table, a monospace block, no images, no
# external CSS. It has to be legible in a phone notification preview and in a
# text-only client, and it must not look like marketing.
# Same components as the daily report, so the two look like one product. An
# alert has to be legible in a phone notification preview first and a mail client
# second, so the severity, host and headline all appear before any detail.
alerts_html() {
  local newlist=$1 onglist=$2 worst=$3 i
  local nnew=0 nong=0
  for i in $newlist; do [[ $i =~ ^[0-9]+$ ]] && ((nnew++)); done
  for i in $onglist; do [[ $i =~ ^[0-9]+$ ]] && ((nong++)); done
  local badge
  case $worst in
    crit) badge='CRITICAL' ;;
    warn) badge='WARNING' ;;
    *) badge='NOTICE' ;;
  esac
  local total=$((nnew + nong))
  ((total > 0)) && badge="$badge · $total issue$( ((total > 1)) && printf s )"

  # Inbox snippet: the first problem, spelled out.
  local pre=''
  for i in $newlist $onglist; do
    [[ $i =~ ^[0-9]+$ ]] || continue
    pre=${AL_MSG[i]}
    break
  done
  [[ -z $pre ]] && pre='Previously reported issues have cleared'

  {
    e_preheader "$pre"
    e_open
    printf -v _now '%(%H:%M %Z, %d %b)T' -1
    e_header "$HOSTNAME_S" "Alert · $_now" "$badge" "$worst"

    # Quick state, so the reader does not have to ssh in for context.
    local cpucol memcol dskcol dpct=0 mp
    for mp in "${MOUNTS[@]}"; do
      [[ ${MP_PCT[$mp]:-0} =~ ^[0-9]+$ ]] || continue
      ((MP_PCT[$mp] > dpct)) && dpct=${MP_PCT[$mp]}
    done
    cpucol=$(e_level "$CPU_PCT"); memcol=$(e_level "$MEM_PCT"); dskcol=$(e_level "$dpct")
    e_kpi_open
    e_kpi 'CPU' "${CPU_PCT}%" "steal ${CPU_STEAL}%" "$cpucol"
    e_kpi 'Memory' "${MEM_PCT}%" "swap ${SWAP_PCT}%" "$memcol"
    e_kpi 'Disk' "${dpct}%" 'fullest mount' "$dskcol"
    fmt_dur_v "$UPTIME_S"
    e_kpi 'Uptime' "$FMT_OUT" "load ${LOAD1:-?}" "$E_ACCENT"
    e_kpi_close

    if ((nnew > 0)); then
      e_section 'New'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="font-size:14px">'
      for i in $newlist; do
        [[ $i =~ ^[0-9]+$ ]] || continue
        printf '<tr><td style="padding:6px 10px 6px 0;vertical-align:top;white-space:nowrap">%s</td>' "$(e_pill "${AL_SEV[i]}")"
        printf '<td style="padding:6px 0;color:%s;font-weight:600">%s</td></tr>' "$E_INK" "$(html_escape "${AL_MSG[i]}")"
      done
      printf '</table></td></tr></table>'
    fi

    if ((nong > 0)); then
      e_section 'Still active'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px">'
      for i in $onglist; do
        [[ $i =~ ^[0-9]+$ ]] || continue
        printf '<tr><td style="padding:6px 10px 6px 0;vertical-align:top;white-space:nowrap">%s</td>' "$(e_pill "${AL_SEV[i]}")"
        printf '<td style="padding:6px 0;color:%s">%s <span style="color:%s">(for %s)</span></td></tr>' \
          "$E_INK" "$(html_escape "${AL_MSG[i]}")" "$E_MUTED" \
          "$(fmt_dur $((${EPOCHSECONDS:-0} - ${_AL_PREV_SINCE[${AL_ID[i]}]:-0})))"
      done
      printf '</table></td></tr></table>'
    fi

    if ((${#AL_RESOLVED[@]} > 0)) && cfg_on alert_notify_resolved; then
      e_section 'Resolved'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
      printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px">'
      local r
      for r in "${AL_RESOLVED[@]}"; do
        printf '<tr><td style="padding:6px 10px 6px 0;vertical-align:top;white-space:nowrap">%s</td>' "$(e_pill ok)"
        printf '<td style="padding:6px 0;color:%s">%s</td></tr>' "$E_MUTED" "$(html_escape "${r#*|}")"
      done
      printf '</table></td></tr></table>'
    fi

    # Resource bars: the numbers the reader will want next.
    e_section 'Resources'
    printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
    e_bar 'CPU' "$CPU_PCT" "usr ${CPU_USER}% sys ${CPU_SYS}%"
    fmt_size_v "$MEM_USED"; local mu=$FMT_OUT
    fmt_size_v "$MEM_TOTAL"
    e_bar 'Memory' "$MEM_PCT" "$mu / $FMT_OUT"
    ((SWAP_TOTAL > 0)) && e_bar 'Swap' "$SWAP_PCT" "$(fmt_size "$SWAP_USED")"
    for mp in "${MOUNTS[@]}"; do
      fmt_size_v "${MP_AVAIL[$mp]:-0}"
      e_bar "$mp" "${MP_PCT[$mp]:-0}" "$FMT_OUT free"
    done
    printf '</td></tr></table>'

    e_section 'Access'
    e_kv_open
    local ranas="${RUN_AS:-?} (uid ${RUN_UID:-?})"
    [[ -n ${LOGIN_USER:-} && $LOGIN_USER != "${RUN_AS:-}" ]] && ranas+=" · invoked by $LOGIN_USER"
    e_kv 'Running as' "$ranas"
    if ((${#SESS_USER[@]} == 0)); then
      e_kv 'Logged in now' 'nobody'
    else
      local si
      for ((si = 0; si < ${#SESS_USER[@]} && si < 6; si++)); do
        local scol=$E_INK
        [[ ${SESS_FROM[si]} == local ]] && scol=$E_MUTED
        e_kv "Session ${SESS_TTY[si]}" "${SESS_USER[si]} from ${SESS_FROM[si]} since ${SESS_WHEN[si]}" "$scol"
      done
    fi
    e_kv_close

    e_section 'Network'
    net_identity
    e_kv_open
    local ifc=${NET_WAN:-none}
    e_kv 'Interface' "$ifc${NET_IDENT_LABEL:+ ($NET_IDENT_LABEL)}"
    [[ -n ${NET_SSID:-} ]] && e_kv 'Wi-Fi SSID' "$NET_SSID" "$E_ACCENT"
    [[ -n ${NET_LOCAL_IP:-} ]] && e_kv 'Local address' "$NET_LOCAL_IP"
    [[ -n ${PUB_IP:-} ]] && e_kv 'Public address' "$PUB_IP"
    [[ -n ${NET_GW:-} ]] && e_kv 'Gateway' "${NET_GW}${NET_DNS:+  ·  dns $NET_DNS}"
    if [[ $ifc != none ]]; then
      e_kv 'Throughput' "$(fmt_rate "${NET_RXR[$ifc]:-0}") down / $(fmt_rate "${NET_TXR[$ifc]:-0}") up"
    fi
    local rcol=$E_INK
    ((NET_RETRANS_PM > 50)) && rcol=$E_WARN
    e_kv 'TCP retransmits' "$(fmt_fixed "$NET_RETRANS_PM" 10 2)% of segments" "$rcol"
    local k
    for k in "${!LAT_MS[@]}"; do
      [[ $k == '#ts' ]] && continue
      [[ ${LAT_MS[$k]} =~ ^[0-9]+$ ]] || continue
      local lcol=$E_INK
      ((${LAT_LOSS[$k]:-0} > 0)) && lcol=$E_CRIT
      e_kv "Latency $k" "$(fmt_fixed "${LAT_MS[$k]}" 1000 1)ms, loss ${LAT_LOSS[$k]:-0}%" "$lcol"
    done
    e_kv_close

    if cfg_on highway_track && ((HW_PRESENT)); then
      e_section 'Highway node'
      local hcol
      hcol=$(e_sevcolor "$( [[ $HW_HEALTH == ok ]] && printf ok || printf '%s' "$HW_HEALTH" )")
      e_kv_open
      e_kv 'Status' "$HW_HEALTH — $HW_HEALTH_WHY" "$hcol"
      e_kv 'Version' "${HW_VERSION:-unknown}"
      if ((HW_PID > 0)); then
        e_kv 'Process' "pid $HW_PID · up $(fmt_dur "$HW_UPTIME") · $(fmt_size "$HW_RSS") · $(fmt_fixed "$HW_CPU" 10 1)% cpu"
      fi
      e_kv 'Mesh tunnel' "${HW_NEBULA:-not detected}" "$( [[ -z $HW_NEBULA ]] && printf '%s' "$E_WARN" )"
      local u
      for u in "${HW_UNITS[@]}"; do
        local ucol=$E_OK
        [[ ${HW_STATE[$u]:-} == active ]] || ucol=$E_CRIT
        e_kv "${u%.service}" "${HW_STATE[$u]:-?}/${HW_SUB[$u]:-?} · ${HW_RESTARTS[$u]:-0} restart(s)" "$ucol"
      done
      e_kv_close
    fi

    e_section 'How to silence this'
    printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
    printf '<div style="font-size:12px;line-height:1.7;color:%s">' "$E_MUTED"
    printf 'Set the rule&rsquo;s threshold to <span style="font-family:%s;color:%s">0</span> in ' "$E_MONO" "$E_INK"
    printf '<span style="font-family:%s;color:%s">%s/config</span>, then ' "$E_MONO" "$E_INK" "$HYN_ETC"
    printf '<span style="font-family:%s;color:%s">systemctl restart hyn-alerts.timer</span>.<br>' "$E_MONO" "$E_INK"
    printf 'Run <span style="font-family:%s;color:%s">hyn alerts list</span> on the host to see every rule and its current value.' \
      "$E_MONO" "$E_INK"
    printf '</div></td></tr></table>'

    e_footer
    e_close
  }
}

# ---------------------------------------------------------------------------
# entry point for the timer
# ---------------------------------------------------------------------------
alerts_run() {
  local quiet=${1:-0}
  alerts_state_load
  alerts_collect
  alerts_evaluate
  alerts_notify 0
  alerts_state_save
  # Health-aware heartbeat: a box that is up but critical still trips the
  # external dead man's switch.
  if ((AL_CRIT > 0)); then heartbeat_ping 1; else heartbeat_ping 0; fi
  ((quiet)) && return 0
  if ((AL_FIRING == 0)); then
    printf 'hyn: no alerts firing (%d rules evaluated)\n' "${#_AL_SEEN[@]}"
  else
    printf 'hyn: %d firing (%d crit, %d warn, %d info)%s\n' \
      "$AL_FIRING" "$AL_CRIT" "$AL_WARN" "$AL_INFO" \
      "$( ((AL_NOTIFY)) && printf ', notified' || printf ', no notification due')"
    local i
    for ((i = 0; i < ${#AL_ID[@]}; i++)); do
      printf '  [%-4s] %-22s %s\n' "${AL_SEV[i]}" "${AL_ID[i]}" "${AL_MSG[i]}"
    done
  fi
  ((${#AL_RESOLVED[@]} > 0)) && printf '  resolved: %s\n' "${#AL_RESOLVED[@]}"
  return 0
}
