#!/usr/bin/env bash
# hyn-view :: Highway (hw-os) node tracker
#
# STRICTLY READ-ONLY. This file must never change the node's state. That means:
#
#   * no systemctl start/stop/restart/reload/enable/disable -- only `show`,
#     `list-units` and `is-*`, which do not touch the unit;
#   * no writes anywhere under /etc/highway, /var/lib/highway or /opt/highway;
#   * no `tc`/`nft`/`iptables` subcommands other than `show`/`list`;
#   * the `highway` binary is NOT executed. Version discovery reads files, unit
#     properties and the journal instead. Running a node's own binary to ask its
#     version means starting a second instance of an activation TUI next to a
#     live validator, and no monitor is worth that risk. An operator who wants
#     it anyway can set highway_version_probe=exec.
#
# If you extend this file, keep that list true.

HW_BIN='/usr/local/bin/highway'
HW_PRESENT=0 HW_SIZE=0 HW_MTIME=0 HW_MTIME_H=''
HW_VERSION='' HW_VERSION_SRC='' HW_LATEST='' HW_UPDATE=0
HW_PID=0 HW_RSS=0 HW_CPU=0 HW_THR=0 HW_FDS=0 HW_UPTIME=0
HW_UNIT_COUNT=0 HW_ACTIVE=0 HW_FAILED=0
HW_JOURNAL_WARN=0 HW_JOURNAL_ERR=0
HW_NEBULA='' HW_QDISC='' HW_QDISC_DROPS=''
declare -a HW_UNITS=() HW_JOURNAL_TAIL=()
declare -A HW_STATE=() HW_SUB=() HW_RESTARTS=() HW_MEM=() HW_SINCE=()

HW_LATEST_URL='https://install.hiwaynetwork.io/hw-os/latest.txt'

# ---------------------------------------------------------------------------
# binary
# ---------------------------------------------------------------------------
hw_binary() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  ((force == 0 && HW_BIN_LAST > 0 && now - HW_BIN_LAST < 30)) && return 0
  HW_BIN_LAST=$now
  HW_PRESENT=0
  [[ -f $HW_BIN ]] || return 1
  HW_PRESENT=1
  # One `stat` per 30s. There is no builtin stat, and %s/%Y on a single file at
  # this cadence is far cheaper than the alternative of not knowing when the
  # operator last upgraded.
  local s prev=$HW_MTIME
  if have stat; then
    s=$(stat -c '%s %Y' "$HW_BIN" 2>/dev/null) || s=''
    if [[ -n $s ]]; then
      HW_SIZE=${s%% *}
      HW_MTIME=${s##* }
    fi
  fi
  if [[ $HW_MTIME =~ ^[0-9]+$ ]] && ((HW_MTIME > 0)); then
    HW_MTIME_H=$(fmt_dur $((now - HW_MTIME)))
  fi
  # A changed binary means a new version: drop the cached answer so discovery
  # re-runs instead of reporting the version the operator just replaced.
  if [[ $prev != "$HW_MTIME" ]]; then
    HW_VERSION='' HW_VERSION_SRC='' _HW_VER_TRIED=0
  fi
  return 0
}
HW_BIN_LAST=0

