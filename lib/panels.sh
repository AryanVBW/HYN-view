#!/usr/bin/env bash
# hyn-view :: panels and layout
#
# Layout rule: the network panel is allocated first and gets every leftover row
# for its graph. Everything else fits around it, and panels that do not fit are
# dropped from the bottom up. That is a deliberate inversion of how htop and btop
# lay out -- they treat CPU as the headline -- because on a relay node the
# network is the headline and CPU is usually the boring part.

declare -a P_NET=() P_CPU_=() P_MEM=() P_DISK=() P_PROCS=() P_NODE=() P_ROW=()

# ---------------------------------------------------------------------------
# header / footer
# ---------------------------------------------------------------------------
HDR_OUT=''
header_line() {
  local w=$1 clock right
  # The right side is built first and never dropped: the node health verdict is
  # the one thing an operator wants visible at every terminal size, and at 80
  # columns the naive "truncate the whole line" approach threw it away.
  right=''
  if cfg_on highway_track && [[ $HW_HEALTH != absent ]]; then
    local hs=idle
    case $HW_HEALTH in
      ok) hs=ok ;;
      warn) hs=warn ;;
      crit) hs=crit ;;
    esac
    status_dot_v "$hs" "HIGHWAY $HW_HEALTH"
    right+="$STATUS_OUT  "
  fi
  printf -v clock '%(%H:%M:%S)T' -1
  right+="${C[dim]}$clock${C[reset]}"
  vlen "$right"
  local rw=$VLEN

  # Left segments in descending importance. Added while they fit, so a narrow
  # terminal loses the distro string rather than the load average.
  fmt_dur_v "$UPTIME_S"
  local -a segs=(
    "${C[title]}${C[bold]}$HOSTNAME_S${C[reset]}"
    "${C[dim]}load${C[reset]} ${LOAD1:-?} ${LOAD5:-?} ${LOAD15:-?}"
    "${C[dim]}up${C[reset]} $FMT_OUT"
    "${C[accent]}${C[bold]}hyn${C[reset]}${C[dim]} $HYN_VERSION${C[reset]}"
    "${C[dim]}$KERNEL${C[reset]}"
    "${C[dim]}$DISTRO${C[reset]}"
  )
  local left='' cand s
  for s in "${segs[@]}"; do
    vlen "$s"
    ((VLEN == 0)) && continue
    if [[ -z $left ]]; then cand=$s; else cand="$left  $s"; fi
    vlen "$cand"
    ((VLEN + rw + 3 > w)) && continue
    left=$cand
  done

  vlen "$left"
  local gap=$((w - VLEN - rw - 2))
  if ((gap < 1)); then
    # Even the hostname alone does not fit beside the badge: keep the badge.
    fit_v " $right" "$w"
    HDR_OUT=$FIT_OUT
  else
    rep_v ' ' "$gap"
    HDR_OUT=" $left$REP_OUT$right "
  fi
  return 0
}

FTR_OUT=''
footer_line() {
  local w=$1 s right
  s="${C[dim]}"
  s+="${C[accent]}q${C[dim]} quit  "
  s+="${C[accent]}1${C[dim]} dash ${C[accent]}0${C[dim]} simple ${C[accent]}2${C[dim]} net ${C[accent]}3${C[dim]} proc ${C[accent]}4${C[dim]} node  "
  s+="${C[accent]}t${C[dim]} theme  ${C[accent]}p${C[dim]} profile  ${C[accent]}u${C[dim]} units  ${C[accent]}m${C[dim]} sort  "
  s+="${C[accent]}s${C[dim]} test  ${C[accent]}+/-${C[dim]} rate  ${C[accent]}i${C[dim]} iface"
  s+="${C[reset]}"

  # Attribution lives on the status bar: present in every view, at the
  # conventional place for it, without taking a row from the data.
  right="${C[dim]}$HYN_PKG ${C[reset]}${C[accent2]}$HYN_AUTHOR${C[reset]}"
  if ((UPD_AVAILABLE)); then
    right="${C[warn]}$G_UP v$UPD_LATEST${C[reset]}  $right"
  fi

  vlen " $s"; local lw=$VLEN
  vlen "$right"; local rw=$VLEN
  if ((lw + rw + 3 <= w)); then
    rep_v ' ' $((w - lw - rw - 1))
    FTR_OUT=" $s$REP_OUT$right "
  elif ((rw + 2 <= w)); then
    # Too narrow for both: the credit stays, the key hints are discoverable
    # with `h` anyway.
    rep_v ' ' $((w - rw - 1))
    FTR_OUT="$REP_OUT$right "
  else
    fit_v " $s" "$w"
    FTR_OUT=$FIT_OUT
  fi
  return 0
}

