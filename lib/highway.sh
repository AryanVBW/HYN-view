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

# Where Highway publishes the current release pointer. This is the host its own
# installer (`curl -fsSL get.highway.space | sudo -H bash`) resolves against, and it
# names the release as `mainnet-vX.Y.Z`. The previous host, install.hiwaynetwork.io,
# now answers 503 and published a different scheme (`v0.1.x`); it is kept only as a
# fallback so a box that still reaches it keeps working. The pointer is read for
# display only: nothing here downloads or runs what it names, so the signature
# check the installer performs on it is not needed.
HW_LATEST_URL='https://get.highway.space/hw-os/latest.txt'
HW_LATEST_URL_LEGACY='https://install.hiwaynetwork.io/hw-os/latest.txt'

# `mainnet-v1.0.10` and `v1.0.10` both normalise to `v1.0.10`, which is the shape
# every other version in this file uses. Anything else yields '' so a changed or
# hostile response is dropped instead of cached.
HW_LATEST_NORM=''
hw_latest_normalize_v() {
  local s=${1//[[:space:]]/}
  s=${s#mainnet-}
  if [[ $s =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then HW_LATEST_NORM=$s; else HW_LATEST_NORM=''; fi
}

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
  # /opt/hway-agent/current/VERSION (older images) or
  # /etc/hway-relayer/hw-os-version (current ones, written by the installer, e.g.
  # `v1.0.8`; the relayer binary's own version is a separate track in
  # binary-swap-state.json and is not what the release pointer describes), and
  # reading it is the difference between
  # reporting v0.1.95 (correct) and scraping "v0.3.1" out of an unrelated unit's
  # metadata further down this function.
  for f in /opt/hway-agent/current/VERSION /opt/hway-agent/VERSION \
           /etc/hway-relayer/hw-os-version /var/lib/highway/version /var/lib/highway/VERSION /etc/highway/version \
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
    local out url
    for url in "$HW_LATEST_URL" "${HW_LATEST_URL_LEGACY:-}"; do
      [[ -n $url ]] || continue
      out=$(curl -fsSL --max-time 10 --proto '=https' "$url" 2>/dev/null) || out=''
      hw_latest_normalize_v "$out"
      if [[ -n $HW_LATEST_NORM ]]; then
        printf '%s\n%s\n' "${EPOCHSECONDS:-0}" "$HW_LATEST_NORM" >"$file.tmp" && mv -f "$file.tmp" "$file"
        break
      fi
    done
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

# ---------------------------------------------------------------------------
# operations: what Highway's own installer menu would tell the operator to do
# ---------------------------------------------------------------------------
# `sudo highway` opens a menu whose options map onto the state of the box:
#
#   UPDATE & REPAIR   refresh the agent stack and timers; needs a valid overlay
#                     certificate and refuses without one
#   REPAIR CONNECT    re-register after the certificate lapsed, was revoked or
#                     does not match; needs a browser sign-in
#   REACTIVATE        like repair but keeps the registration (beyond grace)
#   CREATE BACKUP     seal the relayer keys with the manager mnemonic into
#                     /root/highway-recovery-<name>.hrb and upload that to the
#                     account
#   START RELAYER     undo STOP RELAYER (which also writes a held-down marker)
#
# The menu only appears when someone is at the terminal. Everything it decides
# from is already on disk, and this reads it without touching it: it never opens
# a key, never reads the backup past its four-byte header, and never runs or
# restarts anything. The answer goes to the dashboard as "choose X", so the
# person looking at the portal knows which option to pick before they SSH in.
: "${HW_ETC:=/etc/hway-relayer}"
: "${HW_NEBULA_DIR:=/etc/nebula-hway}"
: "${HW_BK_DIR:=/root}"
: "${HW_UNIT_FILE:=/etc/systemd/system/hway-relayer.service}"
HW_OPS_STATE='absent' HW_OPS_ACTION='none' HW_OPS_WHY='' HW_OPS_GATE=''
HW_OVERLAY_LEFT='' HW_CERT_DAYS='' HW_KILLSWITCH=0 HW_HELD=0
HW_NETWORK='' HW_OS_VERSION='' HW_RELAYER_VERSION='' HW_CONFIG_VERSION=''
HW_BK_PRESENT=0 HW_BK_AGE='' HW_BK_SIZE='' HW_BK_STALE=0 HW_BK_PERMS_OK=1 HW_BK_MAGIC_OK=1
HW_MAINT=0 HW_MAINT_QUIET=0 HW_MAINT_WHY=''
HW_OPS_LAST=0 HW_BK_LAST=0 HW_BK_MTIME=0

# _hw_json <file> <key>: a flat JSON scalar into REPLY. These state files are
# written by Highway's own scripts as one flat object, so a pattern is enough and
# there is no jq to depend on. Bounded read; an absent key returns 1.
_hw_json() {
  REPLY=''
  [[ -r $1 ]] || return 1
  local c=''
  IFS= read -r -d '' -N 65536 c <"$1" 2>/dev/null
  if [[ $c =~ \"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    REPLY=${BASH_REMATCH[1]}
  elif [[ $c =~ \"$2\"[[:space:]]*:[[:space:]]*(-?[0-9]+|true|false) ]]; then
    REPLY=${BASH_REMATCH[1]}
  else
    return 1
  fi
  return 0
}

# _hw_line <file>: first line of a one-value file, capped, into REPLY.
_hw_line() {
  REPLY=''
  [[ -r $1 ]] || return 1
  IFS= read -r -N 64 REPLY <"$1" 2>/dev/null
  REPLY=${REPLY%%$'\n'*}
  REPLY=${REPLY//[[:space:]]/}
  [[ -n $REPLY ]]
}

# Seconds until the overlay (Nebula) certificate lapses; negative once it has.
# This is an estimate, and deliberately so: the agent never runs the mesh tools
# (see the read-only guard in the self-check), so it does not decode the
# certificate. Highway issues it for 24 hours (its own docs and installer say so)
# and renews every 12, writing host.crt each time, which makes the file's
# modification time the issue time. A box that renews normally never has a
# certificate older than about 12.5 hours; the caller only treats it as lapsed
# an hour past the 24h mark, so a changed lifetime cannot raise a false alarm.
: "${HW_OVERLAY_LIFETIME:=86400}"
hw_overlay_left() {
  local now=${EPOCHSECONDS:-0} crt=$HW_NEBULA_DIR/host.crt m
  HW_OVERLAY_LEFT=''
  [[ -f $crt && ! -L $crt ]] || return 1
  have stat || return 1
  m=$(stat -c %Y "$crt" 2>/dev/null) || return 1
  [[ $m =~ ^[0-9]+$ ]] || return 1
  HW_OVERLAY_LEFT=$((m + HW_OVERLAY_LIFETIME - now))
  return 0
}

# The recovery backup, judged from the file alone. Highway keeps the account copy
# in the platform; only its mTLS client can ask whether that exists, so what is
# reported here is the local file, and the dashboard says so.
hw_backup() {
  local now=${EPOCHSECONDS:-0} f m sz mode name best='' bm=0 bsz='' bmode=''
  if ((HW_BK_LAST > 0 && now - HW_BK_LAST < 300)); then
    ((HW_BK_PRESENT)) && HW_BK_AGE=$((now - HW_BK_MTIME))
    return 0
  fi
  HW_BK_LAST=$now
  HW_BK_PRESENT=0 HW_BK_AGE='' HW_BK_SIZE='' HW_BK_STALE=0 HW_BK_PERMS_OK=1 HW_BK_MAGIC_OK=1
  have stat || return 0
  while IFS=' ' read -r m sz mode name; do
    [[ $m =~ ^[0-9]+$ && $name == */highway-recovery-*.hrb ]] || continue
    ((m > bm)) && { bm=$m; bsz=$sz; bmode=$mode; best=$name; }
  done < <(stat -c '%Y %s %a %n' "$HW_BK_DIR"/highway-recovery-*.hrb 2>/dev/null)
  [[ -n $best && ! -L $best ]] || return 0
  HW_BK_PRESENT=1
  HW_BK_MTIME=$bm
  HW_BK_AGE=$((now - bm))
  ((HW_BK_AGE < 0)) && HW_BK_AGE=0
  HW_BK_SIZE=$bsz
  # The bundle holds the relayer keys, so anything but owner-only is a leak.
  [[ $bmode == 600 || $bmode == 400 ]] || HW_BK_PERMS_OK=0
  local magic=''
  IFS= read -r -N 4 magic <"$best" 2>/dev/null
  [[ $magic == HWRB ]] || HW_BK_MAGIC_OK=0
  # Stale once a key file changed after the backup was sealed: a restore would
  # bring back the old identity. default.toml is left out on purpose, because
  # the config-refresh timer rewrites it routinely.
  local cfg k km
  for cfg in "$HW_ETC"/relayers/*/config; do
    [[ -d $cfg ]] || continue
    for k in p2p_key .env; do
      [[ -f $cfg/$k && ! -L $cfg/$k ]] || continue
      km=$(stat -c %Y "$cfg/$k" 2>/dev/null) || continue
      [[ $km =~ ^[0-9]+$ ]] && ((km > bm + 60)) && HW_BK_STALE=1
    done
    break
  done
  return 0
}

# ---------------------------------------------------------------------------
# Other backups on this machine, for the simple view's "backups" block.
#
#   system   dashboard/backup/hyn-sysbackup.sh writes <host>-<stamp>.tar.gz plus
#            last-success and last-offsite (epoch seconds) into HYN_BACKUP_DIR.
#   local    hyn's own history snapshots, one JSON file per snapshot.
#
# Both are read-only and cheap: one directory glob each, one stat for the pair of
# newest files, and a re-read at most once a minute however often the TUI asks.
# A directory the caller cannot read simply reads as "no backup here" -- the same
# answer as a box that has none -- so an unprivileged operator sees fewer rows,
# never an error.
# ---------------------------------------------------------------------------
: "${HYN_BACKUP_DIR:=/var/backups/hyn-system}"
BK_SYS_PRESENT=0 BK_SYS_TS=0 BK_SYS_SIZE='' BK_SYS_COUNT=0 BK_SYS_OFFSITE_TS=0
BK_LOC_PRESENT=0 BK_LOC_TS=0 BK_LOC_COUNT=0
BK_LAST=0 BK_LEVEL=ok

# bk_level_v <age-seconds> <warn-after> <crit-after> -> BK_LEVEL (ok|warn|crit).
# An age that is not a number is never reported as healthy: "we cannot tell" is
# the one answer a backup status must not round up to "fine".
bk_level_v() {
  local age=$1 warn=$2 crit=$3
  if [[ ! $age =~ ^[0-9]+$ ]]; then BK_LEVEL=warn
  elif ((age > crit)); then BK_LEVEL=crit
  elif ((age > warn)); then BK_LEVEL=warn
  else BK_LEVEL=ok; fi
  return 0
}
bk_level() { bk_level_v "$@"; printf '%s' "$BK_LEVEL"; }

# _bk_stamp <file>: an epoch-seconds stamp file into REPLY; fails on anything
# else. These files are written by a script, but a stamp is still just a file.
_bk_stamp() {
  REPLY=''
  [[ -f $1 && ! -L $1 ]] || return 1
  _hw_line "$1" || return 1
  [[ $REPLY =~ ^[0-9]{9,11}$ ]]
}

bk_local_sample() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  ((force == 0 && BK_LAST > 0 && now - BK_LAST < 60)) && return 0
  BK_LAST=$now
  BK_SYS_PRESENT=0 BK_SYS_TS=0 BK_SYS_SIZE='' BK_SYS_COUNT=0 BK_SYS_OFFSITE_TS=0
  BK_LOC_PRESENT=0 BK_LOC_TS=0 BK_LOC_COUNT=0

  local sysdir=$HYN_BACKUP_DIR snapdir arc='' snap='' stamp=0
  local -a arcs=() snaps=()
  state_dir_v
  snapdir=$STATE_DIR/local/snapshots

  # Names sort by their timestamp, so the last glob entry is the newest.
  if [[ -d $sysdir ]]; then
    arcs=("$sysdir"/*.tar.gz)
    [[ -f ${arcs[0]} ]] && arc=${arcs[${#arcs[@]} - 1]} || arcs=()
    _bk_stamp "$sysdir/last-success" && stamp=$REPLY
    _bk_stamp "$sysdir/last-offsite" && BK_SYS_OFFSITE_TS=$REPLY
  fi
  if [[ -d $snapdir ]]; then
    snaps=("$snapdir"/*.json)
    [[ -f ${snaps[0]} ]] && snap=${snaps[${#snaps[@]} - 1]} || snaps=()
  fi

  local -a targets=()
  [[ -n $arc ]] && targets+=("$arc")
  [[ -n $snap ]] && targets+=("$snap")
  local m sz name am=0 asz='' sm=0
  if ((${#targets[@]} > 0)) && have stat; then
    while IFS=' ' read -r m sz name; do
      [[ $m =~ ^[0-9]+$ ]] || continue
      if [[ $name == "$arc" ]]; then am=$m asz=$sz
      elif [[ $name == "$snap" ]]; then sm=$m; fi
    done < <(stat -c '%Y %s %n' "${targets[@]}" 2>/dev/null)
  fi

  # The script's own stamp is the truth about when it last succeeded; the
  # archive's mtime only stands in when the stamp is missing or unreadable.
  ((stamp > 0)) || stamp=$am
  if ((stamp > 0)); then
    BK_SYS_PRESENT=1 BK_SYS_TS=$stamp BK_SYS_SIZE=$asz BK_SYS_COUNT=${#arcs[@]}
  fi
  if ((sm > 0)); then
    BK_LOC_PRESENT=1 BK_LOC_TS=$sm BK_LOC_COUNT=${#snaps[@]}
  fi
  return 0
}

# Is somebody running the Highway installer right now? Its update and repair
# restart the very units this agent watches, so while it is open a failing unit
# is the operator's own work, not an incident. Suppression is bounded
# (hw_maint_grace_min) so a terminal left open on a broken box still alerts.
hw_maintenance() {
  local now=${EPOCHSECONDS:-0} d c f since grace
  HW_MAINT=0 HW_MAINT_QUIET=0 HW_MAINT_WHY=''
  for d in "${HYN_PROC:-/proc}"/[0-9]*; do
    [[ -r $d/comm ]] || continue
    c=''
    read -r c <"$d/comm" 2>/dev/null || continue
    [[ $c == highway ]] && { HW_MAINT=1; HW_MAINT_WHY='the Highway installer is open on this machine'; break; }
  done
  state_dir_v
  f="$STATE_DIR/hw-maint-since"
  if ((HW_MAINT == 0)); then
    [[ -e $f ]] && rm -f "$f" 2>/dev/null
    return 0
  fi
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null
  since=''
  [[ -r $f ]] && read -r since <"$f" 2>/dev/null
  if [[ ! $since =~ ^[0-9]+$ ]]; then
    since=$now
    printf '%s\n' "$now" >"$f" 2>/dev/null
  fi
  grace=${CFG[hw_maint_grace_min]:-30}
  [[ $grace =~ ^[0-9]+$ ]] || grace=30
  if ((now - since < grace * 60)); then
    HW_MAINT_QUIET=1
  else
    HW_MAINT_WHY="the Highway installer has been open for over ${grace}m"
  fi
  return 0
}

hw_operations() {
  local force=${1:-0} now=${EPOCHSECONDS:-0}
  ((force == 0 && HW_OPS_LAST > 0 && now - HW_OPS_LAST < 30)) && return 0
  HW_OPS_LAST=$now
  HW_OPS_STATE='absent' HW_OPS_ACTION='none' HW_OPS_WHY='' HW_OPS_GATE=''
  HW_CERT_DAYS='' HW_KILLSWITCH=0 HW_HELD=0
  HW_NETWORK='' HW_OS_VERSION='' HW_RELAYER_VERSION='' HW_CONFIG_VERSION=''
  hw_maintenance
  ((HW_PRESENT)) || return 0

  _hw_line "$HW_ETC/hw-os-version" && HW_OS_VERSION=$REPLY
  _hw_line "$HW_ETC/network" && HW_NETWORK=$REPLY
  _hw_line "$HW_ETC/applied-config-version" && [[ $REPLY =~ ^[0-9]+$ ]] && HW_CONFIG_VERSION=$REPLY
  _hw_json "$HW_ETC/binary-swap-state.json" version && HW_RELAYER_VERSION=$REPLY
  _hw_json "$HW_ETC/api-cert-state.json" days_left && [[ $REPLY =~ ^-?[0-9]+$ ]] && HW_CERT_DAYS=$REPLY
  _hw_json "$HW_ETC/killswitch-state.json" engaged && [[ $REPLY == true ]] && HW_KILLSWITCH=1
  _hw_json "$HW_ETC/renew-state.json" gate && HW_OPS_GATE=$REPLY
  [[ -e $HW_ETC/relayer-held-down ]] && HW_HELD=1
  hw_overlay_left
  hw_backup

  # The same decision tree the installer uses to pick its menu (computeBoxStatus).
  local has_identity=0 enrolled=0 cfg reg=''
  for cfg in "$HW_ETC"/relayers/*/config; do
    [[ -f $cfg/p2p_key ]] && { has_identity=1; break; }
  done
  [[ -e $HW_ETC/api.crt || -e $HW_NEBULA_DIR/host.crt ]] && enrolled=1
  _hw_line "$HW_ETC/registration-state" && reg=$REPLY
  local relayer_up=0
  [[ ${HW_STATE[hway-relayer.service]:-} == active ]] && relayer_up=1
  local lapsed=0
  [[ $HW_OVERLAY_LEFT =~ ^-?[0-9]+$ ]] && ((HW_OVERLAY_LEFT <= -3600)) && lapsed=1

  if ((!has_identity && !enrolled)); then
    HW_OPS_STATE='fresh'
  elif ((!has_identity)); then
    HW_OPS_STATE='enrolled-no-relayer'
  elif [[ $reg == pending ]]; then
    HW_OPS_STATE='relayer-unregistered'
  elif [[ ! -e $HW_UNIT_FILE ]]; then
    HW_OPS_STATE='install-incomplete'
  elif [[ $HW_OPS_GATE == key_mismatch_401 ]]; then
    HW_OPS_STATE='key-mismatch'
  elif ((lapsed)); then
    case $HW_OPS_GATE in
      terminal_410 | retired_403) HW_OPS_STATE='deregistered' ;;
      beyond_grace_403) HW_OPS_STATE='awaiting-reactivation' ;;
      *) HW_OPS_STATE='certs-expired' ;;
    esac
  elif ((!relayer_up)); then
    HW_OPS_STATE='installed-stopped'
  else
    HW_OPS_STATE='installed'
  fi

  case $HW_OPS_STATE in
    certs-expired)
      HW_OPS_ACTION='REPAIR CONNECT'
      HW_OPS_WHY='the overlay certificate lapsed; the relayer cannot reach the network' ;;
    key-mismatch)
      HW_OPS_ACTION='REPAIR CONNECT'
      HW_OPS_WHY="the platform rejects this machine's certificate; renewal keeps failing" ;;
    deregistered)
      HW_OPS_ACTION='REPAIR CONNECT'
      HW_OPS_WHY='the platform no longer has this device; repair registers it again (the address may change)' ;;
    awaiting-reactivation)
      HW_OPS_ACTION='REACTIVATE'
      HW_OPS_WHY='the certificate lapsed beyond the grace window; reactivation keeps the registration' ;;
    relayer-unregistered | install-incomplete | enrolled-no-relayer)
      HW_OPS_ACTION='RESUME SETUP'
      HW_OPS_WHY='setup never finished on this machine' ;;
    installed-stopped)
      HW_OPS_ACTION='START RELAYER'
      if ((HW_HELD)); then
        HW_OPS_WHY='the relayer was stopped on purpose and is held down'
      else
        HW_OPS_WHY='the relayer service is not running'
      fi ;;
    installed)
      # Healthy box: pick the most valuable housekeeping. Losing the keys is
      # permanent while a late update arrives on its own, so backup goes first.
      if ((HW_BK_PRESENT == 0)); then
        HW_OPS_ACTION='CREATE BACKUP'
        HW_OPS_WHY='no recovery backup of the relayer keys exists on this machine'
      elif ((HW_BK_STALE)); then
        HW_OPS_ACTION='CREATE BACKUP'
        HW_OPS_WHY='the relayer keys changed after the last backup was made'
      elif ((HW_UPDATE)); then
        HW_OPS_ACTION='UPDATE & REPAIR'
        HW_OPS_WHY="${HW_LATEST:-a newer release} is available (installed: ${HW_OS_VERSION:-${HW_VERSION:-unknown}})"
      fi ;;
  esac
  return 0
}

hw_sample() {
  local ms=$1
  # Backups are worth showing whether or not this box tracks a Highway node.
  bk_local_sample
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
  hw_operations
  return 0
}
