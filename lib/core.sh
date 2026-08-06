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

HYN_VERSION="1.0.0"

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
  [theme]=hiway
  [interval]=1.0
  [net_unit]=bits
  [graph]=braille
  [wan_iface]=auto
  [hide_iface]='lo,docker0,veth,br-,virbr,tap,dummy'
  # Order is priority: on a short terminal the panels at the end are the ones
  # that get dropped. net is always first and always drawn.
  [panels]='net,cpu,mem,node,proc,disk'
  [proc_rows]=8
  [proc_sort]=cpu
  [latency_targets]='1.1.1.1,8.8.8.8'
  [latency_interval]=10
  [latency_gateway]=on
  [dns_probe]=on
  [dns_probe_host]=install.hiwaynetwork.io
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
  [color_depth]=auto
  [ascii]=off
)

# Keys a config file is allowed to set. Anything else is reported, not applied,
# so a typo shows up instead of silently doing nothing.
_cfg_allowed() { [[ -v CFG[$1] ]]; }

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
  local f tmp
  declare -A tmp=()
  for f in "$HYN_ETC/config" "${XDG_CONFIG_HOME:-$HOME/.config}/hyn-view/config" "${HYN_CONFIG:-}"; do
    [[ -n $f && -r $f ]] || continue
    _read_kv "$f" tmp
  done
  local k
  for k in "${!tmp[@]}"; do
    if _cfg_allowed "$k"; then
      CFG[$k]=${tmp[$k]}
    else
      CFG_WARNINGS+=("unknown config key: $k")
    fi
  done
}
declare -a CFG_WARNINGS=()

cfg() { printf '%s' "${CFG[$1]}"; }
cfg_on() { [[ ${CFG[$1]} == on || ${CFG[$1]} == true || ${CFG[$1]} == yes || ${CFG[$1]} == 1 ]]; }

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
