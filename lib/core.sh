#!/usr/bin/env bash
# hyn-view :: core runtime
#
# Everything in here is deliberately fork-free on the hot path. The whole point
# of this tool is that it can sit on a 24/7 relay node without being part of the
# problem, so the render loop uses bash builtins (read, printf, arithmetic,
# parameter expansion) against /proc and /sys and nothing else. If you add a
# collector, budget it: no `awk`, `grep`, `cut`, `ps` or `sed` inside a tick.
#
# HYN_PROC / HYN_SYS exist so test/selfcheck.sh can point the readers at a
# fixture tree and assert on known numbers. Never hardcode /proc below.

HYN_VERSION="1.5.0"
HYN_AUTHOR='NEXUSV'
HYN_AUTHOR_URL='https://www.hyn-view.in'
HYN_COPYRIGHT='(c) 2026 NEXUSV TECHNOLOGIES PRIVATE LIMITED'
HYN_PKG='hyn-view'

# Globbing is left at its default. An earlier version enabled extglob for vlen's
# escape-stripping pattern, which had a nasty side effect: with extglob on, "*("
# starts an extglob group, so ${line#*(} in the /proc/<pid>/stat parser silently
# stopped matching and every process field shifted by one. vlen no longer needs
# it (see ui.sh), so the hazard is gone rather than worked around. If you ever
# do need extglob, scope it with `shopt -s extglob` inside the one function.

