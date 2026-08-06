#!/usr/bin/env bash
# hyn-view :: metric recording + daily report
#
# A daily report needs history, and history needs someone to write it down. So
# there are two halves:
#
#   record_sample()  one TSV row, appended by the hyn-record timer every few
#                    minutes. Cheap and append-only.
#   report_run()     aggregates the last 24h into something worth reading.
#
# The report deliberately reports CHANGE as well as level. "Disk at 71%" is not
# actionable; "disk at 71%, up 4 points in 24h, full in about 7 days" is. Same
# for throughput against the recorded baseline.
#
# Columns (append-only, order is fixed forever; add new fields at the END):
#   1 ts  2 cpu  3 steal  4 iowait  5 mem  6 swap  7 load_milli  8 disk_max_pct
#   9 rx_bps 10 tx_bps 11 rx_total 12 tx_total 13 retrans_pm 14 lat_us
#  15 ct_pct 16 hw_active 17 hw_rss 18 hw_cpu 19 procs 20 hw_restarts

metrics_file() {
  state_dir_v
  printf '%s/metrics.tsv' "$STATE_DIR"
}

alert_log_file() {
  state_dir_v
  printf '%s/alert-log' "$STATE_DIR"
}

# ---------------------------------------------------------------------------
# recording
# ---------------------------------------------------------------------------
record_sample() {
  local f keep
  # Two samples for rates, same as snapshot and the alert run.
  net_sample 0
  cpu_sample 0
  sleep 1
  net_sample 1000
  net_snmp 1000
  cpu_sample 1000
  mem_sample
  sys_sample
  psi_sample
  disk_usage 1
  net_conntrack
  net_latency_read
  net_retrans_permille
  cfg_on highway_track && hw_sample 1000

  local ifc=${NET_WAN:-} loadm=0 diskmax=0 mp lat=0 k hwrest=0 u r
  [[ ${LOAD1:-} =~ ^[0-9.]+$ ]] && { parse_fixed3_v "$LOAD1"; loadm=$FIX3; }
  for mp in "${MOUNTS[@]}"; do
    [[ ${MP_PCT[$mp]:-0} =~ ^[0-9]+$ ]] || continue
    ((MP_PCT[$mp] > diskmax)) && diskmax=${MP_PCT[$mp]}
  done
  for k in "${!LAT_MS[@]}"; do
    [[ $k == gw || $k == 'gw*' || $k == dns || $k == '#ts' ]] && continue
    [[ ${LAT_MS[$k]} =~ ^[0-9]+$ ]] || continue
    ((LAT_MS[$k] > lat)) && lat=${LAT_MS[$k]}
  done
  for u in "${HW_UNITS[@]}"; do
    r=${HW_RESTARTS[$u]:-0}
    [[ $r =~ ^[0-9]+$ ]] && ((r > hwrest)) && hwrest=$r
  done

  f=$(metrics_file)
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${EPOCHSECONDS:-0}" "$CPU_PCT" "$CPU_STEAL" "$CPU_IOWAIT" "$MEM_PCT" "$SWAP_PCT" \
    "$loadm" "$diskmax" "${NET_RXR[$ifc]:-0}" "${NET_TXR[$ifc]:-0}" \
    "${NET_RX[$ifc]:-0}" "${NET_TX[$ifc]:-0}" "$NET_RETRANS_PM" "$lat" \
    "${CT_PCT:-0}" "${HW_ACTIVE:-0}" "${HW_RSS:-0}" "${HW_CPU:-0}" \
    "${PROC_TOTAL:-0}" "$hwrest" >>"$f"

  # Trim by age rather than line count, so changing the record interval does not
  # silently change how much history is kept.
  keep=${CFG[metrics_keep_days]:-8}
  [[ $keep =~ ^[0-9]+$ ]] || keep=8
  _metrics_trim "$f" $((keep * 86400))
  return 0
}

_metrics_trim() {
  local f=$1 maxage=$2 cutoff line ts tmp n=0 total=0
  cutoff=$((${EPOCHSECONDS:-0} - maxage))
  [[ -r $f ]] || return 0
  # Only rewrite when there is actually something to drop; this runs every few
  # minutes and rewriting a 2000-line file each time is pointless I/O.
  while IFS=$'\t' read -r ts _; do
    ((total++))
    [[ $ts =~ ^[0-9]+$ ]] && ((ts < cutoff)) && ((n++))
  done <"$f"
  ((n == 0)) && return 0
  tmp="$f.tmp.$$"
  : >"$tmp" || return 1
  while IFS= read -r line; do
    ts=${line%%$'\t'*}
    [[ $ts =~ ^[0-9]+$ ]] || continue
    ((ts >= cutoff)) && printf '%s\n' "$line" >>"$tmp"
  done <"$f"
  mv -f "$tmp" "$f"
  return 0
}