# Version without executing anything. Ordered cheapest-and-safest first. The
# result -- including "could not determine" -- is cached, because the journal
# scan below is expensive and re-running it every tick would make this monitor
# the heaviest thing on the box.
_HW_VER_TRIED=0
hw_version() {
  [[ -n $HW_VERSION ]] && return 0
  ((_HW_VER_TRIED)) && return 1
  _HW_VER_TRIED=1
  local f v line

  # On-disk version files, cheapest and safest. Ordered most specific first: the
  # relayer OS keeps the running agent's version at
  # /opt/hway-agent/current/VERSION, and reading it is the difference between
  # reporting v0.1.95 (correct) and scraping "v0.3.1" out of an unrelated unit's
  # metadata further down this function.
  for f in /opt/hway-agent/current/VERSION /opt/hway-agent/VERSION \
           /var/lib/highway/version /var/lib/highway/VERSION /etc/highway/version \
           /opt/highway/VERSION /var/lib/hw-os/version /etc/hway/version; do
    [[ -r $f ]] || continue
    readval v "$f" || continue
    v=${v//[[:space:]]/}
    if [[ $v =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      HW_VERSION=$v HW_VERSION_SRC=file
      return 0
    fi
  done

  # Unit metadata: an ExecStart or Environment line often carries the version.
  if ((HW_UNIT_COUNT > 0)) && have systemctl; then
    local u
    for u in "${HW_UNITS[@]}"; do
      while IFS= read -r line; do
        [[ $line == *[0-9].[0-9]* ]] || continue
        if [[ $line =~ (v?[0-9]+\.[0-9]+\.[0-9]+) ]]; then
          HW_VERSION=${BASH_REMATCH[1]} HW_VERSION_SRC=unit
          return 0
        fi
      done < <(systemctl show -p ExecStart -p Environment "$u" 2>/dev/null)
    done
  fi

  # The node's own startup banner, read out of the journal. Read-only and it
  # reflects what is actually running rather than what is on disk.
  if ((HW_UNIT_COUNT > 0)) && have journalctl; then
    local u
    for u in "${HW_UNITS[@]}"; do
      while IFS= read -r line; do
        if [[ $line =~ (v[0-9]+\.[0-9]+\.[0-9]+) ]]; then
          HW_VERSION=${BASH_REMATCH[1]} HW_VERSION_SRC=journal
          return 0
        fi
      done < <(journalctl -u "$u" -n 400 --no-pager -o cat --since '-30 days' 2>/dev/null)
    done
  fi

  # Opt-in only. See the header comment for why this is not the default.
  if [[ ${CFG[highway_version_probe]:-off} == exec ]] && ((HW_PRESENT)); then
    local out
    out=$(timeout 5 "$HW_BIN" --version </dev/null 2>/dev/null | head -1) || out=''
    if [[ $out =~ (v?[0-9]+\.[0-9]+\.[0-9]+) ]]; then
      HW_VERSION=${BASH_REMATCH[1]} HW_VERSION_SRC=exec
      return 0
    fi
  fi
  return 1
}

# Latest published version, cached on disk for 6h and fetched detached so a slow
# or blocked network never delays a frame.
#
# _HW_FETCH_AT rate-limits the *attempt*, not just the success. Without it, a
# host that cannot reach the endpoint (no egress, DNS blocked, endpoint down)
# never writes the cache file, so every single tick spawned another curl —
# unbounded process growth on exactly the machines least able to afford it.
_HW_FETCH_AT=0
_HW_FETCH_PID=0
hw_latest_check() {
  cfg_on highway_update_check || return 0
  have curl || return 0
  local file age now
  state_dir_v
  file="$STATE_DIR/hw-latest"
  now=${EPOCHSECONDS:-0}
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  if [[ -r $file ]]; then
    local ts v
    { read -r ts; read -r v; } <"$file" 2>/dev/null
    [[ $ts =~ ^[0-9]+$ ]] || ts=0
    HW_LATEST=$v
    age=$((now - ts))
    ((age < 21600)) && { hw_update_flag; return 0; }
  fi
  # One attempt per 6h, and never two at once.
  if ((now - _HW_FETCH_AT < 21600)); then hw_update_flag; return 0; fi
  if ((_HW_FETCH_PID > 0)) && kill -0 "$_HW_FETCH_PID" 2>/dev/null; then hw_update_flag; return 0; fi
  _HW_FETCH_AT=$now
  {
    local out
    out=$(curl -fsSL --max-time 10 --proto '=https' "$HW_LATEST_URL" 2>/dev/null) || out=''
    out=${out//[[:space:]]/}
    if [[ $out =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s\n%s\n' "${EPOCHSECONDS:-0}" "$out" >"$file.tmp" && mv -f "$file.tmp" "$file"
    fi
  } &
  _HW_FETCH_PID=$!
  hw_update_flag
  return 0
}

hw_update_flag() {
  HW_UPDATE=0
  [[ -n $HW_LATEST && -n $HW_VERSION ]] || return 0
  local a=${HW_VERSION#v} b=${HW_LATEST#v}
  [[ $a == "$b" ]] && return 0
  # Numeric compare per component, so v0.1.9 is correctly older than v0.1.75.
  local -a pa=() pb=()
  local oIFS=$IFS
  IFS=.; pa=($a); pb=($b); IFS=$oIFS
  local i x y
  for i in 0 1 2; do
    x=${pa[i]:-0} y=${pb[i]:-0}
    [[ $x =~ ^[0-9]+$ ]] || x=0
    [[ $y =~ ^[0-9]+$ ]] || y=0
    ((y > x)) && { HW_UPDATE=1; return 0; }
    ((y < x)) && return 0
  done
  return 0
}

# ---------------------------------------------------------------------------
# systemd units (read-only properties)
# ---------------------------------------------------------------------------
HW_UNITS_LAST=0
hw_units() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  ((force == 0 && HW_UNITS_LAST > 0 && now - HW_UNITS_LAST < 10)) && return 0
  HW_UNITS_LAST=$now
  have systemctl || return 1
  local -a pats=()
  local p
  local oIFS=$IFS
  IFS=,
  for p in ${CFG[highway_units]}; do
    [[ -n $p ]] && pats+=("$p")
  done
  IFS=$oIFS
  ((${#pats[@]} == 0)) && return 0

  HW_UNITS=() HW_STATE=() HW_SUB=() HW_RESTARTS=() HW_MEM=() HW_SINCE=()
  HW_ACTIVE=0 HW_FAILED=0
  local unit rest
  while read -r unit rest; do
    case $unit in
      *.service | *.socket | *.timer | *.mount | *.target) ;;
      *) continue ;;
    esac
    HW_UNITS+=("$unit")
  done < <(systemctl list-units --all --no-legend --plain --no-pager "${pats[@]}" 2>/dev/null)
  HW_UNIT_COUNT=${#HW_UNITS[@]}

  local u line k v
  for u in "${HW_UNITS[@]}"; do
    while IFS= read -r line; do
      k=${line%%=*} v=${line#*=}
      case $k in
        ActiveState) HW_STATE[$u]=$v ;;
        SubState) HW_SUB[$u]=$v ;;
        NRestarts) HW_RESTARTS[$u]=$v ;;
        MemoryCurrent) HW_MEM[$u]=$v ;;
        ExecMainStartTimestampMonotonic) HW_SINCE[$u]=$v ;;
      esac
    done < <(systemctl show -p ActiveState -p SubState -p NRestarts -p MemoryCurrent \
      -p ExecMainStartTimestampMonotonic "$u" 2>/dev/null)
    case ${HW_STATE[$u]:-} in
      active) ((HW_ACTIVE++)) ;;
      failed) ((HW_FAILED++)) ;;
    esac
  done
  # Which of those units is the node itself is a ranked decision, not "whichever
  # one systemd happened to list first". That heuristic is what reported a
  # 3.8 MiB shell as the node process on a real relayer: `systemctl list-units`
  # is alphabetical, so hway-monitor.service was seen before hway-relayer.service
  # and its MainPID won. See hw_main_pid.
  local prevpid=$HW_PID
  HW_PID=0
  hw_main_pid || HW_PID=$prevpid
  # A different pid means the CPU baseline that went with the old one is
  # meaningless -- after a restart it would read as a huge burst.
  ((HW_PID != prevpid)) && _HW_PREV=()
  return 0
}

# ---------------------------------------------------------------------------
# process resources
# ---------------------------------------------------------------------------
# Falls back to scanning comm when systemd did not give us a MainPID (the node
# may be started by hand, or by a unit outside our patterns).
declare -A _HW_PREV=()
_HW_SCAN_LAST=0
# The node's own service knows its main pid. Tried before any /proc walk.
#
# Read-only: `systemctl show` cannot change a unit's state. The unit names are
# ranked so the relayer wins over its sidecars -- on a real relay node
# hway-monitor, hway-otel-agent and nebula-guard are all active too, and
# reporting a 10 MiB sidecar as "the node process" is worse than reporting
# nothing.
HW_NODE_UNIT=''
hw_main_pid() {
  HW_NODE_UNIT=''
  ((HW_UNIT_COUNT > 0)) || return 1
  have systemctl || return 1
  local rank u pid
  for rank in 'hway-relayer.service' 'highway.service' 'hw-os.service' \
              'hway-node.service' 'hway-monitor.service'; do
    for u in "${HW_UNITS[@]}"; do
      [[ $u == "$rank" ]] || continue
      [[ ${HW_STATE[$u]:-} == active ]] || continue
      pid=$(systemctl show -p MainPID --value "$u" 2>/dev/null) || pid=''
      [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1)) || continue
      [[ -r $HYN_PROC/$pid/stat ]] || continue
      HW_PID=$pid
      HW_NODE_UNIT=$u
      return 0
    done
  done
  return 1
}

hw_process() {
  local ms=$1 d pid comm line rest tail total dt now=${EPOCHSECONDS:-0}
  local -a f=()
  if ((HW_PID > 0)) && [[ ! -r $HYN_PROC/$HW_PID/stat ]]; then
    HW_PID=0
    _HW_PREV=()
  fi
  if ((HW_PID == 0)); then
    # Ask systemd first. The unit that runs the node knows its own main pid
    # exactly, which is both cheaper than walking /proc and correct in a case a
    # comm scan gets wrong: /proc/<pid>/comm is capped at 15 characters by the
    # kernel, so hway-relayer-supervise appears as "hway-relayer-su", and a scan
    # matching the old fixed names picked up nebula-guard instead -- reporting
    # 11 MiB of RSS for a process actually holding 1.5 GiB.
    hw_main_pid
    if ((HW_PID == 0)); then
      # Scanning every /proc entry is the expensive path, so rate-limit it. A node
      # that is genuinely down should not cost a full process walk every second.
      ((_HW_SCAN_LAST > 0 && now - _HW_SCAN_LAST < 10)) && { HW_RSS=0 HW_CPU=0 HW_THR=0 HW_FDS=0 HW_UPTIME=0; return 1; }
      _HW_SCAN_LAST=$now
      for d in "$HYN_PROC"/[0-9]*; do
        readval comm "$d/comm" || continue
        # Prefix matches, for the 15-character cap above.
        case $comm in
          highway* | hw-os* | hway-relayer* | hway-node*) ;;
          *) continue ;;
        esac
        HW_PID=${d##*/}
        break
      done
    fi
  fi
  ((HW_PID == 0)) && { HW_RSS=0 HW_CPU=0 HW_THR=0 HW_FDS=0 HW_UPTIME=0; return 1; }

  # 2>/dev/null first: see the note in proc_sample. The node restarting between
  # the pid lookup and this read is exactly the case worth handling quietly.
  read -r line 2>/dev/null <"$HYN_PROC/$HW_PID/stat" || { HW_PID=0; return 1; }
  # Escaped parens: extglob makes an unescaped "*(" an extglob group.
  rest=${line#*\(}
  tail=${rest##*\)}
  f=($tail)
  ((${#f[@]} < 22)) && return 1
  HW_THR=${f[17]}
  HW_RSS=$((${f[21]} * PAGE_SIZE))
  total=$((${f[11]} + ${f[12]}))
  dt=$((total - ${_HW_PREV[cpu]:-total}))
  _HW_PREV[cpu]=$total
  ((dt < 0)) && dt=0
  # Tenths of a percent of one core, matching proc_sample's units.
  if ((ms > 0)); then HW_CPU=$((dt * 1000000 / (CLK_TCK * ms))); else HW_CPU=0; fi

  # starttime is in clock ticks since boot; convert against current uptime.
  local start=${f[19]}
  if ((UPTIME_S > 0 && CLK_TCK > 0)); then
    HW_UPTIME=$((UPTIME_S - start / CLK_TCK))
    ((HW_UPTIME < 0)) && HW_UPTIME=0
  fi

  # fd count by glob (no fork). Requires root or same ownership; an unreadable
  # fd dir reports 0, which the panel renders as "-" rather than a false zero.
  HW_FDS=0
  local fd
  if [[ -r $HYN_PROC/$HW_PID/fd ]]; then
    for fd in "$HYN_PROC/$HW_PID/fd"/*; do
      [[ -e $fd || -L $fd ]] && ((HW_FDS++))
    done
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Nebula tunnel
# ---------------------------------------------------------------------------
# Highway puts validators on a Nebula mesh, so the tunnel being up and moving
# packets is as important as the WAN link. tun_flags only exists on tun/tap
# devices, which is a more reliable test than guessing at names.
hw_nebula() {
  local ifn
  HW_NEBULA=''
  for ifn in "${NET_IFACES[@]}"; do
    case $ifn in
      nebula* | hw* | highway*) HW_NEBULA=$ifn; return 0 ;;
    esac
  done
  for ifn in "${NET_IFACES[@]}"; do
    [[ -r $HYN_SYS/class/net/$ifn/tun_flags ]] || continue
    case $ifn in
      docker* | veth* | br-*) continue ;;
    esac
    HW_NEBULA=$ifn
    return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# traffic control (highway drives tc on the WAN interface)
# ---------------------------------------------------------------------------
HW_TC_LAST=0
hw_qdisc() {
  local now=${EPOCHSECONDS:-0}
  ((HW_TC_LAST > 0 && now - HW_TC_LAST < 15)) && return 0
  HW_TC_LAST=$now
  HW_QDISC='' HW_QDISC_DROPS=''
  have tc || return 1
  [[ -n $NET_WAN ]] || return 1
  local line first=1
  while IFS= read -r line; do
    if ((first)); then
      # "qdisc fq_codel 8003: root refcnt 2 ..." -> the kind is the 2nd word.
      local -a f=($line)
      HW_QDISC=${f[1]:-}
      first=0
    fi
    if [[ $line == *'dropped '* ]]; then
      local d=${line#*dropped }
      HW_QDISC_DROPS=${d%%,*}
    fi
  done < <(tc -s qdisc show dev "$NET_WAN" 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# journal health
# ---------------------------------------------------------------------------
HW_JOURNAL_LAST=0
hw_journal() {
  local now=${EPOCHSECONDS:-0}
  ((HW_JOURNAL_LAST > 0 && now - HW_JOURNAL_LAST < 30)) && return 0
  HW_JOURNAL_LAST=$now
  have journalctl || return 1
  ((HW_UNIT_COUNT > 0)) || return 1
  HW_JOURNAL_WARN=0 HW_JOURNAL_ERR=0 HW_JOURNAL_TAIL=()
  local -a args=()
  local u
  for u in "${HW_UNITS[@]}"; do args+=(-u "$u"); done
  local line prio
  # PRIORITY comes back as a number: <=3 is err/crit/alert/emerg, 4 is warning.
  while IFS= read -r line; do
    case $line in
      PRIORITY=*)
        prio=${line#*=}
        [[ $prio =~ ^[0-9]+$ ]] || continue
        if ((prio <= 3)); then ((HW_JOURNAL_ERR++))
        elif ((prio == 4)); then ((HW_JOURNAL_WARN++)); fi
        ;;
      MESSAGE=*)
        # Keep the NEWEST three: journalctl emits oldest-first, so append and
        # trim rather than taking the first three (which would be an hour old).
        HW_JOURNAL_TAIL+=("${line#*=}")
        ((${#HW_JOURNAL_TAIL[@]} > 3)) && HW_JOURNAL_TAIL=("${HW_JOURNAL_TAIL[@]: -3}")
        ;;
    esac
  done < <(journalctl "${args[@]}" --since '-1h' -p warning -o export \
    --no-pager -n 200 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# firewall footprint (counts only; never enumerates or changes rules)
# ---------------------------------------------------------------------------
HW_NFT_TABLES='' HW_FW_LAST=0
hw_firewall() {
  local now=${EPOCHSECONDS:-0}
  ((HW_FW_LAST > 0 && now - HW_FW_LAST < 60)) && return 0
  HW_FW_LAST=$now
  is_root || return 1
  HW_NFT_TABLES=''
  if have nft; then
    local n=0 line
    while IFS= read -r line; do [[ $line == table* ]] && ((n++)); done < <(nft list tables 2>/dev/null)
    HW_NFT_TABLES=$n
  fi
  return 0
}

# ---------------------------------------------------------------------------
# rollup
# ---------------------------------------------------------------------------
# One health verdict for the header, so an operator glancing at the terminal
# from across the room gets the answer without reading numbers.
HW_HEALTH='unknown' HW_HEALTH_WHY=''
hw_health() {
  HW_HEALTH='unknown' HW_HEALTH_WHY=''
  if ((HW_PRESENT == 0)); then
    HW_HEALTH='absent' HW_HEALTH_WHY='highway not installed'
    return 0
  fi
  if ((HW_FAILED > 0)); then
    HW_HEALTH='crit' HW_HEALTH_WHY="$HW_FAILED unit(s) failed"
    return 0
  fi
  if ((HW_UNIT_COUNT == 0)); then
    if ((HW_PID > 0)); then
      HW_HEALTH='warn' HW_HEALTH_WHY='running without a systemd unit'
    else
      HW_HEALTH='warn' HW_HEALTH_WHY='installed, not running'
    fi
    return 0
  fi
  if ((HW_ACTIVE == 0)); then
    HW_HEALTH='crit' HW_HEALTH_WHY='no active unit'
    return 0
  fi
  local u r
  for u in "${HW_UNITS[@]}"; do
    r=${HW_RESTARTS[$u]:-0}
    [[ $r =~ ^[0-9]+$ ]] || continue
    ((r >= 3)) && { HW_HEALTH='warn' HW_HEALTH_WHY="$u restarted ${r}x"; return 0; }
  done
  if ((HW_JOURNAL_ERR > 0)); then
    HW_HEALTH='warn' HW_HEALTH_WHY="$HW_JOURNAL_ERR error(s) in last hour"
    return 0
  fi
  HW_HEALTH='ok' HW_HEALTH_WHY="$HW_ACTIVE unit(s) active"
  return 0
}

hw_sample() {
  local ms=$1
  cfg_on highway_track || return 0
  hw_binary
  hw_units
  hw_process "$ms"
  hw_nebula
  hw_qdisc
  hw_journal
  hw_firewall
  hw_version
  hw_latest_check
  hw_health
  return 0
}
