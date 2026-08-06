#!/usr/bin/env bash
# hyn-view :: network
#
# The reason this tool exists. A relay node's health is mostly a network story,
# so this collects more than throughput: error and drop counters, TCP retransmit
# and listen-drop rates, socket state distribution, conntrack headroom, and the
# split between local-hop and internet latency (which is what tells you whether
# a problem is yours or your provider's).
#
# Everything on the per-tick path reads /proc with builtins. The things that
# genuinely need a subprocess -- ping, address enumeration, public IP -- run in
# detached probes on their own slow cadence and drop results into cache files
# that the render loop just reads.

declare -A NET_RX=() NET_TX=() NET_RXR=() NET_TXR=()
declare -A NET_RERR=() NET_TERR=() NET_RDROP=() NET_TDROP=()
declare -A NET_RERR_R=() NET_TERR_R=() NET_RDROP_R=() NET_TDROP_R=()
declare -A NET_RPKT=() NET_TPKT=() NET_RPPS=() NET_TPPS=()
declare -A NET_PEAK_RX=() NET_PEAK_TX=()
declare -A _PREV=() _PREV_MS=()
declare -a NET_IFACES=()
NET_WAN='' NET_LAST_MS=0

RING_MAX=512
ring_push() {
  local -n _r=$1
  _r+=("$2")
  ((${#_r[@]} > RING_MAX + 128)) && _r=("${_r[@]: -$RING_MAX}")
  return 0
}

# delta_rate <key> <counter> <elapsed-ms> -> per-second rate in DELTA_RATE.
# Counter wrap or a device reset shows up as a negative delta; report 0 rather
# than a fabricated spike, and reseed so the next tick is correct.
DELTA_RATE=0 DELTA_RAW=0
delta_rate() {
  local key=$1 cur=$2 ms=$3 prev d
  prev=${_PREV[$key]:-}
  _PREV[$key]=$cur
  if [[ -z $prev ]] || ((ms <= 0)); then DELTA_RATE=0 DELTA_RAW=0; return 0; fi
  d=$((cur - prev))
  if ((d < 0)); then DELTA_RATE=0 DELTA_RAW=0; return 0; fi
  DELTA_RAW=$d
  DELTA_RATE=$((d * 1000 / ms))
  return 0
}

# ---------------------------------------------------------------------------
# interface discovery
# ---------------------------------------------------------------------------
net_iface_hidden() {
  local ifn=$1 pat
  local IFS=,
  for pat in ${CFG[hide_iface]}; do
    [[ -z $pat ]] && continue
    [[ $ifn == "$pat" || $ifn == "$pat"* ]] && return 0
  done
  return 1
}

# The default route's interface is the one that matters for a relay node. Read
# it from /proc/net/route rather than forking `ip route`: destination 00000000
# with the RTF_GATEWAY flag is the default.
net_find_wan() {
  if [[ ${CFG[wan_iface]} != auto ]]; then NET_WAN=${CFG[wan_iface]}; return 0; fi
  local ifn dest flags rest best='' bestmetric=999999 metric
  local -a f=()
  while read -r ifn dest _ flags _ _ metric rest; do
    [[ $ifn == Iface ]] && continue
    [[ $dest == 00000000 ]] || continue
    ((0x$flags & 0x2)) || continue
    [[ $metric =~ ^[0-9]+$ ]] || metric=0
    if ((metric < bestmetric)); then bestmetric=$metric best=$ifn; fi
  done <"$HYN_PROC/net/route" 2>/dev/null
  if [[ -z $best ]]; then
    # No default route (or IPv6-only). Fall back to the busiest non-hidden link.
    local top=0
    for ifn in "${NET_IFACES[@]}"; do
      ((${NET_RX[$ifn]:-0} > top)) && { top=${NET_RX[$ifn]}; best=$ifn; }
    done
  fi
  NET_WAN=$best
  return 0
}

# ---------------------------------------------------------------------------
# per-tick sample
# ---------------------------------------------------------------------------
declare -A NET_HIST_RX_KEYS=()
# net_sample [elapsed-ms] -- pass the interval when the caller already knows it
# (the render loop does), otherwise it is derived from the previous call. Taking
# it as a parameter keeps every collector on the same clock, so rates across
# panels are computed over identical windows.
net_sample() {
  local ms=${1:-} now line ifn rest
  local -a f=()
  now_ms_v; now=$NOW_MS
  if [[ -z $ms ]]; then
    ms=$((now - NET_LAST_MS))
    ((NET_LAST_MS == 0)) && ms=0
  fi
  NET_LAST_MS=$now
  NET_IFACES=()

  while IFS= read -r line; do
    [[ $line == *:* ]] || continue
    ifn=${line%%:*}
    ifn=${ifn//[[:space:]]/}
    [[ -z $ifn || $ifn == Inter-* || $ifn == face ]] && continue
    net_iface_hidden "$ifn" && continue
    rest=${line#*:}
    # Unquoted on purpose: word-splitting into an array is the fork-free way to
    # get fields out of a /proc line. `read -ra <<<"$rest"` would be a
    # here-string, which on bash 5.3 costs a pipe and a subshell every tick.
    # Safe from globbing because $rest is the numeric field run after the colon,
    # which the kernel generates -- see .shellcheckrc for the full argument.
    f=($rest)
    ((${#f[@]} < 16)) && continue
    NET_IFACES+=("$ifn")

    delta_rate "rx:$ifn" "${f[0]}" "$ms"; NET_RXR[$ifn]=$DELTA_RATE
    delta_rate "tx:$ifn" "${f[8]}" "$ms"; NET_TXR[$ifn]=$DELTA_RATE
    delta_rate "rp:$ifn" "${f[1]}" "$ms"; NET_RPPS[$ifn]=$DELTA_RATE
    delta_rate "tp:$ifn" "${f[9]}" "$ms"; NET_TPPS[$ifn]=$DELTA_RATE
    delta_rate "re:$ifn" "${f[2]}" "$ms"; NET_RERR_R[$ifn]=$DELTA_RAW
    delta_rate "rd:$ifn" "${f[3]}" "$ms"; NET_RDROP_R[$ifn]=$DELTA_RAW
    delta_rate "te:$ifn" "${f[10]}" "$ms"; NET_TERR_R[$ifn]=$DELTA_RAW
    delta_rate "td:$ifn" "${f[11]}" "$ms"; NET_TDROP_R[$ifn]=$DELTA_RAW

    NET_RX[$ifn]=${f[0]} NET_TX[$ifn]=${f[8]}
    NET_RPKT[$ifn]=${f[1]} NET_TPKT[$ifn]=${f[9]}
    NET_RERR[$ifn]=${f[2]} NET_RDROP[$ifn]=${f[3]}
    NET_TERR[$ifn]=${f[10]} NET_TDROP[$ifn]=${f[11]}

    ((${NET_RXR[$ifn]} > ${NET_PEAK_RX[$ifn]:-0})) && NET_PEAK_RX[$ifn]=${NET_RXR[$ifn]}
    ((${NET_TXR[$ifn]} > ${NET_PEAK_TX[$ifn]:-0})) && NET_PEAK_TX[$ifn]=${NET_TXR[$ifn]}

    # History rings are per-interface dynamic arrays; declare on first sight.
    # `declare -ga NAME` (no assignment) creates a real empty array -- writing
    # `declare -ga "NAME=()"` would store the literal string "()" as element 0.
    local safe=${ifn//[^A-Za-z0-9]/_}
    if [[ ! -v NET_HIST_RX_KEYS[$ifn] ]]; then
      NET_HIST_RX_KEYS[$ifn]=1
      declare -ga "HRX_$safe"
      declare -ga "HTX_$safe"
    fi
    ring_push "HRX_$safe" "${NET_RXR[$ifn]}"
    ring_push "HTX_$safe" "${NET_TXR[$ifn]}"
  done <"$HYN_PROC/net/dev"

  [[ -z $NET_WAN ]] && net_find_wan
  return 0
}

# ---------------------------------------------------------------------------
# link details (/sys, so all builtin reads)
# ---------------------------------------------------------------------------
LINK_SPEED='' LINK_DUPLEX='' LINK_MTU='' LINK_CARRIER='' LINK_STATE='' LINK_MAC='' LINK_DRIVER=''
net_link() {
  # Split across two statements: bash expands every word of a `local` command
  # before any of its assignments take effect, so referring to $ifn in the same
  # `local` reads it as unset (and aborts under set -u).
  local ifn=$1
  local base="$HYN_SYS/class/net/$ifn"
  LINK_SPEED='' LINK_DUPLEX='' LINK_MTU='' LINK_CARRIER='' LINK_STATE='' LINK_MAC='' LINK_DRIVER=''
  [[ -d $base ]] || return 1
  readval LINK_SPEED "$base/speed"
  readval LINK_DUPLEX "$base/duplex"
  readval LINK_MTU "$base/mtu"
  readval LINK_CARRIER "$base/carrier"
  readval LINK_STATE "$base/operstate"
  readval LINK_MAC "$base/address"
  # Virtual links report speed -1 or nothing; treat that as unknown, not 0.
  [[ $LINK_SPEED == -1 ]] && LINK_SPEED=''
  if [[ -L $base/device/driver ]]; then
    LINK_DRIVER=$(readlink "$base/device/driver" 2>/dev/null)
    LINK_DRIVER=${LINK_DRIVER##*/}
  fi
  return 0
}

# ---------------------------------------------------------------------------
# sockets
# ---------------------------------------------------------------------------
declare -A SOCK=()
net_sockstat() {
  local line proto rest
  local -a f=()
  SOCK=()
  while IFS= read -r line; do
    proto=${line%%:*}
    rest=${line#*: }
    f=($rest)
    local i
    for ((i = 0; i + 1 < ${#f[@]}; i += 2)); do SOCK[$proto.${f[i]}]=${f[i + 1]}; done
  done <"$HYN_PROC/net/sockstat" 2>/dev/null
  if [[ -r $HYN_PROC/net/sockstat6 ]]; then
    while IFS= read -r line; do
      proto=${line%%:*}
      rest=${line#*: }
      f=($rest)
      local i
      for ((i = 0; i + 1 < ${#f[@]}; i += 2)); do SOCK[6$proto.${f[i]}]=${f[i + 1]}; done
    done <"$HYN_PROC/net/sockstat6"
  fi
  return 0
}

# TCP state histogram. /proc/net/tcp can hold tens of thousands of rows on a
# busy node, so this runs on tcp_states_interval (default 5s), not every tick,
# and stops at TCP_SCAN_CAP rows -- a truncated histogram with an honest flag
# beats a 200ms stall in the render loop.
declare -A TCPST=()
declare -a LISTEN_PORTS=()
TCP_SCAN_CAP=20000
TCP_TRUNCATED=0
_TCP_STATE_NAME=(x ESTAB SYN_SENT SYN_RECV FIN_WAIT1 FIN_WAIT2 TIME_WAIT CLOSE CLOSE_WAIT LAST_ACK LISTEN CLOSING NEW_SYN_RECV)

net_tcp_states() {
  local file st n=0 port hexport local_addr
  TCPST=() LISTEN_PORTS=() TCP_TRUNCATED=0
  declare -A seen_ports=()
  for file in "$HYN_PROC/net/tcp" "$HYN_PROC/net/tcp6"; do
    [[ -r $file ]] || continue
    while read -r _ local_addr _ st _; do
      [[ $st =~ ^[0-9A-Fa-f]{2}$ ]] || continue
      if ((++n > TCP_SCAN_CAP)); then TCP_TRUNCATED=1; break; fi
      local idx=$((16#$st))
      ((idx > 12)) && idx=0
      local name=${_TCP_STATE_NAME[idx]}
      ((TCPST[$name]++))
      if ((idx == 10)); then
        hexport=${local_addr##*:}
        port=$((16#$hexport))
        [[ -v seen_ports[$port] ]] || { seen_ports[$port]=1; LISTEN_PORTS+=("$port"); }
      fi
    done <"$file"
  done
  TCPST[TOTAL]=$n
  return 0
}

# ---------------------------------------------------------------------------
# SNMP / netstat counters
# ---------------------------------------------------------------------------
# These are the counters that actually diagnose a flaky node: RetransSegs and
# TCPSynRetrans mean loss on the path, ListenDrops/ListenOverflows mean the
# service is not accepting fast enough, Udp InErrors/RcvbufErrors mean the
# Nebula tunnel is dropping datagrams.
declare -A SNMP=() SNMPR=()
_snmp_parse() {
  local file=$1 line proto rest pending='' i
  local -a names=() vals=()
  [[ -r $file ]] || return 0
  while IFS= read -r line; do
    [[ $line == *:\ * ]] || continue
    proto=${line%%:*}
    rest=${line#*: }
    if [[ -z $pending ]]; then
      names=($rest)
      pending=$proto
    else
      vals=($rest)
      if [[ $pending == "$proto" ]]; then
        for ((i = 0; i < ${#names[@]} && i < ${#vals[@]}; i++)); do
          SNMP[$proto.${names[i]}]=${vals[i]}
        done
        pending=''
      else
        names=($rest)
        pending=$proto
      fi
    fi
  done <"$file"
  return 0
}

_snmp_rate() {
  local key=$1 ms=$2
  [[ -v SNMP[$key] ]] || { SNMPR[$key]=0; return 0; }
  delta_rate "snmp:$key" "${SNMP[$key]}" "$ms"
  SNMPR[$key]=$DELTA_RATE
  SNMPR[$key.raw]=$DELTA_RAW
  return 0
}

net_snmp() {
  local ms=$1
  SNMP=()
  _snmp_parse "$HYN_PROC/net/snmp"
  _snmp_parse "$HYN_PROC/net/netstat"
  local k
  for k in Tcp.RetransSegs Tcp.InErrs Tcp.OutRsts Tcp.ActiveOpens Tcp.PassiveOpens \
           Tcp.AttemptFails Tcp.EstabResets Tcp.InSegs Tcp.OutSegs Tcp.CurrEstab \
           Udp.InErrors Udp.NoPorts Udp.RcvbufErrors \
           Udp.SndbufErrors Udp.InDatagrams Udp.OutDatagrams TcpExt.ListenDrops \
           TcpExt.ListenOverflows TcpExt.TCPSynRetrans TcpExt.TCPLostRetransmit \
           TcpExt.TCPTimeouts TcpExt.TCPBacklogDrop Ip.InReceives Ip.InDiscards; do
    _snmp_rate "$k" "$ms"
  done
  return 0
}

# Retransmit share of outbound segments, in per-mille. A raw retransmit rate is
# not interpretable on its own: 50/s is alarming on an idle node and irrelevant
# under 200k segments/s. Both operands are the same tick's deltas.
NET_RETRANS_PM=0
net_retrans_permille() {
  local out=${SNMPR[Tcp.OutSegs.raw]:-0} re=${SNMPR[Tcp.RetransSegs.raw]:-0}
  if ((out > 0)); then NET_RETRANS_PM=$((re * 1000 / out)); else NET_RETRANS_PM=0; fi
  return 0
}

# ---------------------------------------------------------------------------
# conntrack + tuning (plain sysctl reads, no fork)
# ---------------------------------------------------------------------------
CT_COUNT='' CT_MAX='' CT_PCT=0
net_conntrack() {
  CT_COUNT='' CT_MAX='' CT_PCT=0
  readval CT_COUNT "$HYN_PROC/sys/net/netfilter/nf_conntrack_count" || return 1
  readval CT_MAX "$HYN_PROC/sys/net/netfilter/nf_conntrack_max" || return 1
  [[ $CT_MAX =~ ^[0-9]+$ ]] && ((CT_MAX > 0)) && CT_PCT=$((CT_COUNT * 100 / CT_MAX))
  return 0
}

declare -A TUNE=()
net_tuning() {
  TUNE=()
  local v
  readval v "$HYN_PROC/sys/net/ipv4/tcp_congestion_control" && TUNE[cc]=$v
  readval v "$HYN_PROC/sys/net/core/default_qdisc" && TUNE[qdisc]=$v
  readval v "$HYN_PROC/sys/net/core/somaxconn" && TUNE[somaxconn]=$v
  readval v "$HYN_PROC/sys/net/core/netdev_max_backlog" && TUNE[backlog]=$v
  readval v "$HYN_PROC/sys/net/ipv4/tcp_max_syn_backlog" && TUNE[synbacklog]=$v
  readval v "$HYN_PROC/sys/net/ipv4/ip_forward" && TUNE[forward]=$v
  readval v "$HYN_PROC/sys/net/ipv4/tcp_rmem" && TUNE[rmem]=${v##*$'\t'}
  readval v "$HYN_PROC/sys/net/ipv4/tcp_wmem" && TUNE[wmem]=${v##*$'\t'}
  readval v "$HYN_PROC/sys/net/ipv4/tcp_fastopen" && TUNE[fastopen]=$v
  readval v "$HYN_PROC/sys/fs/file-nr" && TUNE[filenr]=$v
  return 0
}

# ---------------------------------------------------------------------------
# latency / DNS probe
# ---------------------------------------------------------------------------
# Runs detached on latency_interval and writes one TSV line per target. The
# render loop only reads the file, so a hung or slow probe can never stall a
# frame -- worst case the panel shows a slightly stale number, which it labels.
declare -A LAT_MS=() LAT_LOSS=() LAT_JIT=()
LAT_AGE=-1 LAT_GW='' _LAT_PID=0 _LAT_FILE=''

# "8.456" -> 8456 (microseconds). Bash has no floats and one fork per sample to
# get one is not worth it.
_ms_to_us() {
  local s=$1 whole frac
  whole=${s%%.*}
  frac=${s#*.}
  [[ $frac == "$s" ]] && frac=0
  frac=${frac}000
  frac=${frac:0:3}
  [[ $whole =~ ^[0-9]+$ ]] || whole=0
  [[ $frac =~ ^[0-9]+$ ]] || frac=0
  printf '%d' $((whole * 1000 + 10#$frac))
}

# Default gateway IPv4 from /proc/net/route: little-endian hex, so the octets
# come out of the word in reverse.
net_gateway_ip() {
  local ifn dest gw flags rest g
  while read -r ifn dest gw flags rest; do
    [[ $ifn == Iface ]] && continue
    [[ $dest == 00000000 ]] || continue
    ((0x$flags & 0x2)) || continue
    g=$((16#$gw))
    printf '%d.%d.%d.%d' $((g & 255)) $(((g >> 8) & 255)) $(((g >> 16) & 255)) $(((g >> 24) & 255))
    return 0
  done <"$HYN_PROC/net/route" 2>/dev/null
  return 1
}

# One probe pass. Runs in a detached child; forks here are fine and bounded.
net_probe_once() {
  local out='' t gw
  local -a targets=()
  # First line is the probe's own completion time, so the reader can label a
  # stale panel without a stat(1) fork every tick.
  out="#ts	${EPOCHSECONDS:-0}"$'\n'
  if cfg_on latency_gateway; then
    gw=$(net_gateway_ip) && [[ -n $gw ]] && targets+=("gw=$gw")
  fi
  local IFS=,
  for t in ${CFG[latency_targets]}; do
    [[ -n $t ]] && targets+=("$t=$t")
  done
  unset IFS

  local spec label host line loss avg jit rtt
  for spec in "${targets[@]}"; do
    label=${spec%%=*} host=${spec#*=}
    loss=-1 avg=-1 jit=-1
    if have ping; then
      while IFS= read -r line; do
        case $line in
          *'packet loss'*)
            # Parse leftward from the literal "% packet loss": some ping builds
            # inject "+N errors," between "received," and the loss figure, which
            # breaks the more obvious forward parse.
            loss=${line%%'% packet loss'*}
            loss=${loss##* }
            [[ $loss =~ ^[0-9]+$ ]] || loss=-1
            ;;
          rtt*=* | round-trip*=*)
            rtt=${line#*= }
            rtt=${rtt% ms}
            local -a p=()
            local oIFS=$IFS; IFS=/; p=($rtt); IFS=$oIFS
            ((${#p[@]} >= 2)) && avg=$(_ms_to_us "${p[1]}")
            ((${#p[@]} >= 4)) && jit=$(_ms_to_us "${p[3]}")
            ;;
        esac
      done < <(ping -n -q -c 3 -W 2 -i 0.3 "$host" 2>/dev/null)
    fi
    # No ping, or ICMP filtered: time a TCP handshake with bash's own /dev/tcp.
    # Not the same measurement as ICMP, but it answers "can I reach it, and how
    # long does it take", which is the question that matters.
    if ((avg < 0)); then
      local t0 t1
      now_ms_v; t0=$NOW_MS
      if exec 9<>"/dev/tcp/$host/443" 2>/dev/null; then
        now_ms_v; t1=$NOW_MS
        exec 9<&- 2>/dev/null
        avg=$(((t1 - t0) * 1000))
        loss=0
        label="$label*"
      fi
    fi
    out+="$label	$avg	$loss	$jit"$'\n'
  done

  if cfg_on dns_probe; then
    local d0 d1 dus=-1
    now_ms_v; d0=$NOW_MS
    if getent hosts "${CFG[dns_probe_host]}" >/dev/null 2>&1; then
      now_ms_v; d1=$NOW_MS
      dus=$(((d1 - d0) * 1000))
    fi
    out+="dns	$dus	0	-1"$'\n'
  fi
  printf '%s' "$out"
  return 0
}

net_latency_spawn() {
  local sd file
  state_dir_v; sd=$STATE_DIR
  file="$sd/latency"
  _LAT_FILE=$file
  [[ -d $sd ]] || mkdir -p "$sd" 2>/dev/null || return 1
  # Already running? Leave it alone; a stuck probe must not pile up children.
  if ((_LAT_PID > 0)) && kill -0 "$_LAT_PID" 2>/dev/null; then return 0; fi
  { net_probe_once >"$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"; } &
  _LAT_PID=$!
  return 0
}

net_latency_read() {
  local sd file label us loss jit
  state_dir_v; sd=$STATE_DIR
  file="$sd/latency"
  [[ -r $file ]] || { LAT_AGE=-1; return 1; }
  LAT_MS=() LAT_LOSS=() LAT_JIT=()
  LAT_AGE=-1
  while IFS=$'\t' read -r label us loss jit; do
    [[ -n $label ]] || continue
    if [[ $label == '#ts' ]]; then
      [[ $us =~ ^[0-9]+$ ]] && LAT_AGE=$((${EPOCHSECONDS:-0} - us))
      continue
    fi
    LAT_MS[$label]=$us LAT_LOSS[$label]=$loss LAT_JIT[$label]=$jit
  done <"$file"
  return 0
}

# ---------------------------------------------------------------------------
# public identity (hourly, detached)
# ---------------------------------------------------------------------------
PUB_IP='' PUB_INFO=''
net_pubip_spawn() {
  local sd file
  state_dir_v; sd=$STATE_DIR
  file="$sd/pubip"
  [[ -d $sd ]] || mkdir -p "$sd" 2>/dev/null || return 1
  have curl || return 1
  {
    local ip=''
    # Two independent sources: a single provider having a bad day should not
    # make the panel claim the node lost its address.
    ip=$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null) \
      || ip=$(curl -fsS --max-time 6 https://ifconfig.me/ip 2>/dev/null) || ip=''
    ip=${ip//[^0-9a-fA-F.:]/}
    [[ -n $ip ]] && printf '%s\n' "$ip" >"$file.tmp" && mv -f "$file.tmp" "$file"
  } &
  return 0
}

net_pubip_read() {
  local sd file
  state_dir_v; sd=$STATE_DIR
  file="$sd/pubip"
  [[ -r $file ]] && readval PUB_IP "$file"
  return 0
}

# Local address of the WAN interface, without forking `ip` every tick: resolved
# once on demand and cached for the process lifetime (it rarely changes, and a
# change comes with a route change we'd notice anyway).
declare -A _ADDR_CACHE=()
net_addr() {
  local ifn=$1
  if [[ -v _ADDR_CACHE[$ifn] ]]; then printf '%s' "${_ADDR_CACHE[$ifn]}"; return 0; fi
  local a=''
  if have ip; then
    a=$(ip -4 -o addr show dev "$ifn" 2>/dev/null) || a=''
    if [[ -n $a ]]; then
      a=${a#*inet }
      a=${a%% *}
    fi
  fi
  _ADDR_CACHE[$ifn]=$a
  printf '%s' "$a"
  return 0
}
net_addr_flush() { _ADDR_CACHE=(); }


# ---------------------------------------------------------------------------
# connection identity
# ---------------------------------------------------------------------------
# What network is this box actually on: SSID if wireless, NetworkManager
# connection name if there is one, local address and CIDR, gateway, DNS.
#
# All of it changes rarely, and some of it needs a subprocess, so this runs on a
# 30s cadence and caches. Nothing here is on the per-tick path.
declare -A IF_IP=() IF_TYPE=() IF_SSID=() IF_MAC=() IF_SPEED=() IF_STATE=()
NET_SSID='' NET_CONN='' NET_LOCAL_IP='' NET_GW='' NET_DNS='' NET_DOMAIN=''
NET_IDENT_LAST=0

# Wireless interfaces have a `wireless` directory (or a phy80211 link) under
# /sys/class/net/<if>. That test is reliable and needs no tooling, unlike
# guessing from a name like wlan0/wlp3s0/ath0.
net_iface_type() {
  # Two statements: bash expands every word of a `local` before any of its
  # assignments take effect, so referencing $ifn in the same `local` reads it as
  # unset and aborts the function under set -u.
  local ifn=$1
  local base="$HYN_SYS/class/net/$ifn"
  if [[ -d $base/wireless || -L $base/phy80211 ]]; then printf wifi; return 0; fi
  [[ -r $base/tun_flags ]] && { printf tunnel; return 0; }
  [[ -d $base/bridge ]] && { printf bridge; return 0; }
  [[ -d $base/bonding ]] && { printf bond; return 0; }
  [[ $ifn == lo ]] && { printf loopback; return 0; }
  # A `device` symlink means a real bus device behind the interface. `speed` is
  # a second signal: some drivers expose it where the device link is not what
  # you would expect, and no virtual interface (veth, dummy, bridge) has it.
  [[ -L $base/device || -r $base/speed ]] && { printf ethernet; return 0; }
  printf virtual
}

# SSID. iwgetid is the cheapest; iw and nmcli are the fallbacks, because Ubuntu
# Server images vary in which of the three is present.
_net_ssid() {
  local ifn=$1 s=''
  if have iwgetid; then
    s=$(iwgetid -r "$ifn" 2>/dev/null) && [[ -n $s ]] && { printf '%s' "$s"; return 0; }
  fi
  if have iw; then
    local line
    while IFS= read -r line; do
      case $line in
        *SSID:*) s=${line#*SSID: }; break ;;
      esac
    done < <(iw dev "$ifn" link 2>/dev/null)
    [[ -n $s ]] && { printf '%s' "$s"; return 0; }
  fi
  if have nmcli; then
    local act ssid dev
    while IFS=: read -r act ssid dev; do
      [[ $act == yes && $dev == "$ifn" ]] && { printf '%s' "$ssid"; return 0; }
    done < <(nmcli -t -f active,ssid,device dev wifi 2>/dev/null)
  fi
  return 1
}

# NetworkManager / netplan connection name, when there is one. Purely
# informational, but it is what an operator recognises: "office-lan", not "enp3s0".
_net_conn_name() {
  have nmcli || return 1
  local name dev
  while IFS=: read -r name dev; do
    [[ $dev == "$1" ]] && [[ -n $name ]] && { printf '%s' "$name"; return 0; }
  done < <(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null)
  return 1
}

# Resolvers. systemd-resolved puts a stub in resolv.conf, so ask resolvectl
# first for the real upstreams and fall back to the file.
_net_dns() {
  local out='' line ip
  if have resolvectl; then
    while IFS= read -r line; do
      case $line in
        *'DNS Servers:'*)
          line=${line#*: }
          out=${line//[[:space:]]/,}
          break ;;
      esac
    done < <(resolvectl status 2>/dev/null)
    [[ -n $out ]] && { printf '%s' "${out%,}"; return 0; }
  fi
  while read -r line ip _; do
    [[ $line == nameserver ]] || continue
    out+="${out:+,}$ip"
  done <"/etc/resolv.conf" 2>/dev/null
  printf '%s' "$out"
  return 0
}

# ip -o addr in one call for every interface, rather than one call per interface.
_net_addrs_all() {
  have ip || return 1
  local idx dev rest cidr
  while read -r idx dev _ cidr rest; do
    [[ -n $dev ]] || continue
    dev=${dev%:}
    [[ -n ${IF_IP[$dev]:-} ]] && continue
    IF_IP[$dev]=$cidr
  done < <(ip -4 -o addr show 2>/dev/null | awk '{print $1, $2, $3, $4, $5}')
  return 0
}

net_identity() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  cfg_on net_identity || return 0
  ((force == 0 && NET_IDENT_LAST > 0 && now - NET_IDENT_LAST < 30)) && return 0
  NET_IDENT_LAST=$now

  IF_IP=() IF_TYPE=() IF_SSID=() IF_MAC=() IF_SPEED=() IF_STATE=()
  _net_addrs_all
  local ifn
  for ifn in "${NET_IFACES[@]}"; do
    IF_TYPE[$ifn]=$(net_iface_type "$ifn")
    net_link "$ifn"
    IF_MAC[$ifn]=$LINK_MAC
    IF_SPEED[$ifn]=$LINK_SPEED
    IF_STATE[$ifn]=$LINK_STATE
    if [[ ${IF_TYPE[$ifn]} == wifi ]]; then
      IF_SSID[$ifn]=$(_net_ssid "$ifn" || printf '')
    fi
  done

  local wan=${NET_WAN:-}
  NET_LOCAL_IP=${IF_IP[$wan]:-}
  NET_SSID=${IF_SSID[$wan]:-}
  NET_CONN=$(_net_conn_name "$wan" || printf '')
  NET_GW=$(net_gateway_ip || printf '')
  NET_DNS=$(_net_dns)
  return 0
}

# A one-line description of what we are connected to, for the panel title.
NET_IDENT_LABEL=''
net_ident_label() {
  local wan=${NET_WAN:-}
  NET_IDENT_LABEL=''
  [[ -n $wan ]] || return 1
  if [[ -n $NET_SSID ]]; then
    NET_IDENT_LABEL="wifi:$NET_SSID"
  elif [[ -n $NET_CONN && $NET_CONN != "$wan" ]]; then
    NET_IDENT_LABEL="$NET_CONN"
  else
    NET_IDENT_LABEL="${IF_TYPE[$wan]:-link}"
  fi
  return 0
}