: "${HYN_PROC:=/proc}"
: "${HYN_SYS:=/sys}"
: "${HYN_ETC:=/etc/hyn-view}"
: "${HYN_VAR:=/var/lib/hyn-view}"
: "${HYN_RUN:=${XDG_RUNTIME_DIR:-/tmp}/hyn-view-$UID}"

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
# Defaults live here as the single source of truth; /etc/hyn-view/config and
# ~/.config/hyn-view/config override, then CLI flags. Config is PARSED, never
# sourced -- a monitoring tool should not be an arbitrary-code loader just
# because someone can drop a file in /etc.
declare -A CFG=(
  # 'best' for the richest visuals, 'performance' for the cheapest. Sets graph,
  # interval and row counts together; anything you set explicitly still wins.
  [profile]=best
  [theme]=hiway
  [interval]=1.0
  [net_unit]=bits
  [graph]=braille
  # Colour graph rows by height, so a plot reads as a gradient rather than a
  # single flat colour. Costs h colour lookups per graph, all cached.
  [graph_gradient]=on
  # Time axis and min/avg/peak annotation under the network graph.
  [graph_axis]=on
  [graph_stats]=on
  [net_history_detail]=on
  # Show the connection identity (SSID / connection name / local address).
  [net_identity]=on
  [wan_iface]=auto
  [hide_iface]='lo,docker0,veth,br-,virbr,tap,dummy'
  # Mount points to leave out of the disk panel and the disk alerts. Snap
  # squashfs mounts are read-only and permanently 100% full, so they are already
  # excluded by type; these are the paths that are real filesystems but not
  # interesting (container layers, bind mounts of the same device).
  [hide_mount]='/snap,/var/lib/snapd,/var/lib/docker,/var/lib/containers,/run,/dev,/sys,/proc,/boot/efi'
  # Order is priority: on a short terminal the panels at the end are the ones
  # that get dropped. net is always first and always drawn.
  [panels]='net,cpu,mem,node,proc,disk'
  [proc_rows]=8
  [proc_sort]=cpu
  [latency_targets]='1.1.1.1,8.8.8.8'
  [latency_interval]=10
  [latency_gateway]=on
  [dns_probe]=on
  # A neutral, reliably-resolving domain, deliberately not a hostname belonging
  # to any node platform: this probe measures DNS resolution latency and the name
  # queried is irrelevant to the measurement. Making a third party's host the
  # default would send a lookup to them from every install for no benefit.
  [dns_probe_host]=cloudflare.com
  [public_ip]=on
  [tcp_states]=on
  [tcp_states_interval]=5
  [speedtest_per_day]=4
  [speedtest_down_mb]=25
  [speedtest_up_mb]=10
  [speedtest_timeout]=20
  [speedtest_guard_pct]=25
  [speedtest_provider]=auto
  [speedtest_history]=90
  [highway_track]=on
  [highway_update_check]=on
  [highway_version_probe]=off
  [highway_units]='highway*,hw-*,nebula*,mosaic*'

  # --- notification delivery -------------------------------------------------
  # Empty until `sudo hyn setup` configures it; nothing is sent by default.
  [notify_channels]=''
  [notify_to]=''
  [notify_from]='onboarding@resend.dev'
  [notify_from_name]='hyn-view'
  # Account names, active-session origins and rejected-login source addresses
  # can be useful for incident response, but are identity-bearing data. Keep
  # notifications aggregate-only unless the operator explicitly opts in from
  # a local config file; cloud-pulled configuration cannot enable this key.
  [notify_access_details]=off
  [notify_max_per_day]=50
  [notify_timeout]=15
  [smtp_host]=''
  [smtp_port]=587
  [telegram_chat_id]=''
  [ntfy_topic]=''
  [ntfy_server]='https://ntfy.sh'
  [webhook_url]=''
  [heartbeat_url]=''

  # --- alerting --------------------------------------------------------------
  [alert_enabled]=on
  [alert_min_severity]=warn
  [alert_interval_min]=5
  [alert_repeat_hours]=6
  [alert_notify_resolved]=on
  # Set any threshold to 0 to disable that rule entirely.
  [alert_mem_pct]=90
  [alert_mem_crit_pct]=96
  [alert_swap_pct]=60
  [alert_disk_pct]=85
  [alert_disk_crit_pct]=93
  # Load as a percentage of one core: 400 means load 4.0 per core.
  [alert_load_per_core]=400
  [alert_steal_pct]=15
  [alert_iowait_pct]=35
  [alert_temp_c]=85
  [alert_net_err_rate]=10
  # Retransmits in per-mille of segments sent: 50 is 5%.
  [alert_retrans_pm]=50
  [alert_listen_drops]=1
  [alert_conntrack_pct]=85
  [alert_latency_ms]=250
  [alert_loss_pct]=15
  # Warn when a speed test comes back below this percentage of the best ever.
  [alert_speed_min_pct]=50
  [alert_fd_pct]=80
  [alert_hw_restarts]=3
  [alert_hw_journal_err]=5

  # --- daily report ----------------------------------------------------------
  [report_enabled]=on
  [report_at]='08:00'
  [report_hours]=24
  [report_busy_cpu_pct]=80
  [report_busy_mem_pct]=85
  [record_interval_min]=5
  [metrics_keep_days]=8

  # --- web portal / cloud sync ----------------------------------------------
  # Set by `sudo hyn link`. cloud_url and cloud_anon_key are the Supabase
  # project URL and its PUBLIC anon key -- the same key that ships in every
  # browser bundle talking to that project, which is why it lives here in the
  # world-readable config rather than in secrets. The node token, which is the
  # actual credential, goes to /etc/hyn-view/secrets at 0600.
  [cloud_enabled]=off
  [cloud_url]=''
  [cloud_anon_key]=''
  # Where the human opens the pairing page. Only used to print a complete URL
  # during `hyn link`; the agent never contacts it.
  [cloud_portal_url]=''
  [cloud_node_id]=''
  [cloud_push_min]=5
  [cloud_timeout]=20

  # --- self update -----------------------------------------------------------
  # off     never look
  # check   (default) look on launch, tell you, change nothing
  # install look on launch and install a newer version automatically
  #
  # 'check' is the default deliberately. 'install' means this tool runs
  # `npm i -g` as root, unattended, on a production node: a bad release or a
  # compromised registry account would land straight on the box, and a monitor
  # that breaks itself at 3am is worse than one that is a version behind.
  [auto_update]=check
  [update_check_hours]=12
  # Offer the guided setup on the first interactive launch. Asked once; a
  # decline is remembered.
  [onboarding]=on
  [color_depth]=auto
  [ascii]=off
)

# Keys a config file is allowed to set. Anything else is reported, not applied,
# so a typo shows up instead of silently doing nothing.
_cfg_allowed() { [[ -v CFG[$1] ]]; }

# The portal is a much narrower trust boundary than a root-owned local config.
# Keep this list in step with the fields in the portal's NodeSettings form and
# the database constraint. In particular, no destination, credential, network
# endpoint, local privacy option or portal connection setting belongs here.
_cfg_cloud_allowed() {
  case ${1:-} in
    alert_mem_pct | alert_disk_pct | alert_temp_c | alert_load_per_core | \
      alert_latency_ms | alert_min_severity | alert_repeat_hours | report_at | \
      notify_max_per_day | cloud_push_min) return 0 ;;
    *) return 1 ;;
  esac
}