# ---------------------------------------------------------------------------
# NETWORK
# ---------------------------------------------------------------------------
# graph_h is per-direction: the panel draws graph_h rows of rx growing up and
# graph_h rows of tx growing down, sharing one scale so the two are comparable
# by eye. Independent scales would make a 10 Mbps upload look like a 900 Mbps
# one, which is worse than no graph.
panel_net() {
  local w=$2 graph_h=$3
  local iface=${NET_WAN:-}
  local inner=$((w - 4))
  local right='' line safe rxa txa gmax i
  P_NET=()

  if [[ -z $iface ]]; then
    panel_open P_NET "$w" 'NETWORK' 'no interface'
    panel_row P_NET "$w" "${C[warn]}no usable interface found${C[reset]}"
    panel_close P_NET "$w"
    return 0
  fi

  net_link "$iface"
  net_identity
  net_ident_label
  # The interface name is what the kernel calls it; the SSID or connection name
  # is what the operator calls it. Show the recognisable one first.
  right="$iface"
  [[ -n $NET_IDENT_LABEL ]] && right+=" ${C[accent]}$NET_IDENT_LABEL${C[reset]}"
  [[ -n $LINK_SPEED ]] && { fmt_rate_v $((LINK_SPEED * 125000)); right+=" ${C[dim]}·${C[reset]} $FMT_OUT"; }
  [[ -n $NET_LOCAL_IP ]] && right+=" · $NET_LOCAL_IP"
  [[ -n $PUB_IP ]] && right+=" · wan $PUB_IP"
  panel_open P_NET "$w" 'NETWORK' "$right" "${C[accent]}"

  safe=${iface//[^A-Za-z0-9]/_}
  rxa="HRX_$safe" txa="HTX_$safe"

  local gw=$((inner))
  arr_max_v "$rxa" $((gw * 2)); local mrx=$ARR_MAX
  arr_max_v "$txa" $((gw * 2)); local mtx=$ARR_MAX
  gmax=$mrx
  ((mtx > gmax)) && gmax=$mtx
  ((gmax < 1024)) && gmax=1024

  # rx summary
  fmt_rate_v "${NET_RXR[$iface]:-0}"; local rxs=$FMT_OUT
  fmt_rate_v "${NET_PEAK_RX[$iface]:-0}"; local rxp=$FMT_OUT
  fmt_size_v "${NET_RX[$iface]:-0}"; local rxt=$FMT_OUT
  fmt_count_v "${NET_RPPS[$iface]:-0}"; local rxpps=$FMT_OUT
  pad_v "${C[rx]}$G_DOWN $rxs${C[reset]}" 20
  line="$PAD_OUT${C[dim]}peak${C[reset]} "
  pad_v "$rxp" 13; line+="$PAD_OUT${C[dim]}total${C[reset]} "
  pad_v "$rxt" 12; line+="$PAD_OUT${C[dim]}pps${C[reset]} $rxpps"
  if cfg_on graph_stats && ((inner >= 86)); then
    arr_stats_v "$rxa" $((gw * 2))
    fmt_rate_v "$ARR_AVG"
    line+="  ${C[dim]}avg${C[reset]} $FMT_OUT"
  fi
  panel_row P_NET "$w" "$line"

  if ((graph_h > 0)) && [[ ${CFG[graph]} != off && ${CFG[graph]} != none ]]; then
    local grad=0
    cfg_on graph_gradient && grad=1
    if [[ ${CFG[graph]} == block || ${CFG[graph]} == bar ]]; then
      # One block-glyph row per direction. Coarser than braille (8 vertical
      # levels against 24, and one sample per column against two) but roughly a
      # tenth of the cost, which is the point of offering it.
      sparkline_v "$rxa" "$gw" "$gmax" "${C[rx]}"
      panel_raw P_NET "$w" "$SPARK_OUT"
      _net_axis "$w" "$inner" "$gmax"
      sparkline_v "$txa" "$gw" "$gmax" "${C[tx]}"
      panel_raw P_NET "$w" "$SPARK_OUT"
    else
      braille_plot "$rxa" "$gw" "$graph_h" "$gmax" "${C[rx]}" 0 "$grad"
      for i in "${!BR_OUT[@]}"; do panel_raw P_NET "$w" "${BR_OUT[i]}"; done
      _net_axis "$w" "$inner" "$gmax"
      local tx_h=$graph_h
      if ((gmax > 0)); then
        tx_h=$(((mtx * graph_h + gmax - 1) / gmax))
        ((tx_h < 2)) && tx_h=2
        ((tx_h > graph_h)) && tx_h=$graph_h
      fi
      braille_plot "$txa" "$gw" "$tx_h" "$gmax" "${C[tx]}" 1 "$grad"
      for i in "${!BR_OUT[@]}"; do panel_raw P_NET "$w" "${BR_OUT[i]}"; done
    fi
    # A time ruler turns "there was a spike" into "there was a spike 4 min ago".
    if cfg_on graph_axis && ((inner >= 40)); then
      parse_fixed3_v "${CFG[interval]}"
      local isec=$((FIX3 / 1000)); ((isec < 1)) && isec=1
      local per=2
      [[ ${CFG[graph]} == block || ${CFG[graph]} == bar ]] && per=1
      time_axis_v "$inner" "$isec" "$per"
      panel_raw P_NET "$w" "$TIME_AXIS"
    fi
  fi

  # tx summary
  fmt_rate_v "${NET_TXR[$iface]:-0}"; local txs=$FMT_OUT
  fmt_rate_v "${NET_PEAK_TX[$iface]:-0}"; local txp=$FMT_OUT
  fmt_size_v "${NET_TX[$iface]:-0}"; local txt=$FMT_OUT
  fmt_count_v "${NET_TPPS[$iface]:-0}"; local txpps=$FMT_OUT
  pad_v "${C[tx]}$G_UP $txs${C[reset]}" 20
  line="$PAD_OUT${C[dim]}peak${C[reset]} "
  pad_v "$txp" 13; line+="$PAD_OUT${C[dim]}total${C[reset]} "
  pad_v "$txt" 12; line+="$PAD_OUT${C[dim]}pps${C[reset]} $txpps"
  if cfg_on graph_stats && ((inner >= 86)); then
    arr_stats_v "$txa" $((gw * 2))
    fmt_rate_v "$ARR_AVG"
    line+="  ${C[dim]}avg${C[reset]} $FMT_OUT"
  fi
  panel_row P_NET "$w" "$line"

  # health counters
  local errc=${C[ok]} e_rx=${NET_RERR_R[$iface]:-0} e_tx=${NET_TERR_R[$iface]:-0}
  local d_rx=${NET_RDROP_R[$iface]:-0} d_tx=${NET_TDROP_R[$iface]:-0}
  ((e_rx + e_tx + d_rx + d_tx > 0)) && errc=${C[crit]}
  line="${C[dim]}err${C[reset]} $errc$e_rx/$e_tx${C[reset]}"
  line+="  ${C[dim]}drop${C[reset]} $errc$d_rx/$d_tx${C[reset]}"
  net_retrans_permille
  local rtc=${C[ok]}
  ((NET_RETRANS_PM > 10)) && rtc=${C[warn]}
  ((NET_RETRANS_PM > 50)) && rtc=${C[crit]}
  fmt_fixed_v "$NET_RETRANS_PM" 10 1
  line+="  ${C[dim]}retrans${C[reset]} $rtc${SNMPR[Tcp.RetransSegs]:-0}/s ($FMT_OUT%)${C[reset]}"
  local ld=${SNMPR[TcpExt.ListenDrops.raw]:-0}
  local ldc=${C[ok]}
  ((ld > 0)) && ldc=${C[crit]}
  line+="  ${C[dim]}listen-drop${C[reset]} $ldc$ld${C[reset]}"
  if net_conntrack; then
    local ctc=${C[ok]}
    ((CT_PCT > 70)) && ctc=${C[warn]}
    ((CT_PCT > 90)) && ctc=${C[crit]}
    fmt_count_v "$CT_COUNT"; local ctn=$FMT_OUT
    fmt_count_v "$CT_MAX"
    line+="  ${C[dim]}ct${C[reset]} $ctc$ctn/$FMT_OUT${C[reset]}"
  fi
  panel_row P_NET "$w" "$line"

  # latency
  line=''
  local k
  for k in gw 'gw*'; do
    [[ -v LAT_MS[$k] ]] || continue
    _lat_seg gw "$k"
    line+="$LAT_SEG  "
  done
  for k in "${!LAT_MS[@]}"; do
    [[ $k == gw || $k == 'gw*' || $k == dns ]] && continue
    _lat_seg "${k%\*}" "$k"
    line+="$LAT_SEG  "
  done
  if [[ -v LAT_MS[dns] ]]; then
    _lat_seg dns dns
    line+="$LAT_SEG  "
  fi
  if [[ -z $line ]]; then
    line="${C[dim]}latency probe starting…${C[reset]}"
  elif ((LAT_AGE > 120)); then
    line+="${C[warn]}(stale ${LAT_AGE}s)${C[reset]}"
  fi
  panel_row P_NET "$w" "$line"

  # socket states
  line="${C[dim]}tcp${C[reset]} "
  local est=${TCPST[ESTAB]:-${SOCK[TCP.inuse]:-0}}
  line+="estab $est"
  line+="  ${C[dim]}tw${C[reset]} ${TCPST[TIME_WAIT]:-${SOCK[TCP.tw]:-0}}"
  line+="  ${C[dim]}listen${C[reset]} ${TCPST[LISTEN]:-0}"
  local sr=${TCPST[SYN_RECV]:-0}
  local src=${C[fg]}
  ((sr > 32)) && src=${C[warn]}
  line+="  ${C[dim]}syn-recv${C[reset]} $src$sr${C[reset]}"
  line+="  ${C[dim]}udp${C[reset]} ${SOCK[UDP.inuse]:-0}"
  local ue=${SNMPR[Udp.InErrors.raw]:-0} rbe=${SNMPR[Udp.RcvbufErrors.raw]:-0}
  local uec=${C[ok]}
  ((ue + rbe > 0)) && uec=${C[crit]}
  line+="  ${C[dim]}udp-err${C[reset]} $uec$((ue + rbe))${C[reset]}"
  ((TCP_TRUNCATED)) && line+="  ${C[warn]}(capped)${C[reset]}"
  panel_row P_NET "$w" "$line"

  # speed test
  _speed_line "$inner"
  panel_row P_NET "$w" "$SPEED_LINE"
  # Who we are connected to and through what. Second-to-last so the frequently
  # changing numbers stay at a stable height above it.
  if cfg_on net_identity && ((inner >= 60)); then
    line=''
    [[ -n $NET_SSID ]] && line+="${C[dim]}ssid${C[reset]} ${C[accent]}$NET_SSID${C[reset]}  "
    [[ -n $NET_CONN && $NET_CONN != "$iface" ]] && line+="${C[dim]}conn${C[reset]} $NET_CONN  "
    [[ -n ${IF_TYPE[$iface]:-} ]] && line+="${C[dim]}type${C[reset]} ${IF_TYPE[$iface]}  "
    [[ -n $NET_GW ]] && line+="${C[dim]}gw${C[reset]} $NET_GW  "
    [[ -n ${LINK_MAC:-} ]] && ((inner >= 96)) && line+="${C[dim]}mac${C[reset]} $LINK_MAC  "
    if [[ -n $NET_DNS ]]; then
      local dns=$NET_DNS
      ((inner < 110)) && dns=${dns%%,*}
      line+="${C[dim]}dns${C[reset]} $dns"
    fi
    [[ -n $line ]] && panel_row P_NET "$w" "$line"
  fi
  panel_close P_NET "$w"
  return 0
}

# The shared-scale marker between the rx and tx plots. Both directions are drawn
# against one maximum so their heights are directly comparable -- independent
# scales would make a 10 Mbps upload look like a 900 Mbps one -- and this row is
# what turns that relative shape into an absolute magnitude.
_net_axis() {
  local w=$1 inner=$2 gmax=$3
  fmt_rate_v "$gmax"
  rep_v "$G_HLINE" $((inner - ${#FMT_OUT} - 3))
  panel_raw P_NET "$w" "${C[border]}$REP_OUT ${C[dim]}$FMT_OUT${C[reset]}"
  return 0
}

# One "target 8.20ms 0%" segment. A '*' suffix on the label means the figure
# came from a TCP handshake because ICMP was unavailable -- a different
# measurement, so it is labelled rather than silently mixed in.
LAT_SEG=''
_lat_seg() {
  local label=$1 us=${LAT_MS[$2]} loss=${LAT_LOSS[$2]:-0}
  local star=''
  [[ $2 == *\* ]] && star='*'
  if [[ ! $us =~ ^[0-9]+$ ]] || ((us < 0)); then
    LAT_SEG="${C[dim]}$label$star ${C[crit]}-${C[reset]}"
    return 0
  fi
  local c=${C[ok]}
  ((us > 50000)) && c=${C[warn]}
  ((us > 150000)) && c=${C[crit]}
  fmt_fixed_v "$us" 1000 2
  LAT_SEG="${C[dim]}$label$star${C[reset]} $c$FMT_OUT${C[reset]}${C[dim]}ms${C[reset]}"
  if [[ $loss =~ ^[0-9]+$ ]] && ((loss > 0)); then
    LAT_SEG+=" ${C[crit]}${loss}%${C[reset]}"
  fi
  return 0
}

SPEED_LINE=''
_speed_line() {
  local w=$1 out
  st_history_read
  if ((ST_LAST_DOWN == 0)); then
    if [[ -n $ST_LAST_NOTE && $ST_LAST_NOTE != ok ]]; then
      SPEED_LINE="${C[dim]}speedtest${C[reset]} ${C[warn]}$ST_LAST_NOTE${C[reset]}"
    else
      SPEED_LINE="${C[dim]}speedtest${C[reset]} ${C[dim]}no result yet — run: hyn speedtest${C[reset]}"
    fi
    return 0
  fi
  fmt_rate_v "$ST_LAST_DOWN"; out="${C[dim]}speed${C[reset]} ${C[rx]}$G_DOWN $FMT_OUT${C[reset]}"
  fmt_rate_v "$ST_LAST_UP"; out+=" ${C[tx]}$G_UP $FMT_OUT${C[reset]}"
  if ((ST_LAST_LAT > 0)); then
    fmt_fixed_v "$ST_LAST_LAT" 1000 1
    out+="  ${C[dim]}ping${C[reset]} ${FMT_OUT}ms"
  fi
  local age=$((${EPOCHSECONDS:-0} - ST_LAST_TS))
  fmt_dur_v "$age"
  out+="  ${C[dim]}$FMT_OUT ago${C[reset]}"
  # Trend sparkline over stored history: the shape is the point, not the values.
  vlen "$out"
  local room=$((w - VLEN - 2))
  if ((room > 8 && ${#ST_H_DOWN[@]} > 1)); then
    sparkline_v ST_H_DOWN "$room" 0 "${C[accent2]}"
    out+="  $SPARK_OUT"
  fi
  SPEED_LINE=$out
  return 0
}

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------
panel_cpu() {
  local w=$2 maxrows=${3:-99} right line
  local inner=$((w - 4))
  local -a body=()
  P_CPU_=()
  right="${CPU_COUNT}c"
  [[ -n $CPU_MHZ ]] && right+=" · ${CPU_MHZ} MHz"
  [[ -n $CPU_TEMP ]] && right+=" · ${CPU_TEMP}°C"
  # Package draw belongs beside the clock and the temperature: the three of them
  # together are what say whether a busy CPU is also a hot, thirsty one.
  if [[ -n ${PWR_CPU_DW:-} ]]; then
    fmt_fixed_v "$PWR_CPU_DW" 10 1
    right+=" · ${FMT_OUT}W"
  fi

  # Rows are built in priority order and then emitted up to the caller's budget,
  # so a short terminal loses the reference information rather than the load.
  local bw=$((inner - 30))
  ((bw < 8)) && bw=8
  ((bw > 28)) && bw=28
  bar_v "$CPU_PCT" "$bw"
  pad_v "$CPU_PCT%" 5
  body+=("${C[fg]}$PAD_OUT${C[reset]}$BAR_OUT")

  line="${C[dim]}usr${C[reset]} $CPU_USER  ${C[dim]}sys${C[reset]} $CPU_SYS"
  line+="  ${C[dim]}io${C[reset]} $CPU_IOWAIT  ${C[dim]}irq${C[reset]} $CPU_IRQ"
  # steal is called out in colour: on a VPS it is the difference between "my
  # node is slow" and "my host is oversold", and it is the one number here an
  # operator can act on by changing provider.
  local sc=${C[ok]}
  ((CPU_STEAL >= 2)) && sc=${C[warn]}
  ((CPU_STEAL >= 10)) && sc=${C[crit]}
  line+="  ${C[dim]}steal${C[reset]} $sc$CPU_STEAL%${C[reset]}"
  body+=("$line")

  if ((${#CORE_PCT[@]} > 0)); then
    local cw=${#CORE_PCT[@]}
    ((cw > inner - 7)) && cw=$((inner - 7))
    heat_strip_v CORE_PCT "$cw"
    body+=("${C[dim]}cores${C[reset]} $HEAT_OUT")
  fi

  line="${C[dim]}run${C[reset]} $PROCS_RUN  ${C[dim]}blk${C[reset]} $PROCS_BLK"
  fmt_count_v "$CPU_CTXT_R"; line+="  ${C[dim]}ctx${C[reset]} $FMT_OUT/s"
  fmt_count_v "$CPU_FORK_R"; line+="  ${C[dim]}fork${C[reset]} $FMT_OUT/s"
  body+=("$line")

  if ((${#PSI[@]} > 0)); then
    line="${C[dim]}psi${C[reset]} "
    local r n c
    for r in cpu io memory; do
      n=${PSI[$r.some]:-}
      [[ -n $n ]] || continue
      c=${C[ok]}
      ((n >= 500)) && c=${C[warn]}
      ((n >= 2000)) && c=${C[crit]}
      fmt_fixed_v "$n" 100 1
      line+="${C[dim]}${r:0:3}${C[reset]} $c$FMT_OUT%${C[reset]}  "
    done
    body+=("$line")
  fi
  # Power draw, when the platform will say. The source is named next to the
  # number because "118W psu" is a measurement of the machine and "17W cpu+dram"
  # is an estimate of part of it, and an operator sizing a UPS needs to know
  # which one they are reading.
  #
  # Ordering is load-bearing. panel_row truncates from the right, and in a
  # two-column dash this panel is about 44 columns wide, so whatever goes last
  # gets an ellipsis. Losing mains is the only fact here that is an incident
  # rather than a measurement, so it goes FIRST when it happens; cpu and dram are
  # the detail and go last, where losing them costs nothing.
  if [[ -n ${PWR_INPUT_DW:-} || -n ${PWR_CPU_DW:-} || -n ${PWR_AC:-} ]]; then
    line="${C[dim]}power${C[reset]} "
    if [[ ${PWR_AC:-} == 0 ]]; then
      line+="${C[crit]}${C[bold]}on battery${C[reset]}"
      [[ -n ${PWR_BAT_PCT:-} ]] && line+=" ${C[crit]}${PWR_BAT_PCT}%${C[reset]}"
      line+='  '
    fi
    if [[ -n ${PWR_INPUT_DW:-} ]]; then
      fmt_fixed_v "$PWR_INPUT_DW" 10 1
      line+="${C[bold]}${FMT_OUT}W${C[reset]}"
      local psrc
      psrc=$(power_src_label "${PWR_INPUT_SRC:-}")
      [[ -n $psrc ]] && line+=" ${C[dim]}$psrc${C[reset]}"
      line+='  '
    fi
    if [[ -n ${PWR_CPU_DW:-} ]]; then
      fmt_fixed_v "$PWR_CPU_DW" 10 1; line+="${C[dim]}cpu${C[reset]} ${FMT_OUT}W  "
    fi
    if [[ -n ${PWR_DRAM_DW:-} ]]; then
      fmt_fixed_v "$PWR_DRAM_DW" 10 1; line+="${C[dim]}dram${C[reset]} ${FMT_OUT}W  "
    fi
    # Mains present is the unremarkable case, so it is a quiet note at the end
    # and is the first thing dropped on a narrow panel.
    if [[ ${PWR_AC:-} == 1 ]]; then
      line+="${C[dim]}mains${C[reset]}"
      [[ -n ${PWR_BAT_PCT:-} ]] && ((PWR_BAT_PCT < 100)) && line+=" ${C[dim]}bat ${PWR_BAT_PCT}%${C[reset]}"
    fi
    body+=("$line")
  fi
  [[ -n $CPU_MODEL && $CPU_MODEL != unknown ]] && body+=("${C[dim]}$CPU_MODEL${C[reset]}")

  panel_open P_CPU_ "$w" 'CPU' "$right"
  local i
  for ((i = 0; i < ${#body[@]} && i < maxrows; i++)); do panel_row P_CPU_ "$w" "${body[i]}"; done
  panel_close P_CPU_ "$w"
  return 0
}

# ---------------------------------------------------------------------------
# MEMORY
# ---------------------------------------------------------------------------
panel_mem() {
  local w=$2 maxrows=${3:-99} line
  local inner=$((w - 4))
  local -a body=()
  P_MEM=()
  fmt_size_v "$MEM_TOTAL"
  local right=$FMT_OUT

  local bw=$((inner - 22))
  ((bw < 8)) && bw=8
  ((bw > 24)) && bw=24
  bar_v "$MEM_PCT" "$bw"
  pad_v "$MEM_PCT%" 5
  fmt_size_v "$MEM_USED"
  body+=("${C[fg]}$PAD_OUT${C[reset]}$BAR_OUT ${C[dim]}$FMT_OUT${C[reset]}")

  if ((SWAP_TOTAL > 0)); then
    bar_v "$SWAP_PCT" "$bw"
    pad_v "$SWAP_PCT%" 5
    fmt_size_v "$SWAP_USED"
    body+=("${C[dim]}swap${C[reset]} $PAD_OUT$BAR_OUT ${C[dim]}$FMT_OUT${C[reset]}")
  else
    body+=("${C[dim]}swap  none configured${C[reset]}")
  fi

  fmt_size_v "$MEM_CACHE"; line="${C[dim]}cache${C[reset]} $FMT_OUT"
  if ((inner >= 42)); then fmt_size_v "$MEM_BUF"; line+="  ${C[dim]}buf${C[reset]} $FMT_OUT"; fi
  fmt_size_v "$MEM_AVAIL"; line+="  ${C[dim]}avail${C[reset]} $FMT_OUT"
  body+=("$line")

  fmt_size_v "$MEM_DIRTY"; line="${C[dim]}dirty${C[reset]} $FMT_OUT"
  fmt_size_v "$MEM_COMMIT"; line+="  ${C[dim]}commit${C[reset]} $FMT_OUT"
  body+=("$line")

  panel_open P_MEM "$w" 'MEMORY' "$right"
  local i
  for ((i = 0; i < ${#body[@]} && i < maxrows; i++)); do panel_row P_MEM "$w" "${body[i]}"; done
  panel_close P_MEM "$w"
  return 0
}

# ---------------------------------------------------------------------------
# DISK
# ---------------------------------------------------------------------------
panel_disk() {
  local w=$2 maxmounts=${3:-3} maxrows=${4:-99} line n=0
  local inner=$((w - 4))
  # Mount rows and device rows share the budget; mounts win, because running out
  # of disk takes a node down while a busy disk only slows it.
  ((maxmounts > maxrows - 1)) && maxmounts=$((maxrows - 1))
  ((maxmounts < 1)) && maxmounts=1
  P_DISK=()
  panel_open P_DISK "$w" 'DISK' ''
  disk_usage
  # Bars and the number of rows both scale with the panel: a full-width DISK
  # panel showing three short lines wastes the space it was given.
  local bw=$((inner / 4))
  ((bw < 6)) && bw=6
  ((bw > 30)) && bw=30
  local maxdev=2
  ((inner >= 90)) && { maxdev=4; ((maxmounts += 2)); }
  ((maxmounts > maxrows)) && maxmounts=$maxrows
  local mp
  for mp in "${MOUNTS[@]}"; do
    ((n >= maxmounts)) && break
    ((n++))
    local mw=12
    ((inner < 44)) && mw=9
    bar_v "${MP_PCT[$mp]}" "$bw"
    pad_v "$mp" "$mw"
    fmt_size_v "${MP_AVAIL[$mp]}"; local avail=$FMT_OUT
    line="${C[fg]}$PAD_OUT${C[reset]}$BAR_OUT ${C[fg]}${MP_PCT[$mp]}%${C[reset]}"
    if ((inner >= 44)); then
      pad_v " ${C[dim]}$avail free${C[reset]}" 18
      line+="$PAD_OUT"
    else
      line+=" ${C[dim]}$avail${C[reset]}"
    fi
    if ((inner >= 74)); then
      fmt_size_v "${MP_USED[$mp]}"; local used=$FMT_OUT
      fmt_size_v "${MP_SIZE[$mp]}"
      line+="${C[dim]}$used of $FMT_OUT${C[reset]}"
    fi
    panel_row P_DISK "$w" "$line"
  done
  local d emitted=$n
  n=0
  for d in "${DISKS[@]}"; do
    ((n >= maxdev)) && break
    ((emitted + n >= maxrows)) && break
    ((n++))
    local dw=8 rw=16
    ((inner < 44)) && { dw=6; rw=13; }
    pad_v "$d" "$dw"
    line="${C[dim]}$PAD_OUT${C[reset]}"
    fmt_rate_v "${DISK_RD[$d]:-0}"; pad_v "${C[rx]}r $FMT_OUT${C[reset]}" "$rw"; line+="$PAD_OUT"
    fmt_rate_v "${DISK_WR[$d]:-0}"; pad_v "${C[tx]}w $FMT_OUT${C[reset]}" "$rw"; line+="$PAD_OUT"
    local u=${DISK_UTIL[$d]:-0} uc=${C[ok]}
    ((u > 70)) && uc=${C[warn]}
    ((u > 90)) && uc=${C[crit]}
    if ((inner >= 44)); then
      pad_v "$uc${u}% busy${C[reset]}" 12; line+="$PAD_OUT"
      fmt_fixed_v "${DISK_AWAIT[$d]:-0}" 100 1
      line+="${C[dim]}await${C[reset]} ${FMT_OUT}ms"
    else
      line+="$uc${u}%${C[reset]}"
    fi
    if ((inner >= 74)) && [[ ${DISK_INFLIGHT[$d]:-0} =~ ^[0-9]+$ ]]; then
      line+="  ${C[dim]}queue${C[reset]} ${DISK_INFLIGHT[$d]}"
    fi
    panel_row P_DISK "$w" "$line"
  done
  panel_close P_DISK "$w"
  return 0
}

# ---------------------------------------------------------------------------
# PROCESSES
# ---------------------------------------------------------------------------
# proc_state_label_v <rank> -- the group name and colour for a state rank
# (0..3, see proc_state_rank_v). One place defining "what a rank is called",
# so the group divider and the per-row dot always agree with each other.
PROC_STATE_LABEL='' PROC_STATE_COLOR=''
proc_state_label_v() {
  case $1 in
    0) PROC_STATE_LABEL='ACTIVE' PROC_STATE_COLOR=${C[ok]} ;;
    1) PROC_STATE_LABEL='PAUSED' PROC_STATE_COLOR=${C[warn]} ;;
    2) PROC_STATE_LABEL='STOPPED' PROC_STATE_COLOR=${C[crit]} ;;
    *) PROC_STATE_LABEL='INACTIVE' PROC_STATE_COLOR=${C[dim]} ;;
  esac
  return 0
}

# Rows arrive from proc_sample already sequenced active -> paused -> stopped ->
# inactive (see proc_state_rank_v). This panel's only job is to show that
# sequence: a coloured state dot per row, green/yellow/red/dim, and one slim
# divider the moment the group changes -- not a repeated header per state, and
# not a re-sort, since the data is already in the right order.
panel_proc() {
  local w=$2 nrows=$3 line i
  local inner=$((w - 4))
  P_PROCS=()
  fmt_thousands_v "$PROC_TOTAL"; local pt=$FMT_OUT
  fmt_thousands_v "$PROC_THREADS"
  panel_open P_PROCS "$w" 'PROCESSES' "$pt procs · $FMT_OUT thr · by ${CFG[proc_sort]}"
  # Columns are dropped, not truncated, as the panel narrows. An ellipsis in the
  # middle of a header row tells the reader nothing; fewer columns still tell
  # them which process is busy and how busy it is.
  local show_user=0 show_thr=0
  ((inner >= 54)) && show_thr=1
  ((inner >= 66)) && show_user=1
  local wpid=7 wcpu=7 wrss=10 wuser=10 wthr=5

  pad_v 'PID' "$wpid"; line="${C[dim]}$PAD_OUT"
  ((show_user)) && { pad_v 'USER' "$wuser"; line+="$PAD_OUT"; }
  pad_v 'CPU%' "$wcpu"; line+="$PAD_OUT"
  pad_v 'RSS' "$wrss"; line+="$PAD_OUT"
  ((show_thr)) && { pad_v 'THR' "$wthr"; line+="$PAD_OUT"; }
  line+="  COMMAND${C[reset]}"
  panel_row P_PROCS "$w" "$line"

  local prev_rank=-1 rank
  for ((i = 0; i < ${#P_PID[@]} && i < nrows; i++)); do
    proc_state_rank_v "${P_STATE[i]}"; rank=$PROC_STATE_RANK
    if ((rank != prev_rank)); then
      proc_state_label_v "$rank"
      rep_v "$G_HLINE" 2
      panel_row P_PROCS "$w" "$PROC_STATE_COLOR$REP_OUT $PROC_STATE_LABEL${C[reset]}"
      prev_rank=$rank
    fi
    pad_v "${P_PID[i]}" "$wpid"; line="${C[dim]}$PAD_OUT${C[reset]}"
    if ((show_user)); then
      pad_v "${P_USER[i]}" "$wuser"; line+="${C[dim]}$PAD_OUT${C[reset]}"
    fi
    fmt_fixed_v "${P_CPU[i]}" 10 1
    local cp=$((${P_CPU[i]} / 10))
    grad_v $((cp > 100 ? 100 : cp))
    pad_v "$FMT_OUT" "$wcpu"; line+="$GRAD_OUT$PAD_OUT${C[reset]}"
    fmt_size_v "${P_RSS[i]}"
    pad_v "$FMT_OUT" "$wrss"; line+="$PAD_OUT"
    if ((show_thr)); then
      pad_v "${P_THR[i]}" "$wthr"; line+="${C[dim]}$PAD_OUT${C[reset]}"
    fi
    proc_state_label_v "$rank"
    line+="$PROC_STATE_COLOR$G_DOT${C[reset]} "
    # The node's own process is highlighted: it is why the operator is here.
    case ${P_NAME[i]} in
      highway | hw-os | nebula) line+="${C[accent]}${C[bold]}${P_NAME[i]}${C[reset]}" ;;
      *) line+="${C[fg]}${P_NAME[i]}${C[reset]}" ;;
    esac
    panel_row P_PROCS "$w" "$line"
  done
  panel_close P_PROCS "$w"
  return 0
}

# ---------------------------------------------------------------------------
# HIGHWAY NODE
# ---------------------------------------------------------------------------
panel_node() {
  local w=$2 maxunits=${3:-3} maxrows=${4:-99} line right u n=0
  local inner=$((w - 4))
  local -a body=()
  P_NODE=()
  right=''
  if [[ -n $HW_VERSION ]]; then
    right="$HW_VERSION"
    [[ -n $HW_VERSION_SRC ]] && right+=" (${HW_VERSION_SRC})"
  fi
  if [[ -n $HW_LATEST ]]; then
    if ((HW_UPDATE)); then right+=" ${C[warn]}$G_UP $HW_LATEST${C[reset]}"
    elif [[ -z $HW_VERSION ]]; then right="latest $HW_LATEST"; fi
  fi
  panel_open P_NODE "$w" 'HIGHWAY NODE' "$right" "${C[accent2]}"

  if ((HW_PRESENT == 0)); then
    body+=("${C[dim]}no binary at $HW_BIN${C[reset]}")
    [[ -n $HW_LATEST ]] && body+=("${C[dim]}current release $HW_LATEST${C[reset]}")
    body+=("${C[dim]}set highway_track=off to hide this panel${C[reset]}")
    _node_emit "$w" "$maxrows"
    return 0
  fi

  local hs=idle
  case $HW_HEALTH in ok) hs=ok ;; warn) hs=warn ;; crit) hs=crit ;; esac
  status_dot_v "$hs" "$HW_HEALTH"
  body+=("$STATUS_OUT ${C[dim]}$HW_HEALTH_WHY${C[reset]}")

  for u in "${HW_UNITS[@]}"; do
    ((n >= maxunits)) && break
    ((n++))
    local st=${HW_STATE[$u]:-?} sub=${HW_SUB[$u]:-?} r=${HW_RESTARTS[$u]:-0}
    # Column widths shrink with the panel. At dashboard widths the node panel is
    # often the narrowest column on screen, and an ellipsis in place of the
    # restart count would hide the number that matters most.
    local nw sw
    if ((inner >= 52)); then nw=18 sw=17
    elif ((inner >= 42)); then nw=15 sw=15
    else nw=12 sw=11; fi
    status_dot_v "$st" ''
    pad_v "${u%.service}" "$nw"
    line="$STATUS_OUT ${C[fg]}$PAD_OUT${C[reset]}"
    pad_v "$st/$sub" "$sw"
    line+="${C[dim]}$PAD_OUT${C[reset]}"
    local rc=${C[dim]}
    [[ $r =~ ^[0-9]+$ ]] && ((r >= 3)) && rc=${C[warn]}
    line+="$rc${r}x${C[reset]}"
    if ((inner >= 52)) && [[ ${HW_MEM[$u]:-} =~ ^[0-9]+$ ]]; then
      fmt_size_v "${HW_MEM[$u]}"
      line+="  ${C[dim]}$FMT_OUT${C[reset]}"
    fi
    body+=("$line")
  done

  if ((HW_PID > 0)); then
    fmt_fixed_v "$HW_CPU" 10 1; line="${C[dim]}pid${C[reset]} $HW_PID  ${C[dim]}cpu${C[reset]} ${FMT_OUT}%"
    fmt_size_v "$HW_RSS"; line+="  ${C[dim]}rss${C[reset]} $FMT_OUT"
    line+="  ${C[dim]}thr${C[reset]} $HW_THR"
    if ((inner >= 48)); then
      if ((HW_FDS > 0)); then line+="  ${C[dim]}fd${C[reset]} $HW_FDS"; else line+="  ${C[dim]}fd${C[reset]} -"; fi
    fi
    body+=("$line")
    fmt_dur_v "$HW_UPTIME"
    body+=("${C[dim]}running${C[reset]} $FMT_OUT")
  fi

  if [[ -n $HW_NEBULA ]]; then
    fmt_rate_v "${NET_RXR[$HW_NEBULA]:-0}"; line="${C[dim]}tunnel${C[reset]} $HW_NEBULA ${C[rx]}$G_DOWN $FMT_OUT${C[reset]}"
    fmt_rate_v "${NET_TXR[$HW_NEBULA]:-0}"; line+=" ${C[tx]}$G_UP $FMT_OUT${C[reset]}"
    local nd=$((${NET_RDROP_R[$HW_NEBULA]:-0} + ${NET_TDROP_R[$HW_NEBULA]:-0}))
    local ndc=${C[ok]}
    ((nd > 0)) && ndc=${C[crit]}
    line+="  ${C[dim]}drop${C[reset]} $ndc$nd${C[reset]}"
    body+=("$line")
  else
    body+=("${C[dim]}tunnel${C[reset]} ${C[warn]}no mesh interface detected${C[reset]}")
  fi

  line=''
  [[ -n $HW_QDISC ]] && line+="${C[dim]}qdisc${C[reset]} $HW_QDISC"
  [[ -n $HW_QDISC_DROPS ]] && line+=" ${C[dim]}drops${C[reset]} $HW_QDISC_DROPS"
  [[ -n ${TUNE[cc]:-} ]] && line+="  ${C[dim]}cc${C[reset]} ${TUNE[cc]}"
  [[ -n $HW_NFT_TABLES ]] && line+="  ${C[dim]}nft${C[reset]} $HW_NFT_TABLES"
  [[ -n $line ]] && body+=("$line")

  local ec=${C[ok]} wc=${C[dim]}
  ((HW_JOURNAL_ERR > 0)) && ec=${C[crit]}
  ((HW_JOURNAL_WARN > 0)) && wc=${C[warn]}
  line="${C[dim]}journal 1h${C[reset]} $ec$HW_JOURNAL_ERR err${C[reset]} $wc$HW_JOURNAL_WARN warn${C[reset]}"
  if ((HW_SIZE > 0)); then
    fmt_size_v "$HW_SIZE"
    line+="  ${C[dim]}bin${C[reset]} $FMT_OUT"
    [[ -n $HW_MTIME_H ]] && line+=" ${C[dim]}($HW_MTIME_H old)${C[reset]}"
  fi
  body+=("$line")
  _node_emit "$w" "$maxrows"
  return 0
}

# Emits panel_node's collected rows within its budget. `body` is panel_node's
# local, visible here through bash's dynamic scoping -- this is a private helper
# for that one caller, not a general-purpose function. It is named `body` rather
# than `rows` precisely because panel_disk uses `rows` as a count, and one name
# meaning two things inside a dynamically scoped call graph is a live grenade.
#
# Row 0 is the health verdict and therefore always survives: if only one row
# fits, "crit -- no active unit" is the one worth keeping.
_node_emit() {
  local w=$1 maxrows=$2 i
  for ((i = 0; i < ${#body[@]} && i < maxrows; i++)); do panel_row P_NODE "$w" "${body[i]}"; done
  panel_close P_NODE "$w"
  return 0
}

# ---------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------
declare -a PANEL_ORDER=()
panels_enabled() {
  local p
  declare -gA PANEL_ON=()
  PANEL_ORDER=()
  local oIFS=$IFS
  IFS=,
  for p in ${CFG[panels]}; do
    [[ -n $p ]] || continue
    PANEL_ON[$p]=1
    [[ $p == net ]] || PANEL_ORDER+=("$p")
  done
  IFS=$oIFS
  return 0
}

# Render one named panel into its array at the given width, within a budget of
# <budget> TOTAL rows including both borders. Height comes back in PANEL_H and
# the array name in PANEL_VAR.
PANEL_H=0
PANEL_VAR=''
_render_panel() {
  local name=$1 width=$2 budget=$3
  local content=$((budget - 2))
  PANEL_H=0 PANEL_VAR=''
  ((content < 1)) && return 1
  case $name in
    cpu) panel_cpu P_CPU_ "$width" "$content"; PANEL_H=${#P_CPU_[@]}; PANEL_VAR=P_CPU_ ;;
    mem) panel_mem P_MEM "$width" "$content"; PANEL_H=${#P_MEM[@]}; PANEL_VAR=P_MEM ;;
    node)
      cfg_on highway_track || return 1
      panel_node P_NODE "$width" 3 "$content"
      PANEL_H=${#P_NODE[@]}; PANEL_VAR=P_NODE ;;
    disk) panel_disk P_DISK "$width" 2 "$content"; PANEL_H=${#P_DISK[@]}; PANEL_VAR=P_DISK ;;
    proc)
      local pr=${CFG[proc_rows]}
      [[ $pr =~ ^[0-9]+$ ]] || pr=8
      # one content row is the column header
      ((pr > content - 1)) && pr=$((content - 1))
      ((pr < 1)) && return 1
      panel_proc P_PROCS "$width" "$pr"
      PANEL_H=${#P_PROCS[@]}; PANEL_VAR=P_PROCS ;;
    *) return 1 ;;
  esac
  return 0
}

# frame_open <width> -- every render_* function starts a frame the same way:
# draw the header, reset the line buffer, and seed it with that header line.
# Five render functions repeated this verbatim; one helper means the header
# logic can only drift in one place instead of five.
frame_open() {
  header_line "$1"
  fb_reset
  fb_add "$HDR_OUT"
  return 0
}

# frame_close <width> <height> -- pads the buffer out to a full screen and pins
# the footer to the last row. Same repetition as frame_open, at the other end
# of every render function.
frame_close() {
  local w=$1 h=$2
  while ((${#FB[@]} < h - 1)); do fb_add ''; done
  footer_line "$w"
  FB[h - 1]=$FTR_OUT
  return 0
}

# The dashboard.
#
# Row budget is settled before anything is drawn, and the network panel is paid
# first: on a relay node the traffic graph is the reason the tool is open, so at
# 80x24 it keeps its graph and the disk panel is what gets dropped. Priority is
# the order of the `panels` config key, so an operator who disagrees can reorder
# it rather than patching this function.
render_dash() {
  local w=$TERM_COLS h=$TERM_ROWS
  local avail=$((h - 2))

  frame_open "$w"

  # Graph height scales with the terminal. Two rows is the floor at which a
  # braille plot still shows a shape rather than a smear.
  local graph_h=0
  if ((avail >= 42)); then graph_h=6
  elif ((avail >= 36)); then graph_h=5
  elif ((avail >= 30)); then graph_h=4
  elif ((avail >= 21)); then graph_h=3
  elif ((avail >= 16)); then graph_h=2
  fi
  panel_net P_NET "$w" "$graph_h"
  fb_addmany "${P_NET[@]}"
  local left=$((avail - ${#P_NET[@]}))

  # Column widths for grouped rows.
  local cw1 cw2 cw3 percol
  if ((w >= 132)); then
    percol=3
    cw1=$(((w - 2) * 34 / 100)); cw2=$(((w - 2) * 30 / 100)); cw3=$((w - 2 - cw1 - cw2))
  elif ((w >= 92)); then
    percol=2
    cw1=$(((w - 1) / 2)); cw2=$((w - 1 - cw1)); cw3=0
  else
    percol=1
    cw1=$w; cw2=0; cw3=0
  fi

  local i=0 n=${#PANEL_ORDER[@]}
  while ((i < n && left >= 4)); do
    local name=${PANEL_ORDER[i]}
    [[ -v PANEL_ON[$name] ]] || { ((i++)); continue; }

    # Group the next panels side by side when the terminal is wide enough and
    # they are all "small" panels. proc and disk are wide by nature and get a
    # full row to themselves unless paired with each other.
    local group=1
    if ((percol > 1)); then
      case $name in
        cpu | mem | node) group=$percol ;;
        disk | proc) group=2 ;;
      esac
      ((group > n - i)) && group=$((n - i))
      ((group > percol)) && group=$percol
    fi

    if ((group <= 1)); then
      _render_panel "$name" "$w" "$left" || { ((i++)); continue; }
      if ((PANEL_H > left)); then ((i++)); continue; fi
      local -n _p=$PANEL_VAR
      fb_addmany "${_p[@]}"
      unset -n _p
      left=$((left - PANEL_H))
      ((i++))
      continue
    fi

    # Render each member, then equalise to the tallest and compose.
    local -a specs=() vars=()
    local gh=0 j wcol
    for ((j = 0; j < group; j++)); do
      case $j in
        0) wcol=$cw1 ;;
        1) wcol=$cw2 ;;
        *) wcol=$cw3 ;;
      esac
      _render_panel "${PANEL_ORDER[i + j]}" "$wcol" "$left" || continue
      ((PANEL_H > gh)) && gh=$PANEL_H
      specs+=("$PANEL_VAR:$wcol")
      vars+=("$PANEL_VAR")
    done
    if ((${#specs[@]} == 0 || gh > left)); then
      ((i += group))
      continue
    fi
    for ((j = 0; j < ${#vars[@]}; j++)); do
      _equalize "${vars[j]}" "${specs[j]##*:}" "$gh"
    done
    hstack P_ROW 1 "${specs[@]}"
    fb_addmany "${P_ROW[@]}"
    left=$((left - gh))
    ((i += group))
  done

  frame_close "$w" "$h"
  return 0
}

# Re-close a panel at a taller height so side-by-side panels share a bottom
# edge. The panel already ends with its own bottom border, which is dropped and
# redrawn. Slicing rather than `unset` keeps this safe through the nameref.
_equalize() {
  local name=$1 w=$2 target=$3
  local -n _ea=$name
  local cur=${#_ea[@]}
  ((cur >= target)) && return 0
  _ea=("${_ea[@]:0:cur - 1}")
  while ((${#_ea[@]} < target - 1)); do panel_row "$name" "$w" ''; done
  panel_close "$name" "$w"
  return 0
}

render_net_full() {
  local w=$TERM_COLS h=$TERM_ROWS
  frame_open "$w"
  local graph_h=$(((h - 2 - 8) / 2))
  ((graph_h > 14)) && graph_h=14
  ((graph_h < 0)) && graph_h=0
  panel_net P_NET "$w" "$graph_h"
  fb_addmany "${P_NET[@]}"

  # Remaining rows go to the other interfaces and the tuning snapshot: this view
  # is for someone diagnosing, not glancing.
  local left=$((h - 1 - ${#FB[@]} - 1))
  if ((left >= 4)); then
    local -a P_IF=()
    net_identity
    panel_open P_IF "$w" 'INTERFACES' "gw ${NET_GW:-none} · dns ${NET_DNS:-none}"
    local ifn n=0
    for ifn in "${NET_IFACES[@]}"; do
      ((n >= left - 3)) && break
      ((n++))
      pad_v "$ifn" 12
      local line="${C[fg]}$PAD_OUT${C[reset]}"
      pad_v "${IF_TYPE[$ifn]:-?}" 10; line+="${C[dim]}$PAD_OUT${C[reset]}"
      status_dot_v "${IF_STATE[$ifn]:-unknown}" "${IF_STATE[$ifn]:-?}"
      pad_v "$STATUS_OUT" 12; line+="$PAD_OUT"
      pad_v "${IF_IP[$ifn]:-—}" 20; line+="${C[fg]}$PAD_OUT${C[reset]}"
      fmt_rate_v "${NET_RXR[$ifn]:-0}"; pad_v "$G_DOWN $FMT_OUT" 15; line+="${C[rx]}$PAD_OUT${C[reset]}"
      fmt_rate_v "${NET_TXR[$ifn]:-0}"; pad_v "$G_UP $FMT_OUT" 15; line+="${C[tx]}$PAD_OUT${C[reset]}"
      if [[ -n ${IF_SSID[$ifn]:-} ]]; then
        line+="${C[accent]}${IF_SSID[$ifn]}${C[reset]}"
      else
        fmt_size_v "${NET_RX[$ifn]:-0}"; line+="${C[dim]}$FMT_OUT"
        fmt_size_v "${NET_TX[$ifn]:-0}"; line+=" / $FMT_OUT${C[reset]}"
      fi
      panel_row P_IF "$w" "$line"
    done
    net_tuning
    if ((n < left - 4)); then
      local t="${C[dim]}cc${C[reset]} ${TUNE[cc]:-?}  ${C[dim]}qdisc${C[reset]} ${TUNE[qdisc]:-?}"
      t+="  ${C[dim]}somaxconn${C[reset]} ${TUNE[somaxconn]:-?}"
      t+="  ${C[dim]}backlog${C[reset]} ${TUNE[backlog]:-?}"
      t+="  ${C[dim]}rmem-max${C[reset]} ${TUNE[rmem]:-?}"
      panel_row P_IF "$w" "$t"
    fi
    panel_close P_IF "$w"
    fb_addmany "${P_IF[@]}"
  fi
  frame_close "$w" "$h"
  return 0
}

render_proc_full() {
  local w=$TERM_COLS h=$TERM_ROWS
  frame_open "$w"
  panel_proc P_PROCS "$w" $((h - 5))
  fb_addmany "${P_PROCS[@]}"
  frame_close "$w" "$h"
  return 0
}

render_node_full() {
  local w=$TERM_COLS h=$TERM_ROWS
  frame_open "$w"
  panel_node P_NODE "$w" 8
  fb_addmany "${P_NODE[@]}"
  local left=$((h - 1 - ${#FB[@]} - 1))
  if ((left >= 4)) && ((${#HW_JOURNAL_TAIL[@]} > 0)); then
    local -a P_J=()
    panel_open P_J "$w" 'RECENT WARNINGS' 'read-only'
    local m n=0
    for m in "${HW_JOURNAL_TAIL[@]}"; do
      ((n >= left - 3)) && break
      ((n++))
      panel_row P_J "$w" "${C[dim]}$m${C[reset]}"
    done
    panel_close P_J "$w"
    fb_addmany "${P_J[@]}"
  fi
  frame_close "$w" "$h"
  return 0
}

# ---------------------------------------------------------------------------
# SIMPLE DASHBOARD -- premium, minimal, glanceable
# ---------------------------------------------------------------------------
# The advanced dashboard (render_dash) is for someone diagnosing. This one is
# for someone who just wants to know, from across the room: is the node up,
# is the internet fine, is the box hot. Four things, each answered in one
# glance, nothing repeated from panel to panel.

declare -a P_SIMPLE=()

# _simple_node_line -- one big coloured verdict for the Highway node, or a
# calm "not tracked" note when there is nothing to watch. This is the
# headline: on a relay box a node that is not running is the one fact that
# matters more than everything else in the view combined.
_simple_node_line() {
  local w=$1 line
  if ! cfg_on highway_track || [[ $HW_HEALTH == absent ]]; then
    line="${C[dim]}$G_DOT node tracking off${C[reset]}"
    panel_row P_SIMPLE "$w" "$line"
    return 0
  fi
  local word verdict
  case $HW_HEALTH in
    ok) word=ok verdict='RUNNING' ;;
    warn) word=warn verdict='DEGRADED' ;;
    crit) word=crit verdict='NOT RUNNING' ;;
    *) word=dim verdict='UNKNOWN' ;;
  esac
  local col=${C[$word]:-${C[dim]}}
  line="$col${C[bold]}$G_DOT $verdict${C[reset]}"
  [[ -n $HW_HEALTH_WHY ]] && line+="  ${C[dim]}$HW_HEALTH_WHY${C[reset]}"
  panel_row P_SIMPLE "$w" "$line"
  if ((HW_PID > 0)); then
    fmt_dur_v "$HW_UPTIME"
    panel_row P_SIMPLE "$w" "${C[dim]}up $FMT_OUT · ${HW_ACTIVE} unit(s) active${C[reset]}"
  fi
  return 0
}

# _simple_speed_lines -- current throughput, today's fastest result, and a
# braille sparkline of the day's tests so "the high" has a shape, not just a
# number. Falls back to a plain sentence when there is no history yet, rather
# than drawing an empty graphic that looks broken.
_simple_speed_lines() {
  local w=$1 inner=$2 line
  local iface=${NET_WAN:-}
  if [[ -n $iface ]]; then
    fmt_rate_v "${NET_RXR[$iface]:-0}"; line="${C[dim]}now${C[reset]}   ${C[rx]}${C[bold]}$G_DOWN $FMT_OUT${C[reset]}"
    fmt_rate_v "${NET_TXR[$iface]:-0}"; line+="  ${C[tx]}$G_UP $FMT_OUT${C[reset]}"
    panel_row P_SIMPLE "$w" "$line"
  fi

  st_today_high_v
  if ((ST_TODAY_HIGH == 0)); then
    panel_row P_SIMPLE "$w" "${C[dim]}today's high  no speed test yet — press s${C[reset]}"
    return 0
  fi
  fmt_rate_v "$ST_TODAY_HIGH"
  fmt_dur_v $((${EPOCHSECONDS:-0} - ST_TODAY_HIGH_TS))
  line="${C[dim]}high${C[reset]}  ${C[accent2]}${C[bold]}$G_UP $FMT_OUT${C[reset]} ${C[dim]}today, $FMT_OUT ago${C[reset]}"
  panel_row P_SIMPLE "$w" "$line"

  # The graphic: today's tests only, oldest to newest, so the bar chart reads
  # left-to-right as the day progressing rather than as a rolling window.
  local today i ts down
  local -a today_down=()
  printf -v today '%(%Y%m%d)T' -1
  for ((i = 0; i < ${#ST_H_TS[@]}; i++)); do
    ts=${ST_H_TS[i]} down=${ST_H_DOWN[i]}
    [[ $down =~ ^[0-9]+$ ]] || continue
    local day; printf -v day '%(%Y%m%d)T' "$ts"
    [[ $day == "$today" ]] && today_down+=("$down")
  done
  if ((${#today_down[@]} > 1 && inner >= 24)); then
    sparkline_v today_down $((inner - 2)) "$ST_TODAY_HIGH" "${C[accent2]}"
    panel_row P_SIMPLE "$w" "  $SPARK_OUT"
  fi
  return 0
}

# _simple_temp_line -- CPU temperature, the one sensor number a "simple" view
# keeps, coloured against fixed thresholds rather than a relative gradient:
# 70C means the same thing on every machine, so the colour should not depend
# on what else this box has seen.
_simple_temp_line() {
  local w=$1 line
  if [[ -z $CPU_TEMP ]]; then
    panel_row P_SIMPLE "$w" "${C[dim]}cpu temp  no thermal sensor${C[reset]}"
    return 0
  fi
  local tc=${C[ok]}
  ((CPU_TEMP >= 70)) && tc=${C[warn]}
  ((CPU_TEMP >= 85)) && tc=${C[crit]}
  local bw=20
  bar_v $((CPU_TEMP > 100 ? 100 : CPU_TEMP)) "$bw" "$tc"
  line="${C[dim]}cpu temp${C[reset]}  $tc${C[bold]}${CPU_TEMP}°C${C[reset]}  $BAR_OUT"
  panel_row P_SIMPLE "$w" "$line"
  return 0
}

# _simple_essentials_line -- the handful of facts worth one line each: memory,
# the tightest disk, and load. Anyone who needs more than this reaches for the
# advanced dashboard (key 1) or the dedicated panel (2/3/4) -- this view's job
# is to not make them read that far in the common case.
_simple_essentials_line() {
  local w=$1 line
  fmt_size_v "$MEM_USED"; local mu=$FMT_OUT
  fmt_size_v "$MEM_TOTAL"
  local mc=${C[ok]}
  ((MEM_PCT >= 80)) && mc=${C[warn]}
  ((MEM_PCT >= 93)) && mc=${C[crit]}
  line="${C[dim]}memory${C[reset]}  $mc$mu / $FMT_OUT ($MEM_PCT%)${C[reset]}"
  panel_row P_SIMPLE "$w" "$line"

  if ((${#MOUNTS[@]} > 0)); then
    local worst_mp='' worst_pct=-1 mp
    for mp in "${MOUNTS[@]}"; do
      local p=${MP_PCT[$mp]:-0}
      ((p > worst_pct)) && { worst_pct=$p; worst_mp=$mp; }
    done
    if [[ -n $worst_mp ]]; then
      fmt_size_v "${MP_AVAIL[$worst_mp]}"
      local dc=${C[ok]}
      ((worst_pct >= 80)) && dc=${C[warn]}
      ((worst_pct >= 93)) && dc=${C[crit]}
      line="${C[dim]}disk${C[reset]}    $dc$worst_mp ${worst_pct}%${C[reset]} ${C[dim]}($FMT_OUT free)${C[reset]}"
      panel_row P_SIMPLE "$w" "$line"
    fi
  fi

  line="${C[dim]}load${C[reset]}    ${LOAD1:-?} ${LOAD5:-?} ${LOAD15:-?}"
  fmt_dur_v "$UPTIME_S"
  line+="  ${C[dim]}up${C[reset]} $FMT_OUT"
  panel_row P_SIMPLE "$w" "$line"
  return 0
}

# _simple_power_line -- one line for what the machine is drawing, and whether it
# is drawing it from the wall. Absent on a box that cannot measure either, rather
# than printed as a dash: this view earns its place by being short, and a row
# saying "no power sensor" on every VM would be noise on the screen nobody is
# working at.
_simple_power_line() {
  local w=$1 line=''
  [[ -n ${PWR_INPUT_DW:-} || -n ${PWR_AC:-} ]] || return 1
  if [[ -n ${PWR_INPUT_DW:-} ]]; then
    fmt_fixed_v "$PWR_INPUT_DW" 10 1
    local psrc
    psrc=$(power_src_label "${PWR_INPUT_SRC:-}")
    line="${C[dim]}power${C[reset]}     ${C[bold]}${FMT_OUT}W${C[reset]}"
    [[ -n $psrc ]] && line+=" ${C[dim]}$psrc${C[reset]}"
  else
    line="${C[dim]}power${C[reset]}     "
  fi
  # Running on battery is the headline when it happens, so it is coloured and it
  # displaces the polite "mains".
  if [[ ${PWR_AC:-} == 0 ]]; then
    line+="  ${C[crit]}${C[bold]}ON BATTERY${C[reset]}"
    [[ -n ${PWR_BAT_PCT:-} ]] && line+=" ${C[crit]}${PWR_BAT_PCT}%${C[reset]}"
    [[ -n ${PWR_BAT_STATUS:-} ]] && line+=" ${C[dim]}${PWR_BAT_STATUS,,}${C[reset]}"
  elif [[ ${PWR_AC:-} == 1 ]]; then
    line+="  ${C[ok]}mains${C[reset]}"
    [[ -n ${PWR_BAT_PCT:-} ]] && ((PWR_BAT_PCT < 100)) && \
      line+=" ${C[dim]}battery ${PWR_BAT_PCT}%${C[reset]}"
  fi
  panel_row P_SIMPLE "$w" "$line"
  return 0
}

# render_simple -- the premium "just tell me" dashboard. One panel, four
# sections in fixed order (node, internet, temperature, essentials), each
# section appearing exactly once. Sized to fill whatever height is available
# rather than fighting the advanced view's multi-column layout logic.
render_simple() {
  local w=$TERM_COLS h=$TERM_ROWS
  frame_open "$w"

  local inner=$((w - 4))
  P_SIMPLE=()
  panel_open P_SIMPLE "$w" 'HYN' "$HOSTNAME_S" "${C[title]}"
  _simple_node_line "$w"
  panel_row P_SIMPLE "$w" ''
  _simple_speed_lines "$w" "$inner"
  panel_row P_SIMPLE "$w" ''
  _simple_temp_line "$w"
  # Directly under the temperature, because they are the same question asked two
  # ways and they move together.
  _simple_power_line "$w" || true
  panel_row P_SIMPLE "$w" ''
  _simple_essentials_line "$w"
  panel_close P_SIMPLE "$w"
  fb_addmany "${P_SIMPLE[@]}"

  frame_close "$w" "$h"
  return 0
}