# Append-only record of what fired, so the daily report can say what happened
# overnight without keeping the alert engine's state around.
alerts_log_new() {
  local f i now=${EPOCHSECONDS:-0}
  f=$(alert_log_file)
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  for ((i = 0; i < ${#AL_ID[@]}; i++)); do
    ((${AL_NEW[i]})) || continue
    printf '%s\t%s\t%s\t%s\n' "$now" "${AL_SEV[i]}" "${AL_ID[i]}" "${AL_MSG[i]}" >>"$f"
  done
  _metrics_trim "$f" $((31 * 86400))
  return 0
}

# ---------------------------------------------------------------------------
# aggregation
# ---------------------------------------------------------------------------
declare -A R=()
R_ROWS=0

# Aggregate the last <hours> of samples. All integer maths; averages are
# accumulated as sums and divided once at the end.
report_aggregate() {
  local hours=${1:-24} f cutoff line
  local ts cpu steal iowait mem swap loadm diskmax rxb txb rxt txt retr lat ctp hwa hwr hwc procs hwrest
  f=$(metrics_file)
  R=() R_ROWS=0
  [[ -r $f ]] || return 1
  cutoff=$((${EPOCHSECONDS:-0} - hours * 3600))

  local n=0
  local cpu_s=0 cpu_max=0 steal_s=0 steal_max=0 io_s=0 io_max=0
  local mem_s=0 mem_max=0 swap_max=0 load_s=0 load_max=0
  local disk_first=-1 disk_last=0 disk_max=0
  local rx_max=0 tx_max=0 rxt_first=-1 rxt_last=0 txt_first=-1 txt_last=0
  local retr_s=0 retr_max=0 lat_s=0 lat_n=0 lat_max=0 ct_max=0
  local hw_up=0 hw_rss_max=0 hw_cpu_s=0 hw_rest_max=0 hw_rest_first=-1
  local procs_max=0 first_ts=0 last_ts=0
  local cpu_busy_n=0 mem_busy_n=0

  local busy_cpu=${CFG[report_busy_cpu_pct]:-80}
  local busy_mem=${CFG[report_busy_mem_pct]:-85}
  [[ $busy_cpu =~ ^[0-9]+$ ]] || busy_cpu=80
  [[ $busy_mem =~ ^[0-9]+$ ]] || busy_mem=85

  while IFS=$'\t' read -r ts cpu steal iowait mem swap loadm diskmax rxb txb rxt txt retr lat ctp hwa hwr hwc procs hwrest; do
    [[ $ts =~ ^[0-9]+$ ]] || continue
    ((ts < cutoff)) && continue
    ((n == 0)) && first_ts=$ts
    last_ts=$ts
    ((n++))
    cpu=${cpu:-0}; ((cpu_s += cpu)); ((cpu > cpu_max)) && cpu_max=$cpu
    ((cpu >= busy_cpu)) && ((cpu_busy_n++))
    steal=${steal:-0}; ((steal_s += steal)); ((steal > steal_max)) && steal_max=$steal
    iowait=${iowait:-0}; ((io_s += iowait)); ((iowait > io_max)) && io_max=$iowait
    mem=${mem:-0}; ((mem_s += mem)); ((mem > mem_max)) && mem_max=$mem
    ((mem >= busy_mem)) && ((mem_busy_n++))
    swap=${swap:-0}; ((swap > swap_max)) && swap_max=$swap
    loadm=${loadm:-0}; ((load_s += loadm)); ((loadm > load_max)) && load_max=$loadm
    diskmax=${diskmax:-0}
    ((disk_first < 0)) && disk_first=$diskmax
    disk_last=$diskmax
    ((diskmax > disk_max)) && disk_max=$diskmax
    rxb=${rxb:-0}; ((rxb > rx_max)) && rx_max=$rxb
    txb=${txb:-0}; ((txb > tx_max)) && tx_max=$txb
    rxt=${rxt:-0}
    ((rxt_first < 0)) && rxt_first=$rxt
    # A counter reset means a reboot or NIC reset; restart the accumulator
    # rather than reporting a negative day's transfer.
    ((rxt < rxt_last)) && rxt_first=$rxt
    rxt_last=$rxt
    txt=${txt:-0}
    ((txt_first < 0)) && txt_first=$txt
    ((txt < txt_last)) && txt_first=$txt
    txt_last=$txt
    retr=${retr:-0}; ((retr_s += retr)); ((retr > retr_max)) && retr_max=$retr
    lat=${lat:-0}
    if ((lat > 0)); then ((lat_s += lat)); ((lat_n++)); ((lat > lat_max)) && lat_max=$lat; fi
    ctp=${ctp:-0}; ((ctp > ct_max)) && ct_max=$ctp
    hwa=${hwa:-0}; ((hwa > 0)) && ((hw_up++))
    hwr=${hwr:-0}; ((hwr > hw_rss_max)) && hw_rss_max=$hwr
    hwc=${hwc:-0}; ((hw_cpu_s += hwc))
    hwrest=${hwrest:-0}
    ((hw_rest_first < 0)) && hw_rest_first=$hwrest
    ((hwrest > hw_rest_max)) && hw_rest_max=$hwrest
    procs=${procs:-0}; ((procs > procs_max)) && procs_max=$procs
  done <"$f"

  ((n == 0)) && return 1
  R_ROWS=$n
  R[rows]=$n
  R[from]=$first_ts
  R[to]=$last_ts
  R[span_s]=$((last_ts - first_ts))
  R[cpu_avg]=$((cpu_s / n)); R[cpu_max]=$cpu_max
  R[steal_avg]=$((steal_s / n)); R[steal_max]=$steal_max
  R[io_avg]=$((io_s / n)); R[io_max]=$io_max
  R[mem_avg]=$((mem_s / n)); R[mem_max]=$mem_max
  R[swap_max]=$swap_max
  R[load_avg]=$((load_s / n)); R[load_max]=$load_max
  R[disk_now]=$disk_last; R[disk_max]=$disk_max
  R[disk_delta]=$((disk_last - (disk_first < 0 ? disk_last : disk_first)))
  R[rx_peak]=$rx_max; R[tx_peak]=$tx_max
  R[rx_bytes]=$((rxt_last - (rxt_first < 0 ? rxt_last : rxt_first)))
  R[tx_bytes]=$((txt_last - (txt_first < 0 ? txt_last : txt_first)))
  ((R[rx_bytes] < 0)) && R[rx_bytes]=0
  ((R[tx_bytes] < 0)) && R[tx_bytes]=0
  R[retrans_avg]=$((retr_s / n)); R[retrans_max]=$retr_max
  R[lat_avg]=$((lat_n > 0 ? lat_s / lat_n : 0)); R[lat_max]=$lat_max
  R[ct_max]=$ct_max
  R[hw_up_pct]=$((hw_up * 100 / n))
  R[hw_rss_max]=$hw_rss_max
  R[hw_cpu_avg]=$((hw_cpu_s / n))
  R[hw_restarts]=$((hw_rest_max - (hw_rest_first < 0 ? hw_rest_max : hw_rest_first)))
  R[procs_max]=$procs_max
  # Minutes spent above the busy thresholds, derived from the sample interval.
  local ival=${CFG[record_interval_min]:-5}
  [[ $ival =~ ^[0-9]+$ ]] || ival=5
  R[cpu_busy_min]=$((cpu_busy_n * ival))
  R[mem_busy_min]=$((mem_busy_n * ival))

  # Days until the largest filesystem fills, from the observed trend. Only
  # meaningful when it is actually growing.
  R[disk_days]=0
  if ((R[disk_delta] > 0 && disk_last < 100)); then
    local per_day=$((R[disk_delta] * 24 * 3600 / (R[span_s] > 0 ? R[span_s] : 86400)))
    ((per_day > 0)) && R[disk_days]=$(((100 - disk_last) / per_day))
  fi
  return 0
}

# Alerts recorded in the window.
declare -a RA_TS=() RA_SEV=() RA_MSG=()
RA_CRIT=0 RA_WARN=0
report_alerts() {
  local hours=${1:-24} f cutoff ts sev id msg
  RA_TS=() RA_SEV=() RA_MSG=(); RA_CRIT=0 RA_WARN=0
  f=$(alert_log_file)
  [[ -r $f ]] || return 0
  cutoff=$((${EPOCHSECONDS:-0} - hours * 3600))
  while IFS=$'\t' read -r ts sev id msg; do
    [[ $ts =~ ^[0-9]+$ ]] || continue
    ((ts < cutoff)) && continue
    RA_TS+=("$ts") RA_SEV+=("$sev") RA_MSG+=("$msg")
    case $sev in
      crit) ((RA_CRIT++)) ;;
      warn) ((RA_WARN++)) ;;
    esac
  done <"$f"
  return 0
}

# Speed tests in the window.
declare -A S=()
report_speed() {
  local hours=${1:-24} cutoff i n=0 dsum=0 usum=0 dmin=0 dmax=0 umax=0 lsum=0 ln=0
  S=()
  st_history_read 1 || return 1
  cutoff=$((${EPOCHSECONDS:-0} - hours * 3600))
  for ((i = 0; i < ${#ST_H_TS[@]}; i++)); do
    ((ST_H_TS[i] < cutoff)) && continue
    local d=${ST_H_DOWN[i]:-0} u=${ST_H_UP[i]:-0} l=${ST_H_LAT[i]:-0}
    ((d <= 0)) && continue
    ((n++)); ((dsum += d)); ((usum += u))
    ((dmin == 0 || d < dmin)) && dmin=$d
    ((d > dmax)) && dmax=$d
    ((u > umax)) && umax=$u
    ((l > 0)) && { ((lsum += l)); ((ln++)); }
  done
  ((n == 0)) && return 1
  S[n]=$n
  S[down_avg]=$((dsum / n)); S[down_min]=$dmin; S[down_max]=$dmax
  S[up_avg]=$((usum / n)); S[up_max]=$umax
  S[lat_avg]=$((ln > 0 ? lsum / ln : 0))
  S[best]=$(st_baseline)
  return 0
}

# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------
_verdict() {
  # One line an operator can act on, at the top, before any numbers.
  if ((RA_CRIT > 0)); then printf 'ATTENTION — %d critical alert(s) in the last 24h' "$RA_CRIT"; return; fi
  if cfg_on highway_track && ((HW_PRESENT)) && [[ ${R[hw_up_pct]:-100} -lt 99 ]]; then
    printf 'DEGRADED — Highway was active for only %s%% of the day' "${R[hw_up_pct]}"; return
  fi
  if ((${R[disk_days]:-0} > 0 && ${R[disk_days]} < 14)); then
    printf 'PLAN AHEAD — largest filesystem fills in about %s days' "${R[disk_days]}"; return
  fi
  if ((RA_WARN > 0)); then printf 'MOSTLY HEALTHY — %d warning(s) in the last 24h' "$RA_WARN"; return; fi
  printf 'HEALTHY — no alerts in the last 24h'
}

report_text() {
  local hours=${1:-24}
  local ok=1
  fmt_dur_v "$UPTIME_S"; local up=$FMT_OUT
  {
    printf 'Daily report — %s\n' "$HOSTNAME_S"
    printf '%(%A %d %B %Y, %H:%M %Z)T\n' -1
    printf '\n%s\n\n' "$(_verdict)"

    printf 'SYSTEM\n'
    printf '  uptime           %s%s\n' "$up" "$( ((UPTIME_S < hours * 3600)) && printf '   (rebooted during this window)' )"
    printf '  distro / kernel  %s / %s\n' "${DISTRO:-?}" "${KERNEL:-?}"
    printf '  cpu              %s cores, %s\n' "$CPU_COUNT" "${CPU_MODEL:-unknown}"
    if ((R_ROWS > 0)); then
      printf '  samples          %s over %s\n' "${R[rows]}" "$(fmt_dur "${R[span_s]}")"
    else
      printf '  samples          none recorded yet — is hyn-record.timer running?\n'
    fi
    printf '\n'

    if ((R_ROWS > 0)); then
      printf 'PERFORMANCE (last %sh)\n' "$hours"
      printf '  cpu              avg %s%%   peak %s%%   %s min above %s%%\n' \
        "${R[cpu_avg]}" "${R[cpu_max]}" "${R[cpu_busy_min]}" "${CFG[report_busy_cpu_pct]:-80}"
      printf '  cpu steal        avg %s%%   peak %s%%%s\n' "${R[steal_avg]}" "${R[steal_max]}" \
        "$( ((${R[steal_max]} >= 10)) && printf '   <- host is oversold' )"
      printf '  iowait           avg %s%%   peak %s%%\n' "${R[io_avg]}" "${R[io_max]}"
      printf '  load average     avg %s   peak %s   (%s cores)\n' \
        "$(fmt_fixed "${R[load_avg]}" 1000 2)" "$(fmt_fixed "${R[load_max]}" 1000 2)" "$CPU_COUNT"
      printf '  memory           avg %s%%   peak %s%%   %s min above %s%%\n' \
        "${R[mem_avg]}" "${R[mem_max]}" "${R[mem_busy_min]}" "${CFG[report_busy_mem_pct]:-85}"
      printf '  swap             peak %s%%\n' "${R[swap_max]}"
      printf '  processes        peak %s\n' "${R[procs_max]}"
      printf '\n'

      printf 'STORAGE\n'
      local mp
      for mp in "${MOUNTS[@]}"; do
        fmt_size_v "${MP_USED[$mp]:-0}"; local u=$FMT_OUT
        fmt_size_v "${MP_SIZE[$mp]:-0}"; local t=$FMT_OUT
        fmt_size_v "${MP_AVAIL[$mp]:-0}"
        printf '  %-16s %3s%%   %s of %s   %s free\n' "$mp" "${MP_PCT[$mp]}" "$u" "$t" "$FMT_OUT"
      done
      if ((${R[disk_delta]} != 0)); then
        printf '  24h change       %+d percentage points\n' "${R[disk_delta]}"
      fi
      if ((${R[disk_days]:-0} > 0)); then
        printf '  projection       full in roughly %s days at the current rate\n' "${R[disk_days]}"
      fi
      printf '\n'

      printf 'NETWORK (%s)\n' "${NET_WAN:-no interface}"
      fmt_size_v "${R[rx_bytes]}"; local rxb=$FMT_OUT
      fmt_size_v "${R[tx_bytes]}"
      printf '  transferred      %s down / %s up in %sh\n' "$rxb" "$FMT_OUT" "$hours"
      fmt_rate_v "${R[rx_peak]}"; local rxp=$FMT_OUT
      fmt_rate_v "${R[tx_peak]}"
      printf '  peak rate        %s down / %s up\n' "$rxp" "$FMT_OUT"
      printf '  tcp retransmits  avg %s%%   peak %s%%\n' \
        "$(fmt_fixed "${R[retrans_avg]}" 10 2)" "$(fmt_fixed "${R[retrans_max]}" 10 2)"
      if ((${R[lat_avg]} > 0)); then
        printf '  latency          avg %sms   peak %sms\n' \
          "$(fmt_fixed "${R[lat_avg]}" 1000 1)" "$(fmt_fixed "${R[lat_max]}" 1000 1)"
      fi
      ((${R[ct_max]} > 0)) && printf '  conntrack peak   %s%%\n' "${R[ct_max]}"
      printf '\n'
    fi

    report_connection_text

    if report_speed "$hours"; then
      printf 'THROUGHPUT TESTS (%s in %sh)\n' "${S[n]}" "$hours"
      fmt_rate_v "${S[down_avg]}"; local da=$FMT_OUT
      fmt_rate_v "${S[down_min]}"; local dn=$FMT_OUT
      fmt_rate_v "${S[down_max]}"
      printf '  download         avg %s   worst %s   best %s\n' "$da" "$dn" "$FMT_OUT"
      fmt_rate_v "${S[up_avg]}"; local ua=$FMT_OUT
      fmt_rate_v "${S[up_max]}"
      printf '  upload           avg %s   best %s\n' "$ua" "$FMT_OUT"
      ((${S[lat_avg]} > 0)) && printf '  test latency     avg %sms\n' "$(fmt_fixed "${S[lat_avg]}" 1000 1)"
      if ((${S[best]:-0} > 0)); then
        printf '  vs all-time best %s%% of %s\n' \
          $((S[down_avg] * 100 / S[best])) "$(fmt_rate "${S[best]}")"
      fi
      printf '\n'
    else
      printf 'THROUGHPUT TESTS\n  no results in the last %sh (run: hyn speedtest)\n\n' "$hours"
    fi

    if cfg_on highway_track; then
      printf 'HIGHWAY NODE\n'
      if ((HW_PRESENT == 0)); then
        printf '  not installed at %s\n' "$HW_BIN"
      else
        printf '  status           %s — %s\n' "$HW_HEALTH" "$HW_HEALTH_WHY"
        printf '  version          %s%s\n' "${HW_VERSION:-unknown}" \
          "$( ((HW_UPDATE)) && printf '   (update available: %s)' "$HW_LATEST" )"
        ((R_ROWS > 0)) && printf '  active           %s%% of the last %sh\n' "${R[hw_up_pct]}" "$hours"
        local u
        for u in "${HW_UNITS[@]}"; do
          printf '  %-16s %s/%s   %s restart(s) total\n' \
            "${u%.service}" "${HW_STATE[$u]:-?}" "${HW_SUB[$u]:-?}" "${HW_RESTARTS[$u]:-0}"
        done
        ((${R[hw_restarts]:-0} > 0)) && printf '  restarts in %sh   %s\n' "$hours" "${R[hw_restarts]}"
        if ((HW_PID > 0)); then
          fmt_dur_v "$HW_UPTIME"
          printf '  process          pid %s, up %s, %s threads\n' "$HW_PID" "$FMT_OUT" "$HW_THR"
          fmt_size_v "$HW_RSS"; local hr=$FMT_OUT
          fmt_size_v "${R[hw_rss_max]:-0}"
          printf '  memory           %s now, %s peak in %sh\n' "$hr" "$FMT_OUT" "$hours"
          printf '  cpu              %s%% now, %s%% avg over %sh\n' \
            "$(fmt_fixed "$HW_CPU" 10 1)" "$(fmt_fixed "${R[hw_cpu_avg]:-0}" 10 1)" "$hours"
        fi
        if [[ -n $HW_NEBULA ]]; then
          fmt_size_v "${NET_RX[$HW_NEBULA]:-0}"; local nr=$FMT_OUT
          fmt_size_v "${NET_TX[$HW_NEBULA]:-0}"
          printf '  mesh tunnel      %s   %s in / %s out since boot\n' "$HW_NEBULA" "$nr" "$FMT_OUT"
        else
          printf '  mesh tunnel      not detected\n'
        fi
        printf '  journal (1h)     %s error(s), %s warning(s)\n' "$HW_JOURNAL_ERR" "$HW_JOURNAL_WARN"
        [[ -n $HW_QDISC ]] && printf '  wan qdisc        %s\n' "$HW_QDISC"
      fi
      printf '\n'
    fi

    report_alerts "$hours"
    printf 'ALERTS (last %sh)\n' "$hours"
    if ((${#RA_TS[@]} == 0)); then
      printf '  none\n'
    else
      local i
      for ((i = 0; i < ${#RA_TS[@]} && i < 25; i++)); do
        printf '  %(%H:%M)T  [%-4s] %s\n' "${RA_TS[i]}" "${RA_SEV[i]}" "${RA_MSG[i]}"
      done
      ((${#RA_TS[@]} > 25)) && printf '  ... and %s more\n' $((${#RA_TS[@]} - 25))
    fi
    if ((${#FAILED_UNITS[@]} > 0)); then
      printf '\n  currently failed units: %s\n' "${FAILED_UNITS[*]}"
    fi
    printf '\n'
    printf -- '---\n'
    printf 'hyn-view %s by %s  <%s>\n' "$HYN_VERSION" "$HYN_AUTHOR" "$HYN_AUTHOR_URL"
    printf '%s. Reply is not monitored; run `hyn` on the host for live detail.\n' "$HYN_COPYRIGHT"
    printf 'Change what is in this report or when it arrives: %s/config\n' "$HYN_ETC"
  }
  return 0
}

# Every LAN and WAN interface, with what it is attached to. Included in full so
# the report answers "which network was it on?" without an ssh session.
report_connection_text() {
  net_identity 1
  printf 'CONNECTION\n'
  printf '  wan interface    %s%s\n' "${NET_WAN:-none}" \
    "$( [[ -n ${NET_IDENT_LABEL:-} ]] && printf '  (%s)' "$NET_IDENT_LABEL" )"
  [[ -n $NET_SSID ]] && printf '  wifi ssid        %s\n' "$NET_SSID"
  [[ -n $NET_CONN ]] && printf '  connection name  %s\n' "$NET_CONN"
  [[ -n $NET_LOCAL_IP ]] && printf '  local address    %s\n' "$NET_LOCAL_IP"
  [[ -n $PUB_IP ]] && printf '  public address   %s\n' "$PUB_IP"
  [[ -n $NET_GW ]] && printf '  gateway          %s\n' "$NET_GW"
  [[ -n $NET_DNS ]] && printf '  dns              %s\n' "$NET_DNS"
  printf '\n'
  printf '  %-13s %-9s %-8s %-20s %-12s %s\n' INTERFACE TYPE STATE ADDRESS 'LINK' 'TOTAL IN / OUT'
  local ifn
  for ifn in "${NET_IFACES[@]}"; do
    local spd='-'
    [[ -n ${IF_SPEED[$ifn]:-} ]] && spd="$(fmt_rate $((IF_SPEED[ifn] * 125000)))"
    printf '  %-13s %-9s %-8s %-20s %-12s %s / %s%s\n' \
      "$ifn" "${IF_TYPE[$ifn]:-?}" "${IF_STATE[$ifn]:-?}" "${IF_IP[$ifn]:--}" "$spd" \
      "$(fmt_size "${NET_RX[$ifn]:-0}")" "$(fmt_size "${NET_TX[$ifn]:-0}")" \
      "$( [[ -n ${IF_SSID[$ifn]:-} ]] && printf '  ssid=%s' "${IF_SSID[$ifn]}" )"
  done
  printf '\n'
  return 0
}

report_connection_html() {
  net_identity 1
  printf '<div style="font-weight:600;margin:22px 0 8px">Connection</div><table style="border-collapse:collapse;width:100%%">'
  _hrow 'WAN interface' "${NET_WAN:-none}${NET_IDENT_LABEL:+ ($NET_IDENT_LABEL)}"
  [[ -n $NET_SSID ]] && _hrow 'Wi-Fi SSID' "$NET_SSID"
  [[ -n $NET_CONN ]] && _hrow 'Connection name' "$NET_CONN"
  [[ -n $NET_LOCAL_IP ]] && _hrow 'Local address' "$NET_LOCAL_IP"
  [[ -n $PUB_IP ]] && _hrow 'Public address' "$PUB_IP"
  [[ -n $NET_GW ]] && _hrow 'Gateway' "$NET_GW"
  [[ -n $NET_DNS ]] && _hrow 'DNS' "$NET_DNS"
  printf '</table>'
  printf '<table style="border-collapse:collapse;width:100%%;margin-top:8px;font-size:13px">'
  printf '<tr style="color:#666;text-align:left"><th style="padding:4px 12px 4px 0">Interface</th><th style="padding:4px 12px 4px 0">Type</th><th style="padding:4px 12px 4px 0">State</th><th style="padding:4px 12px 4px 0">Address</th><th style="padding:4px 0">In / Out</th></tr>'
  local ifn
  for ifn in "${NET_IFACES[@]}"; do
    printf '<tr><td style="padding:3px 12px 3px 0">%s</td><td style="padding:3px 12px 3px 0;color:#666">%s</td><td style="padding:3px 12px 3px 0">%s</td><td style="padding:3px 12px 3px 0;font-variant-numeric:tabular-nums">%s</td><td style="padding:3px 0;font-variant-numeric:tabular-nums">%s / %s</td></tr>' \
      "$(html_escape "$ifn")" "$(html_escape "${IF_TYPE[$ifn]:-?}")" \
      "$(html_escape "${IF_STATE[$ifn]:-?}")" "$(html_escape "${IF_IP[$ifn]:--}")" \
      "$(fmt_size "${NET_RX[$ifn]:-0}")" "$(fmt_size "${NET_TX[$ifn]:-0}")"
  done
  printf '</table>'
  return 0
}

_hrow() {
  printf '<tr><td style="padding:3px 14px 3px 0;color:#666;white-space:nowrap">%s</td><td style="padding:3px 0;font-variant-numeric:tabular-nums">%s</td></tr>' \
    "$(html_escape "$1")" "$(html_escape "$2")"
}

report_html() {
  local hours=${1:-24}
  local verdict accent='#15803d'
  verdict=$(_verdict)
  case $verdict in
    ATTENTION*) accent='#b91c1c' ;;
    DEGRADED*) accent='#b45309' ;;
    'PLAN AHEAD'*) accent='#b45309' ;;
    MOSTLY*) accent='#a16207' ;;
  esac
  {
    printf '<div style="font:14px/1.6 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111;max-width:720px">'
    printf '<div style="font-size:13px;color:#888;letter-spacing:.08em;text-transform:uppercase">Daily report</div>'
    printf '<div style="font-size:22px;font-weight:600;margin:2px 0 2px">%s</div>' "$(html_escape "$HOSTNAME_S")"
    printf '<div style="color:#777">%(%A %d %B %Y)T</div>' -1
    printf '<div style="margin:18px 0;padding:12px 14px;border-left:4px solid %s;background:#f8f9fa;font-weight:600">%s</div>' \
      "$accent" "$(html_escape "$verdict")"

    if ((R_ROWS > 0)); then
      printf '<div style="font-weight:600;margin:22px 0 8px">Performance</div><table style="border-collapse:collapse;width:100%%">'
      _hrow 'CPU' "avg ${R[cpu_avg]}%, peak ${R[cpu_max]}%, ${R[cpu_busy_min]} min busy"
      _hrow 'CPU steal' "avg ${R[steal_avg]}%, peak ${R[steal_max]}%"
      _hrow 'iowait' "avg ${R[io_avg]}%, peak ${R[io_max]}%"
      _hrow 'Load' "avg $(fmt_fixed "${R[load_avg]}" 1000 2), peak $(fmt_fixed "${R[load_max]}" 1000 2) over $CPU_COUNT cores"
      _hrow 'Memory' "avg ${R[mem_avg]}%, peak ${R[mem_max]}%, ${R[mem_busy_min]} min high"
      _hrow 'Swap' "peak ${R[swap_max]}%"
      printf '</table>'

      printf '<div style="font-weight:600;margin:22px 0 8px">Storage</div><table style="border-collapse:collapse;width:100%%">'
      local mp
      for mp in "${MOUNTS[@]}"; do
        _hrow "$mp" "${MP_PCT[$mp]}% — $(fmt_size "${MP_AVAIL[$mp]:-0}") free of $(fmt_size "${MP_SIZE[$mp]:-0}")"
      done
      ((${R[disk_delta]} != 0)) && _hrow '24h change' "$(printf '%+d' "${R[disk_delta]}") points"
      ((${R[disk_days]:-0} > 0)) && _hrow 'Projection' "full in about ${R[disk_days]} days"
      printf '</table>'

      printf '<div style="font-weight:600;margin:22px 0 8px">Network</div><table style="border-collapse:collapse;width:100%%">'
      _hrow 'Interface' "${NET_WAN:-none}"
      _hrow 'Transferred' "$(fmt_size "${R[rx_bytes]}") down / $(fmt_size "${R[tx_bytes]}") up"
      _hrow 'Peak rate' "$(fmt_rate "${R[rx_peak]}") down / $(fmt_rate "${R[tx_peak]}") up"
      _hrow 'Retransmits' "avg $(fmt_fixed "${R[retrans_avg]}" 10 2)%, peak $(fmt_fixed "${R[retrans_max]}" 10 2)%"
      ((${R[lat_avg]} > 0)) && _hrow 'Latency' "avg $(fmt_fixed "${R[lat_avg]}" 1000 1)ms, peak $(fmt_fixed "${R[lat_max]}" 1000 1)ms"
      printf '</table>'
    fi

    report_connection_html

    if report_speed "$hours"; then
      printf '<div style="font-weight:600;margin:22px 0 8px">Throughput tests</div><table style="border-collapse:collapse;width:100%%">'
      _hrow 'Tests run' "${S[n]}"
      _hrow 'Download' "avg $(fmt_rate "${S[down_avg]}"), worst $(fmt_rate "${S[down_min]}"), best $(fmt_rate "${S[down_max]}")"
      _hrow 'Upload' "avg $(fmt_rate "${S[up_avg]}"), best $(fmt_rate "${S[up_max]}")"
      ((${S[best]:-0} > 0)) && _hrow 'vs all-time best' "$((S[down_avg] * 100 / S[best]))% of $(fmt_rate "${S[best]}")"
      printf '</table>'
    fi

    if cfg_on highway_track && ((HW_PRESENT)); then
      printf '<div style="font-weight:600;margin:22px 0 8px">Highway node</div><table style="border-collapse:collapse;width:100%%">'
      _hrow 'Status' "$HW_HEALTH — $HW_HEALTH_WHY"
      _hrow 'Version' "${HW_VERSION:-unknown}$( ((HW_UPDATE)) && printf ' (update: %s)' "$HW_LATEST")"
      ((R_ROWS > 0)) && _hrow 'Active' "${R[hw_up_pct]}% of the window"
      ((${R[hw_restarts]:-0} > 0)) && _hrow 'Restarts' "${R[hw_restarts]} in ${hours}h"
      if ((HW_PID > 0)); then
        _hrow 'Process' "pid $HW_PID, up $(fmt_dur "$HW_UPTIME"), $HW_THR threads"
        _hrow 'Memory' "$(fmt_size "$HW_RSS") now, $(fmt_size "${R[hw_rss_max]:-0}") peak"
      fi
      _hrow 'Mesh tunnel' "${HW_NEBULA:-not detected}"
      _hrow 'Journal (1h)' "$HW_JOURNAL_ERR errors, $HW_JOURNAL_WARN warnings"
      printf '</table>'
    fi

    report_alerts "$hours"
    printf '<div style="font-weight:600;margin:22px 0 8px">Alerts</div>'
    if ((${#RA_TS[@]} == 0)); then
      printf '<div style="color:#15803d">None in the last %sh.</div>' "$hours"
    else
      printf '<table style="border-collapse:collapse;width:100%%">'
      local i col
      for ((i = 0; i < ${#RA_TS[@]} && i < 25; i++)); do
        col='#a16207'
        [[ ${RA_SEV[i]} == crit ]] && col='#b91c1c'
        printf '<tr><td style="padding:3px 14px 3px 0;color:#666;white-space:nowrap">%(%H:%M)T</td><td style="padding:3px 8px 3px 0;color:%s;font-weight:600">%s</td><td style="padding:3px 0">%s</td></tr>' \
          "${RA_TS[i]}" "$col" "${RA_SEV[i]}" "$(html_escape "${RA_MSG[i]}")"
      done
      printf '</table>'
      ((${#RA_TS[@]} > 25)) && printf '<div style="color:#666">and %s more</div>' $((${#RA_TS[@]} - 25))
    fi

    printf '<div style="color:#888;font-size:12px;margin-top:26px;border-top:1px solid #e5e7eb;padding-top:12px">'
    printf 'hyn-view %s on %s &middot; %s cores, %s &middot; uptime %s<br>' \
      "$HYN_VERSION" "$(html_escape "$HOSTNAME_S")" "$CPU_COUNT" \
      "$(html_escape "${KERNEL:-}")" "$(fmt_dur "$UPTIME_S")"
    printf '%s &middot; built by <a href="%s" style="color:#666">%s</a>' \
      "$HYN_COPYRIGHT" "$HYN_AUTHOR_URL" "$(html_escape "$HYN_AUTHOR")"
    printf '</div></div>'
  }
  return 0
}

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
report_run() {
  local send=0 hours=${CFG[report_hours]:-24} a
  for a in "$@"; do
    case $a in
      --send) send=1 ;;
      --hours=*) hours=${a#*=} ;;
    esac
  done
  [[ $hours =~ ^[0-9]+$ ]] || hours=24

  alerts_collect
  report_aggregate "$hours" || true

  if ((send == 0)); then
    report_text "$hours"
    return 0
  fi

  local subject
  local v
  v=$(_verdict)
  subject="[hyn] $HOSTNAME_S daily report — ${v%% —*}"
  if notify_send info "$subject" "$(report_text "$hours")" "$(report_html "$hours")"; then
    printf 'hyn: daily report sent to %s\n' "${CFG[notify_to]}"
    return 0
  fi
  printf 'hyn: could not send the daily report: %s\n' "${NOTIFY_LAST_ERR:-unknown error}" >&2
  return 1
}