# Validate values before a portal-owned cache is allowed to feed root-run Bash
# arithmetic or systemd timer generation. Local, root-owned config remains a
# separate trust boundary and is intentionally not restricted by this helper.
_cfg_cloud_value_allowed() {
  local k=${1:-} v=${2:-}
  case $k in
    alert_mem_pct | alert_disk_pct)
      [[ $v =~ ^(0|[1-9][0-9]{0,2})$ ]] && ((10#$v <= 100)) ;;
    alert_temp_c)
      [[ $v =~ ^(0|[1-9][0-9]{0,2})$ ]] && ((10#$v <= 200)) ;;
    alert_load_per_core)
      [[ $v =~ ^(0|[1-9][0-9]{0,4})$ ]] && ((10#$v <= 10000)) ;;
    alert_latency_ms)
      [[ $v =~ ^(0|[1-9][0-9]{0,5})$ ]] && ((10#$v <= 600000)) ;;
    alert_repeat_hours)
      [[ $v =~ ^(0|[1-9][0-9]{0,3})$ ]] && ((10#$v <= 8760)) ;;
    notify_max_per_day)
      [[ $v =~ ^(0|[1-9][0-9]{0,4})$ ]] && ((10#$v <= 10000)) ;;
    cloud_push_min)
      [[ $v =~ ^[1-9][0-9]{0,3}$ ]] && ((10#$v <= 1440)) ;;
    alert_min_severity)
      [[ $v == crit || $v == warn || $v == info ]] ;;
    report_at)
      [[ $v =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] ;;
    *) return 1 ;;
  esac
}

# Parse `key=value` lines. Shared by config and theme loading. Tolerates
# comments, blank lines, surrounding whitespace and quoted values.
# usage: _read_kv <file> <assoc-array-name>
_read_kv() {
  local file=$1 k v line
  local -n _dest=$2
  [[ -r $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    [[ $line == *=* ]] || continue
    k=${line%%=*}
    v=${line#*=}
    k=${k//[[:space:]]/}
    [[ -n $k ]] || continue
    # trim outer whitespace then one layer of quotes
    v=${v#"${v%%[![:space:]]*}"}
    v=${v%"${v##*[![:space:]]}"}
    [[ $v == \"*\" || $v == \'*\' ]] && v=${v:1:${#v}-2}
    _dest[$k]=$v
  done <"$file"
  return 0
}

cfg_load() {
  local f tmp k
  declare -A tmp=()
  # Order matters: later files win. The portal's pulled settings come FIRST so a
  # deliberate local line still overrides central management -- an operator who
  # edited a box at 3am with no network must not be silently reverted, and a
  # cache that outranked explicit config would be undebuggable.
  local cloud_cache=''
  if [[ -n ${HYN_VAR:-} ]]; then
    state_dir_v
    cloud_cache="$STATE_DIR/cloud-config"
  fi
  # Filter a stale cache written by any older agent before reading
  # operator-controlled files. Local config is intentionally unrestricted by
  # this portal allowlist and is read afterwards, so an operator can still set
  # delivery destinations and every other supported local key.
  if [[ -n $cloud_cache && -r $cloud_cache ]]; then
    _read_kv "$cloud_cache" tmp
    for k in "${!tmp[@]}"; do
      if ! _cfg_cloud_allowed "$k" || ! _cfg_cloud_value_allowed "$k" "${tmp[$k]}"; then
        unset 'tmp[$k]'
      fi
    done
  fi
  for f in "$HYN_ETC/config" "${XDG_CONFIG_HOME:-$HOME/.config}/hyn-view/config" "${HYN_CONFIG:-}"; do
    [[ -n $f && -r $f ]] || continue
    _read_kv "$f" tmp
  done
  for k in "${!tmp[@]}"; do
    if _cfg_allowed "$k"; then
      CFG[$k]=${tmp[$k]}
      # Remembered so profile_apply knows not to overwrite a deliberate choice.
      CFG_EXPLICIT[$k]=1
    else
      CFG_WARNINGS+=("unknown config key: $k")
    fi
  done
  profile_apply
}
declare -a CFG_WARNINGS=()
declare -A CFG_EXPLICIT=()

cfg() { printf '%s' "${CFG[$1]}"; }
cfg_on() { [[ ${CFG[$1]} == on || ${CFG[$1]} == true || ${CFG[$1]} == yes || ${CFG[$1]} == 1 ]]; }

# ---------------------------------------------------------------------------
# semver comparison
# ---------------------------------------------------------------------------
# ver_gt <a> <b> -- true when a is strictly newer than b. Numeric per component,
# so 0.1.9 correctly sorts BEFORE 0.1.75, which string comparison gets wrong and
# which is exactly the range real projects live in.
ver_gt() {
  local a=${1#v} b=${2#v} i x y
  [[ -n $a && -n $b ]] || return 1
  local -a pa=() pb=()
  local oIFS=$IFS
  IFS='.'
  # shellcheck disable=SC2206
  pa=($a); pb=($b)
  IFS=$oIFS
  for i in 0 1 2; do
    x=${pa[i]:-0} y=${pb[i]:-0}
    x=${x%%-*} y=${y%%-*}
    [[ $x =~ ^[0-9]+$ ]] || x=0
    [[ $y =~ ^[0-9]+$ ]] || y=0
    ((x > y)) && return 0
    ((x < y)) && return 1
  done
  return 1
}

# ---------------------------------------------------------------------------
# visual profiles
# ---------------------------------------------------------------------------
# `profile` is a preset over several keys, so an operator picks an intent rather
# than tuning six settings. It only fills in keys the config file did NOT set
# explicitly -- otherwise choosing a profile would silently discard a deliberate
# `graph=` line, which is the kind of surprise that makes presets useless.
profile_apply() {
  local p=${CFG[profile]}
  _pdef() { [[ -v CFG_EXPLICIT[$1] ]] || CFG[$1]=$2; }
  case $p in
    best | quality | rich)
      _pdef graph braille
      _pdef graph_gradient on
      _pdef graph_axis on
      _pdef graph_stats on
      _pdef interval 1.0
      _pdef proc_rows 10
      _pdef net_history_detail on
      ;;
    performance | perf | lite | fast)
      _pdef graph block
      _pdef graph_gradient off
      _pdef graph_axis off
      _pdef graph_stats off
      _pdef interval 2.0
      _pdef proc_rows 6
      _pdef net_history_detail off
      ;;
  esac
  unset -f _pdef
  return 0
}

# ---------------------------------------------------------------------------
# capability probes (cached; `command -v` is a builtin so this stays fork-free)
# ---------------------------------------------------------------------------
declare -A _HAVE=()
have() {
  [[ -v _HAVE[$1] ]] || { if command -v "$1" >/dev/null 2>&1; then _HAVE[$1]=1; else _HAVE[$1]=0; fi; }
  ((_HAVE[$1]))
}
is_root() { [[ ${EUID:-$(id -u)} -eq 0 ]]; }

# ---------------------------------------------------------------------------
# colour
# ---------------------------------------------------------------------------
# Themes declare colours as #rrggbb. We resolve them once, at load, into escape
# sequences for whatever the terminal actually supports -- so a theme author
# never writes an escape code and a 16-colour serial console still renders.
COLOR_DEPTH=24

color_detect() {
  case ${CFG[color_depth]} in
    24|truecolor) COLOR_DEPTH=24; return ;;
    256) COLOR_DEPTH=256; return ;;
    16|8) COLOR_DEPTH=16; return ;;
    none|off|0) COLOR_DEPTH=0; return ;;
  esac
  if [[ -n ${NO_COLOR:-} ]]; then COLOR_DEPTH=0
  elif [[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]]; then COLOR_DEPTH=24
  elif [[ ${TERM:-} == *256color* || ${TERM:-} == *direct* ]]; then COLOR_DEPTH=256
  elif [[ ${TERM:-dumb} == dumb || -z ${TERM:-} ]]; then COLOR_DEPTH=0
  else COLOR_DEPTH=16
  fi
}

# #rrggbb -> r g b (as three globals, avoids a subshell per call)
_HEX_R=0 _HEX_G=0 _HEX_B=0
hex_rgb() {
  local h=${1#\#}
  [[ ${#h} -eq 3 ]] && h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}"
  _HEX_R=$((16#${h:0:2})) _HEX_G=$((16#${h:2:2})) _HEX_B=$((16#${h:4:2}))
}

# Nearest xterm-256 index (in $RGB_IDX): 6x6x6 cube, or the 24-step grey ramp
# when the channels are close enough that the cube would visibly tint a grey.
RGB_IDX=0
_rgb_256_v() {
  local r=$1 g=$2 b=$3 mx=$1 mn=$1 l
  ((g > mx)) && mx=$g; ((b > mx)) && mx=$b
  ((g < mn)) && mn=$g; ((b < mn)) && mn=$b
  if ((mx - mn < 12)); then
    l=$(((r + g + b) / 3))
    if ((l < 8)); then RGB_IDX=16
    elif ((l > 248)); then RGB_IDX=231
    else RGB_IDX=$((232 + (l - 8) * 24 / 241)); fi
    return
  fi
  RGB_IDX=$((16 + 36 * (r * 5 / 255) + 6 * (g * 5 / 255) + (b * 5 / 255)))
}

# Nearest of the 16 ANSI colours, by channel bucket + brightness.
_rgb_16_v() {
  local r=$1 g=$2 b=$3 i=0 mx=$1
  ((g > mx)) && mx=$g; ((b > mx)) && mx=$b
  ((r > mx / 2)) && ((i |= 1))
  ((g > mx / 2)) && ((i |= 2))
  ((b > mx / 2)) && ((i |= 4))
  ((mx > 170)) && ((i |= 8))
  ((mx < 40)) && i=0
  RGB_IDX=$i
}

# hex -> SGR escape, returned in $HEX_ESC. $2: fg (default) or bg.
# Sets a global rather than printing so callers don't need a subshell; there is
# a printing wrapper below for the handful of call sites that read cleaner.
HEX_ESC=''
hex_esc_v() {
  local hex=$1 sel=38 base=30 bright=90 idx
  [[ ${2:-fg} == bg ]] && { sel=48; base=40; bright=100; }
  HEX_ESC=''
  ((COLOR_DEPTH == 0)) && return 0
  hex_rgb "$hex"
  case $COLOR_DEPTH in
    24) printf -v HEX_ESC '\033[%d;2;%d;%d;%dm' "$sel" "$_HEX_R" "$_HEX_G" "$_HEX_B" ;;
    256)
      _rgb_256_v "$_HEX_R" "$_HEX_G" "$_HEX_B"
      printf -v HEX_ESC '\033[%d;5;%dm' "$sel" "$RGB_IDX" ;;
    16)
      _rgb_16_v "$_HEX_R" "$_HEX_G" "$_HEX_B"
      idx=$RGB_IDX
      if ((idx > 7)); then printf -v HEX_ESC '\033[%dm' $((idx - 8 + bright))
      else printf -v HEX_ESC '\033[%dm' $((idx + base)); fi ;;
  esac
}
hex_esc() { hex_esc_v "$@"; printf '%s' "$HEX_ESC"; }

# ---------------------------------------------------------------------------
# theme
# ---------------------------------------------------------------------------
# C_* are ready-to-print escapes. T_* are the raw hexes, kept so gradients can
# interpolate (see ui.sh grad_pick).
declare -A THEME=()
declare -A C=()

theme_dirs() { printf '%s\n' "$HYN_ETC/themes" "${XDG_CONFIG_HOME:-$HOME/.config}/hyn-view/themes" "$HYN_LIB/../themes"; }

theme_path() {
  # Name validation is a trust boundary: theme names arrive from config files
  # and argv, and get pasted into a filesystem path.
  [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ $1 == *..* ]] && return 1
  local d
  while read -r d; do
    [[ -r $d/$1.theme ]] && { printf '%s' "$d/$1.theme"; return 0; }
  done < <(theme_dirs)
  return 1
}

theme_list() {
  local d f n
  declare -A seen=()
  while read -r d; do
    [[ -d $d ]] || continue
    for f in "$d"/*.theme; do
      [[ -r $f ]] || continue
      n=${f##*/}; n=${n%.theme}
      [[ -v seen[$n] ]] && continue
      seen[$n]=1
      printf '%s\n' "$n"
    done
  done < <(theme_dirs)
}

theme_load() {
  local name=${1:-${CFG[theme]}} path
  path=$(theme_path "$name") || {
    path=$(theme_path hiway) || return 1
    CFG_WARNINGS+=("theme '$name' not found, using hiway")
  }
  THEME=()
  _read_kv "$path" THEME || return 1
  local k v
  # Sane fallbacks so a partial/minimal theme file still renders.
  : "${THEME[fg]:=#c8d3e0}"   "${THEME[dim]:=#5b6878}"   "${THEME[border]:=#2b3648}"
  : "${THEME[title]:=${THEME[fg]}}" "${THEME[accent]:=#00d4ff}" "${THEME[accent2]:=${THEME[accent]}}"
  : "${THEME[ok]:=#3ddc84}"   "${THEME[warn]:=#ffb020}"  "${THEME[crit]:=#ff4d5e}"
  : "${THEME[rx]:=${THEME[ok]}}" "${THEME[tx]:=${THEME[accent]}}"
  : "${THEME[g_low]:=${THEME[ok]}}" "${THEME[g_mid]:=${THEME[warn]}}" "${THEME[g_high]:=${THEME[crit]}}"
  : "${THEME[panel_bg]:=}"
  C=()
  for k in "${!THEME[@]}"; do
    v=${THEME[$k]}
    [[ $v == \#* ]] || continue
    hex_esc_v "$v"
    C[$k]=$HEX_ESC
  done
  C[reset]=$'\033[0m'
  C[bold]=$'\033[1m'
  C[rev]=$'\033[7m'
  ((COLOR_DEPTH == 0)) && { C[bold]=''; C[rev]=''; C[reset]=''; }
  THEME_NAME=$name
}

# ---------------------------------------------------------------------------
# formatting (integer-only: bash has no floats and forking `bc` per cell is
# exactly the kind of thing that makes bash TUIs slow)
#
# Same convention as ui.sh: the `_v` form sets a global, the bare form prints.
# A frame formats ~30 numbers, so the value form is what the render loop uses.
# ---------------------------------------------------------------------------
_UNITS_BIN=(B KiB MiB GiB TiB PiB)
_UNITS_DEC=(b Kb Mb Gb Tb Pb)
FMT_OUT=''

# fmt_size_v <bytes> -> "12.4 GiB"
fmt_size_v() {
  local v=$1 i=0 whole frac
  [[ $v =~ ^-?[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  while ((v >= 1048576 && i < 5)); do v=$((v / 1024)); ((i++)); done
  if ((v >= 1024 && i < 5)); then
    whole=$((v / 1024)); frac=$(((v % 1024) * 10 / 1024)); ((i++))
  else
    whole=$v; frac=-1
  fi
  if ((i == 0 || whole >= 100 || frac < 0)); then printf -v FMT_OUT '%d %s' "$whole" "${_UNITS_BIN[i]}"
  else printf -v FMT_OUT '%d.%d %s' "$whole" "$frac" "${_UNITS_BIN[i]}"; fi
  return 0
}

# fmt_rate_v <bytes-per-second> -- honours net_unit. Bits is the default because
# NICs are specified in bits and that is what an operator compares against their
# link speed; bytes is available for people who think in file sizes.
fmt_rate_v() {
  local bps=$1 v i=0 whole frac unit
  [[ $bps =~ ^-?[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  ((bps < 0)) && bps=0
  if [[ ${CFG[net_unit]} == bytes ]]; then
    v=$bps
    while ((v >= 1048576 && i < 5)); do v=$((v / 1024)); ((i++)); done
    if ((v >= 1024 && i < 5)); then whole=$((v / 1024)); frac=$(((v % 1024) * 10 / 1024)); ((i++))
    else whole=$v; frac=0; fi
    unit=${_UNITS_BIN[i]}/s
  else
    v=$((bps * 8))
    while ((v >= 1000000 && i < 5)); do v=$((v / 1000)); ((i++)); done
    if ((v >= 1000 && i < 5)); then whole=$((v / 1000)); frac=$(((v % 1000) / 100)); ((i++))
    else whole=$v; frac=0; fi
    unit=${_UNITS_DEC[i]}ps
  fi
  if ((i == 0 || whole >= 100)); then printf -v FMT_OUT '%d %s' "$whole" "$unit"
  else printf -v FMT_OUT '%d.%d %s' "$whole" "$frac" "$unit"; fi
  return 0
}

# fmt_dur_v <seconds> -> "12d 04:31" / "4h 31m" / "31m 09s"
fmt_dur_v() {
  local s=$1 d h m
  [[ $s =~ ^[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  ((d = s / 86400, s %= 86400, h = s / 3600, s %= 3600, m = s / 60, s %= 60))
  if ((d > 0)); then printf -v FMT_OUT '%dd %02d:%02d' "$d" "$h" "$m"
  elif ((h > 0)); then printf -v FMT_OUT '%dh %02dm' "$h" "$m"
  elif ((m > 0)); then printf -v FMT_OUT '%dm %02ds' "$m" "$s"
  else printf -v FMT_OUT '%ds' "$s"; fi
  return 0
}

# fmt_fixed_v <scaled-int> <scale> [decimals] -- render fixed-point integers,
# e.g. fmt_fixed_v 8456 1000 2 -> "8.45"
fmt_fixed_v() {
  local v=$1 scale=$2 dec=${3:-1} whole frac neg=''
  [[ $v =~ ^-?[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  ((v < 0)) && { neg='-'; v=$((-v)); }
  whole=$((v / scale)); frac=$((v % scale))
  printf -v FMT_OUT '%s%d.%0*d' "$neg" "$whole" "$dec" $((frac * 10 ** dec / scale))
  return 0
}

# fmt_thousands_v <int> -> 1,234,567 (no locale, no printf %'d dependency)
fmt_thousands_v() {
  local n=$1 sign='' out=''
  [[ $n =~ ^-?[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  [[ $n == -* ]] && { sign=-; n=${n#-}; }
  while ((${#n} > 3)); do out=,${n: -3}$out; n=${n:0:${#n} - 3}; done
  FMT_OUT="$sign$n$out"
  return 0
}

# Compact count for tight columns: 1234 -> 1.2K, 1234567 -> 1.2M
fmt_count_v() {
  local n=$1
  [[ $n =~ ^-?[0-9]+$ ]] || { FMT_OUT='-'; return 0; }
  if ((n < 1000)); then FMT_OUT=$n
  elif ((n < 1000000)); then printf -v FMT_OUT '%d.%dK' $((n / 1000)) $((n % 1000 / 100))
  elif ((n < 1000000000)); then printf -v FMT_OUT '%d.%dM' $((n / 1000000)) $((n % 1000000 / 100000))
  else printf -v FMT_OUT '%d.%dG' $((n / 1000000000)) $((n % 1000000000 / 100000000)); fi
  return 0
}

fmt_size() { fmt_size_v "$@"; printf '%s' "$FMT_OUT"; }
fmt_rate() { fmt_rate_v "$@"; printf '%s' "$FMT_OUT"; }
fmt_dur() { fmt_dur_v "$@"; printf '%s' "$FMT_OUT"; }
fmt_fixed() { fmt_fixed_v "$@"; printf '%s' "$FMT_OUT"; }
fmt_thousands() { fmt_thousands_v "$@"; printf '%s' "$FMT_OUT"; }
fmt_count() { fmt_count_v "$@"; printf '%s' "$FMT_OUT"; }

# ---------------------------------------------------------------------------
# tiny /proc helpers
# ---------------------------------------------------------------------------
# Read the first line of a file into a named var. `read <file` is a redirect,
# not a fork -- this is the cheapest way to get a value out of /proc or /sys.
readval() {
  local -n _v=$1
  # The -r test is not redundant: a failed `<` redirection is reported by the
  # shell itself, so `2>/dev/null` on the read does not suppress it, and /proc
  # is full of files that exist on one kernel and not the next.
  [[ -r $2 ]] || { _v=''; return 1; }
  read -r _v <"$2" 2>/dev/null || { _v=''; return 1; }
  return 0
}

# Monotonic-ish millisecond clock. Sets NOW_MS rather than printing: this is
# called on every tick and inside latency measurement, where a fork would not
# only cost time but be *counted* as part of the interval being measured.
# EPOCHREALTIME is bash >= 5.0.
NOW_MS=0
now_ms_v() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local t=${EPOCHREALTIME/[.,]/}
    NOW_MS=$((10#${t:0:${#t} - 3}))
  else
    NOW_MS=$((${EPOCHSECONDS:-0} * 1000))
  fi
  return 0
}
now_ms() { now_ms_v; printf '%s' "$NOW_MS"; }

# Atomic-ish write for cache/state files: a half-written cache read by the
# render loop would show garbage, and these are cheap to make safe.
write_atomic() {
  local dest=$1 tmp
  tmp="$dest.tmp.$$"
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dest"
}

# Where history and caches live. Memoised: several collectors want this on every
# tick, and `sd=$(state_dir)` in each of them was four subshell forks per frame.
# The answer cannot change during a run.
STATE_DIR=''
state_dir_v() {
  if [[ -z $STATE_DIR ]]; then
    # Prefer the packaged state dir when writable (root, or after `hyn setup`),
    # otherwise the user's own, so an unprivileged operator still gets history
    # and caches instead of silent failures.
    if [[ -w $HYN_VAR ]]; then STATE_DIR=$HYN_VAR
    else STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyn-view"; fi
  fi
  return 0
}
state_dir() { state_dir_v; printf '%s' "$STATE_DIR"; }

die() { printf 'hyn: %s\n' "$*" >&2; exit 1; }
warn() { printf 'hyn: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# first run
# ---------------------------------------------------------------------------
# True when nobody has configured this install yet. Two independent signals,
# because either one alone gets it wrong:
#
#   * no config file anywhere -- but a user who declined onboarding has no config
#     either, and must not be asked again on every launch;
#   * no "onboarded" marker -- but `sudo hyn setup` writes a config without ever
#     touching the marker, and that operator is plainly already set up.
#
# So: first run means no config AND no marker.
onboard_marker() {
  state_dir_v
  printf '%s/onboarded' "$STATE_DIR"
}

is_first_run() {
  [[ -r $HYN_ETC/config ]] && return 1
  [[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/hyn-view/config ]] && return 1
  [[ -r $(onboard_marker) ]] && return 1
  return 0
}

# Records that the question has been asked, whatever the answer was.
onboard_mark_done() {
  local f
  f=$(onboard_marker)
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  printf '%s\t%s\n' "${EPOCHSECONDS:-0}" "${1:-completed}" >"$f" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# config writing
# ---------------------------------------------------------------------------
# Lives here rather than in bin/hyn because the setup wizard writes config too.
config_file_rw() {
  # Root edits the system config so the change applies to the timers and to
  # every operator on the box; an unprivileged user gets their own.
  if is_root; then
    printf '%s' "$HYN_ETC/config"
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/hyn-view/config"
  fi
}

# Rewrites one key in place, preserving comments and everything else in the file.
config_set() {
  local k=$1 v=$2 f
  _cfg_allowed "$k" || { warn "unknown config key: $k"; return 1; }
  f=$(config_file_rw)
  mkdir -p "${f%/*}" 2>/dev/null || { warn "cannot create ${f%/*}"; return 1; }
  local -a out=()
  local line found=0
  if [[ -r $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$k="* || $line == "$k "*=* ]]; then
        out+=("$k=$v")
        found=1
      else
        out+=("$line")
      fi
    done <"$f"
  fi
  ((found == 0)) && out+=("$k=$v")
  printf '%s\n' "${out[@]}" >"$f.tmp" && mv -f "$f.tmp" "$f" || { warn "cannot write $f"; return 1; }
  CFG[$k]=$v
  return 0
}

# Secrets go to their own root-only file. Keeping them out of the 0644 config is
# the whole point, so this never touches config_set.
secret_set() {
  local k=$1 v=$2 f
  f="$HYN_ETC/secrets"
  mkdir -p "$HYN_ETC" 2>/dev/null || { warn "cannot create $HYN_ETC"; return 1; }
  local -a out=()
  local line found=0
  if [[ -r $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$k="* ]]; then
        out+=("$k=$v"); found=1
      else
        out+=("$line")
      fi
    done <"$f"
  else
    out+=('# hyn-view secrets. Mode 0600, root only. Do not commit this file.')
  fi
  ((found == 0)) && out+=("$k=$v")
  # Create with restrictive permissions BEFORE writing, so the key is never
  # briefly world-readable.
  local tmp="$f.tmp"
  : >"$tmp" && chmod 600 "$tmp" || { warn "cannot create $tmp"; return 1; }
  printf '%s\n' "${out[@]}" >"$tmp" && mv -f "$tmp" "$f" || { warn "cannot write $f"; return 1; }
  chmod 600 "$f" 2>/dev/null
  SEC[$k]=$v
  return 0
}

# clamp <v> <lo> <hi>
clamp() { local v=$1; (($1 < $2)) && v=$2; (($1 > $3)) && v=$3; printf '%d' "$v"; }


# "0.42" -> 420, "8.456" -> 8456 (thousandths), fork-free. Used wherever the
# kernel hands us a decimal string and we need integer math on it.
FIX3=0
parse_fixed3_v() {
  local s=$1 w f
  w=${s%%.*}
  f=${s#*.}
  [[ $f == "$s" ]] && f=0
  f=${f}000
  f=${f:0:3}
  [[ $w =~ ^[0-9]+$ ]] || w=0
  [[ $f =~ ^[0-9]+$ ]] || f=0
  FIX3=$((w * 1000 + 10#$f))
  return 0
}
