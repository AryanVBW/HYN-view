#!/usr/bin/env bash
# hyn-view :: rendering engine
#
# Three ideas carry the whole thing:
#
#   1. One write per frame. Panels append to a line buffer; fb_flush diffs it
#      against the previous frame and emits only the lines that changed, in a
#      single printf. No clear-screen, so no flicker and no tearing, and an
#      idle server costs a few bytes per tick instead of a full repaint.
#
#   2. No command substitution. Every widget writes its result to a global
#      instead of being called as $(widget ...). `$( )` forks a subshell, and a
#      frame touches widgets ~50 times -- at 1 Hz that alone would cost more CPU
#      than every /proc read combined. Hence the `_v` (value) convention: bar_v
#      sets BAR_OUT, pad_v sets PAD_OUT, and so on. The bare-name wrappers at
#      the bottom print instead, and exist only for one-shot CLI output.
#
#   3. Braille plotting. Each cell holds a 2x4 dot matrix, so a graph gets 4x
#      the vertical resolution of block characters at the same cost. Masks are
#      precomputed per (sub-column, filled-count) so plotting costs
#      O(cols x rows) rather than O(cols x dots).

# ---------------------------------------------------------------------------
# unicode / locale
# ---------------------------------------------------------------------------
# Bash measures ${#s} in characters only when the locale is UTF-8. Plenty of
# Ubuntu servers run LANG=C, where every braille glyph counts as 3 bytes and the
# whole layout shears. Fix the locale if we can, drop to ASCII if we can't.
ui_locale() {
  [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *[Uu][Tt][Ff]* ]] && return 0
  local l
  for l in C.UTF-8 C.utf8 en_US.UTF-8; do
    if LC_ALL=$l printf '\u2588' >/dev/null 2>&1; then export LC_ALL=$l; return 0; fi
  done
  CFG[ascii]=on
  CFG_WARNINGS+=("no UTF-8 locale available; falling back to ASCII glyphs")
  return 0
}

declare -a BRAILLE=() GLYPH_BLOCK=() GLYPH_LBLOCK=()
G_HLINE='' G_VLINE='' G_TL='' G_TR='' G_BL='' G_BR='' G_UP='' G_DOWN='' G_DOT='' G_ELL=''

glyphs_init() {
  local i n b
  if cfg_on ascii; then
    GLYPH_BLOCK=(' ' '.' '.' ':' ':' '|' '|' '#' '#')
    GLYPH_LBLOCK=(' ' '.' '.' ':' ':' '|' '|' '#' '#')
    G_HLINE='-' G_VLINE='|' G_TL='+' G_TR='+' G_BL='+' G_BR='+'
    G_UP='v' G_DOWN='^' G_DOT='*' G_ELL='~'
    # Still fill 256 entries so braille_plot can index blindly; density buckets
    # keep the graph shape readable on a serial console.
    BRAILLE=()
    for ((i = 0; i < 256; i++)); do
      n=0
      for b in 1 2 4 8 16 32 64 128; do ((i & b)) && ((n++)); done
      case $n in
        0) BRAILLE[i]=' ' ;;
        1 | 2) BRAILLE[i]='.' ;;
        3 | 4) BRAILLE[i]=':' ;;
        5 | 6) BRAILLE[i]='|' ;;
        *) BRAILLE[i]='#' ;;
      esac
    done
    return 0
  fi
  # Two ramps, because the eighth blocks come in two axes and using the wrong one
  # is visible: GLYPH_BLOCK grows upward from the baseline (for sparkline columns
  # and heat cells), GLYPH_LBLOCK grows rightward from the left edge (for
  # horizontal bars). A horizontal bar ending in a lower-eighth block renders as a
  # squat mark sitting on the baseline -- it reads as a glitch, not as precision.
  GLYPH_BLOCK=(' ' $'\u2581' $'\u2582' $'\u2583' $'\u2584' $'\u2585' $'\u2586' $'\u2587' $'\u2588')
  GLYPH_LBLOCK=(' ' $'\u258f' $'\u258e' $'\u258d' $'\u258c' $'\u258b' $'\u258a' $'\u2589' $'\u2588')
  G_HLINE=$'\u2500' G_VLINE=$'\u2502' G_TL=$'\u256d' G_TR=$'\u256e' G_BL=$'\u2570' G_BR=$'\u256f'
  G_UP=$'\u25b4' G_DOWN=$'\u25be' G_DOT=$'\u25cf' G_ELL=$'\u2026'
  BRAILLE=()
  # Two steps on purpose: printf interprets \U in the FORMAT string, so
  # '\U%08x' is a malformed escape rather than a template. Build the literal
  # escape text first, then let %b interpret it.
  local esc
  for ((i = 0; i < 256; i++)); do
    printf -v esc '\\U%08x' $((0x2800 + i))
    printf -v "BRAILLE[$i]" '%b' "$esc"
  done
  return 0
}

# Dot masks for "n sub-rows filled from the bottom / top", indexed [sub*5 + n].
# Braille dot bits: col0 = 0x01,0x02,0x04,0x40 top->bottom; col1 = 0x08,0x10,0x20,0x80.
declare -a BMASK_BOT=() BMASK_TOP=()
bmask_init() {
  BMASK_BOT=(0 64 68 70 71 0 128 160 176 184)
  BMASK_TOP=(0 1 3 7 71 0 8 24 56 184)
}

# ---------------------------------------------------------------------------
# terminal lifecycle
# ---------------------------------------------------------------------------
TERM_ROWS=24 TERM_COLS=80
_TTY_SAVED='' _TERM_SETUP=0

term_size() {
  local s
  # The only fork on the render path, and it runs once at startup plus once per
  # SIGWINCH. Resizes are rare; there is no builtin ioctl to poll instead.
  if s=$(stty size 2>/dev/null </dev/tty); then
    TERM_ROWS=${s%% *} TERM_COLS=${s##* }
  elif [[ -n ${LINES:-} && -n ${COLUMNS:-} ]]; then
    TERM_ROWS=$LINES TERM_COLS=$COLUMNS
  fi
  [[ $TERM_ROWS =~ ^[0-9]+$ ]] || TERM_ROWS=24
  [[ $TERM_COLS =~ ^[0-9]+$ ]] || TERM_COLS=80
  ((TERM_ROWS < 10)) && TERM_ROWS=10
  ((TERM_COLS < 40)) && TERM_COLS=40
  return 0
}

term_setup() {
  [[ -t 1 ]] || die "stdout is not a terminal (use 'hyn snapshot' for non-interactive output)"
  _TTY_SAVED=$(stty -g 2>/dev/null </dev/tty) || true
  # -echo -icanon: read keys immediately without echoing them into the frame.
  # time 0 min 0 keeps `read -t` from blocking on a partial escape sequence.
  stty -echo -icanon time 0 min 0 2>/dev/null </dev/tty || true
  printf '\033[?1049h\033[?25l\033[2J\033[H'
  _TERM_SETUP=1
  term_size
}

term_restore() {
  ((_TERM_SETUP)) || return 0
  _TERM_SETUP=0
  printf '\033[?25h\033[?1049l\033[0m'
  [[ -n $_TTY_SAVED ]] && stty "$_TTY_SAVED" 2>/dev/null </dev/tty
  return 0
}

# ---------------------------------------------------------------------------
# frame buffer
# ---------------------------------------------------------------------------
declare -a FB=() FB_PREV=()

fb_reset() { FB=(); }
fb_add() { FB+=("$1"); }
fb_addmany() { (($# )) && FB+=("$@"); return 0; }

fb_flush() {
  local out='' i n=${#FB[@]} p=${#FB_PREV[@]}
  ((n > TERM_ROWS)) && n=$TERM_ROWS
  for ((i = 0; i < n; i++)); do
    # \001 sentinel: any real line differs from it, so a grown frame repaints.
    [[ ${FB[i]} == "${FB_PREV[i]-$'\001'}" ]] && continue
    out+=$'\033['$((i + 1))';1H\033[K'"${FB[i]}"
  done
  for ((i = n; i < p; i++)); do out+=$'\033['$((i + 1))';1H\033[K'; done
  [[ -n $out ]] && printf '%s\033[0m' "$out"
  FB_PREV=("${FB[@]:0:n}")
  return 0
}

fb_invalidate() { FB_PREV=(); printf '\033[2J'; }

# ---------------------------------------------------------------------------
# width-aware string helpers
# ---------------------------------------------------------------------------
VLEN=0 PAD_OUT='' FIT_OUT='' REP_OUT=''

# Visible width: the length with SGR sequences discounted.
#
# This is the hottest function in the program -- a frame calls it several hundred
# times, once per padded field and once per composed row. The obvious
# implementation, ${s//$'\033'\[+([0-9;])m/}, measured 4.7ms per call and by
# itself accounted for ~1.2s of CPU per frame: bash's extglob matcher backtracks
# across the whole string. Peeling one escape at a time with plain prefix and
# suffix expansions does the same job in 0.12ms, a 39x difference, because each
# step is a simple anchored match.
#
# Do not "simplify" this back into a single pattern substitution.
vlen() {
  local s=$1
  case $s in
    *$'\033'*) ;;
    *) VLEN=${#s}; return 0 ;;
  esac
  local n=0 head
  while [[ $s == *$'\033'* ]]; do
    head=${s%%$'\033'*}
    n=$((n + ${#head}))
    s=${s#*$'\033'}
    s=${s#*m}
  done
  VLEN=$((n + ${#s}))
  return 0
}

# n copies of a character, fork-free: printf makes the spaces, expansion swaps.
rep_v() {
  local n=$2
  ((n <= 0)) && { REP_OUT=''; return 0; }
  printf -v REP_OUT '%*s' "$n" ''
  [[ $1 == ' ' ]] || REP_OUT=${REP_OUT// /$1}
  return 0
}

pad_v() {
  vlen "$1"
  if ((VLEN < $2)); then
    printf -v PAD_OUT '%s%*s' "$1" $(($2 - VLEN)) ''
  else
    PAD_OUT=$1
  fi
  return 0
}

# Truncate to a visible width, keeping escape sequences intact and resetting at
# the cut so a clipped line cannot leak colour into the rest of the row.
fit_v() {
  local s=$1 w=$2 out='' vis=0 i ch n=${#1}
  vlen "$s"
  ((VLEN <= w)) && { pad_v "$s" "$w"; FIT_OUT=$PAD_OUT; return 0; }
  for ((i = 0; i < n; i++)); do
    ch=${s:i:1}
    if [[ $ch == $'\033' ]]; then
      out+=$ch
      while ((++i < n)); do
        out+=${s:i:1}
        [[ ${s:i:1} == m ]] && break
      done
      continue
    fi
    ((vis >= w - 1)) && { out+=$G_ELL; break; }
    out+=$ch
    ((vis++))
  done
  FIT_OUT="$out${C[reset]}"
  return 0
}

# ---------------------------------------------------------------------------
# gradient
# ---------------------------------------------------------------------------
# Interpolates low->mid->high in RGB, cached per percent: a gauge sweeping the
# full range costs at most 101 conversions for the life of the process.
declare -A _GRAD=()
GRAD_OUT=''
grad_v() {
  local p=$1
  ((p < 0)) && p=0
  ((p > 100)) && p=100
  if [[ -v _GRAD[$p] ]]; then GRAD_OUT=${_GRAD[$p]}; return 0; fi
  local a b t r1 g1 b1 r2 g2 b2 r g bl hex
  if ((p < 50)); then a=${THEME[g_low]} b=${THEME[g_mid]} t=$((p * 2))
  else a=${THEME[g_mid]} b=${THEME[g_high]} t=$(((p - 50) * 2)); fi
  hex_rgb "$a"; r1=$_HEX_R g1=$_HEX_G b1=$_HEX_B
  hex_rgb "$b"; r2=$_HEX_R g2=$_HEX_G b2=$_HEX_B
  r=$((r1 + (r2 - r1) * t / 100))
  g=$((g1 + (g2 - g1) * t / 100))
  bl=$((b1 + (b2 - b1) * t / 100))
  printf -v hex '#%02x%02x%02x' "$r" "$g" "$bl"
  hex_esc_v "$hex"
  _GRAD[$p]=$HEX_ESC
  GRAD_OUT=$HEX_ESC
  return 0
}

# ---------------------------------------------------------------------------
# widgets
# ---------------------------------------------------------------------------
BAR_OUT='' SPARK_OUT='' HEAT_OUT='' KV_OUT=''

# bar_v <percent> <width> [colour]
# Sub-cell precision via the eighth-block glyphs: a 20-cell bar resolves 160
# steps, so slow drift is actually visible instead of quantised away.
bar_v() {
  local p=$1 w=$2 col=${3:-} eighths full part
  ((p < 0)) && p=0
  ((p > 100)) && p=100
  if [[ -z $col ]]; then grad_v "$p"; col=$GRAD_OUT; fi
  eighths=$((p * w * 8 / 100))
  full=$((eighths / 8)); part=$((eighths % 8))
  BAR_OUT=$col
  if ((full > 0)); then rep_v "${GLYPH_LBLOCK[8]}" "$full"; BAR_OUT+=$REP_OUT; fi
  if ((part > 0 && full < w)); then BAR_OUT+=${GLYPH_LBLOCK[part]}; ((full++)); fi
  if ((full < w)); then
    rep_v "${GLYPH_LBLOCK[0]}" $((w - full))
    BAR_OUT+="${C[dim]}$REP_OUT"
  fi
  BAR_OUT+=${C[reset]}
  return 0
}

# sparkline_v <array-name> <width> [max] [colour]
sparkline_v() {
  local -n _sa=$1
  local w=$2 max=${3:-0} col=${4:-${C[accent]}} n=${#_sa[@]} i start v out=''
  if ((n == 0)); then rep_v ' ' "$w"; SPARK_OUT=$REP_OUT; return 0; fi
  if ((max <= 0)); then
    max=1
    for v in "${_sa[@]}"; do ((v > max)) && max=$v; done
  fi
  start=$((n - w)); ((start < 0)) && start=0
  if ((n - start < w)); then rep_v ' ' $((w - (n - start))); out=$REP_OUT; fi
  for ((i = start; i < n; i++)); do
    v=$((${_sa[i]:-0} * 8 / max))
    ((v > 8)) && v=8
    ((v < 0)) && v=0
    out+=${GLYPH_BLOCK[v]}
  done
  SPARK_OUT="$col$out${C[reset]}"
  return 0
}

# heat_strip_v <array-name> <width>
# One coloured cell per element. Used for per-core CPU when a box has more cores
# than we have rows for individual bars -- 64 cores still fit in 64 columns.
heat_strip_v() {
  local -n _ha=$1
  local w=$2 n=${#_ha[@]} i v step out=''
  if ((n == 0)); then rep_v ' ' "$w"; HEAT_OUT=$REP_OUT; return 0; fi
  for ((i = 0; i < n && i < w; i++)); do
    v=${_ha[i]:-0}
    step=$((v * 8 / 100))
    ((step < 1)) && step=1
    ((step > 8)) && step=8
    grad_v "$v"
    out+="$GRAD_OUT${GLYPH_BLOCK[step]}"
  done
  HEAT_OUT="$out${C[reset]}"
  return 0
}

# braille_plot <array-name> <cells-wide> <cells-high> <max> <colour> [flip] [gradient]
# Rows land in BR_OUT, top first. flip=1 grows downward from the top, which is
# what lets the rx/tx pair mirror around a shared axis and read at a glance.
# gradient=1 colours each row by its height, so the plot reads as a vertical
# ramp instead of a flat block -- the single biggest visual difference between
# the `best` and `performance` profiles, and it costs h cached lookups.
#
# Two optimisations matter here, because this is the most expensive thing in a
# frame (a 150-column graph is 292 dot columns):
#
#   * only the cells a column actually reaches are visited. Iterating all `h`
#     rows and skipping empties cost 6 iterations per column regardless of the
#     value; starting at the first reachable cell costs ceil(hh/4).
#   * the zero-fill template is cached and copied rather than rebuilt with a
#     loop. Copying an 876-element array is one bash operation; filling it
#     element by element is 876.
declare -a BR_OUT=()
declare -a _BR_ZERO=()
_BR_SIZE=''
braille_plot() {
  local -n _pv=$1
  local w=$2 h=$3 max=$4 col=$5 flip=${6:-0} gradient=${7:-0}
  local dotw=$((w * 2)) doth=$((h * 4))
  local n=${#_pv[@]} start off i x cx base val hh nfill cy edge line rowcol pct
  local -a cells=()
  BR_OUT=()
  ((w <= 0 || h <= 0)) && return 0
  ((max <= 0)) && max=1
  start=$((n - dotw)); ((start < 0)) && start=0
  off=$((dotw - (n - start))); ((off < 0)) && off=0

  if [[ $_BR_SIZE != "$h:$w" ]]; then
    _BR_ZERO=()
    for ((i = 0; i < h * w; i++)); do _BR_ZERO[i]=0; done
    _BR_SIZE="$h:$w"
  fi
  cells=("${_BR_ZERO[@]}")

  for ((x = off; x < dotw; x++)); do
    # The array subscript is itself an arithmetic context, so indexing directly
    # avoids a separate $(( )) for the sample offset.
    val=${_pv[start + x - off]:-0}
    ((val <= 0)) && continue
    # Fused into one arithmetic command deliberately: bash charges per (( ))
    # invocation and this body runs once per dot column, 292 times per graph on a
    # 150-column terminal. Splitting these into separate commands measurably
    # costs more than the arithmetic itself.
    ((hh = val * doth / max,
      hh = hh > doth ? doth : hh,
      hh = hh < 1 ? 1 : hh,
      cx = x / 2,
      base = (x % 2) * 5))
    if ((flip)); then
      edge=$(((hh - 1) / 4))
      for ((cy = 0; cy <= edge; cy++)); do
        ((nfill = hh - cy * 4,
          nfill = nfill > 4 ? 4 : nfill,
          cells[cy * w + cx] |= BMASK_TOP[base + nfill]))
      done
    else
      ((edge = h - 1 - (hh - 1) / 4, edge = edge < 0 ? 0 : edge))
      for ((cy = edge; cy < h; cy++)); do
        ((nfill = hh - (h - 1 - cy) * 4,
          nfill = nfill > 4 ? 4 : nfill,
          cells[cy * w + cx] |= BMASK_BOT[base + nfill]))
      done
    fi
  done

  for ((cy = 0; cy < h; cy++)); do
    line=''
    base=$((cy * w))
    for ((x = 0; x < w; x++)); do line+=${BRAILLE[cells[base + x]]}; done
    if ((gradient && h > 1)); then
      # Row 0 is the top. For a normal plot the top is the high end; for a
      # flipped plot the far row is, so the ramp has to invert with it.
      if ((flip)); then pct=$((cy * 100 / (h - 1)))
      else pct=$(((h - 1 - cy) * 100 / (h - 1))); fi
      grad_v "$pct"
      rowcol=$GRAD_OUT
    else
      rowcol=$col
    fi
    BR_OUT+=("$rowcol$line${C[reset]}")
  done
  return 0
}

# time_axis_v <cells-wide> <seconds-per-sample> <samples-per-cell>
# A labelled time ruler for under a graph, so "the spike was a while ago" becomes
# "the spike was four minutes ago".
TIME_AXIS=''
time_axis_v() {
  local w=$1 secs=$2 per=$3
  local span=$((w * per * secs))
  ((span <= 0 || w < 20)) && { rep_v "$G_HLINE" "$w"; TIME_AXIS="${C[border]}$REP_OUT${C[reset]}"; return 0; }
  local -a marks=()
  local i frac lbl
  # Four evenly spaced marks reading right-to-left from "now".
  for i in 3 2 1; do
    frac=$((span * i / 4))
    if ((frac >= 3600)); then printf -v lbl -- '-%dh' $((frac / 3600))
    elif ((frac >= 60)); then printf -v lbl -- '-%dm' $((frac / 60))
    else printf -v lbl -- '-%ds' "$frac"; fi
    marks+=("$lbl")
  done
  local out='' seg=$((w / 4)) k
  printf -v lbl -- '-%s' "$( ((span >= 3600)) && printf '%dh' $((span / 3600)) || printf '%dm' $((span / 60)) )"
  out="${C[dim]}$lbl${C[reset]}"
  vlen "$out"
  local used=$VLEN
  for k in 0 1 2; do
    rep_v "$G_HLINE" $((seg - ${#marks[k]} - 1))
    out+="${C[border]}$REP_OUT${C[reset]} ${C[dim]}${marks[k]}${C[reset]}"
    ((used += seg))
  done
  rep_v "$G_HLINE" $((w - used - 4))
  out+="${C[border]}$REP_OUT${C[reset]} ${C[dim]}now${C[reset]}"
  vlen "$out"
  ((VLEN < w)) && { rep_v "$G_HLINE" $((w - VLEN)); out+="${C[border]}$REP_OUT${C[reset]}"; }
  TIME_AXIS=$out
  return 0
}

# arr_stats_v <array-name> <window> -- min/avg/max of the visible window, so the
# graph's shape gets actual numbers attached to it.
ARR_MIN=0 ARR_AVG=0
arr_stats_v() {
  local -n _sa=$1
  local w=$2 n=${#_sa[@]} i start sum=0 cnt=0 v
  ARR_MIN=0 ARR_AVG=0 ARR_MAX=0
  start=$((n - w)); ((start < 0)) && start=0
  for ((i = start; i < n; i++)); do
    v=${_sa[i]:-0}
    ((cnt == 0 || v < ARR_MIN)) && ARR_MIN=$v
    ((v > ARR_MAX)) && ARR_MAX=$v
    ((sum += v)); ((cnt++))
  done
  ((cnt > 0)) && ARR_AVG=$((sum / cnt))
  return 0
}

# ---------------------------------------------------------------------------
# panels
# ---------------------------------------------------------------------------
# A panel is an array of lines at a fixed visible width. panel_open/panel_close
# draw the frame, panel_row pads content into it, hstack composes panels side by
# side. That composition step is what makes the multi-column layout possible
# without absolute cursor addressing per widget.

# panel_open <out-array> <width> <title> [right-text] [accent]
panel_open() {
  local -n _po=$1
  local w=$2 title=$3 right=${4:-} acc=${5:-${C[accent]}}
  local head tail fill used
  head="${C[border]}$G_TL$G_HLINE${C[reset]} $acc${C[bold]}$title${C[reset]} "
  vlen "$head"; used=$VLEN
  if [[ -n $right ]]; then
    tail=" ${C[dim]}$right${C[reset]} ${C[border]}$G_HLINE$G_TR${C[reset]}"
  else
    tail="${C[border]}$G_HLINE$G_TR${C[reset]}"
  fi
  vlen "$tail"
  fill=$((w - used - VLEN))
  if ((fill < 0)); then
    tail="${C[border]}$G_HLINE$G_TR${C[reset]}"
    vlen "$tail"
    fill=$((w - used - VLEN))
  fi
  ((fill < 0)) && fill=0
  rep_v "$G_HLINE" "$fill"
  _po=("$head${C[border]}$REP_OUT${C[reset]}$tail")
  return 0
}

# panel_row <out-array> <width> <content>
panel_row() {
  local -n _po=$1
  fit_v "$3" $(($2 - 4))
  _po+=("${C[border]}$G_VLINE${C[reset]} $FIT_OUT ${C[border]}$G_VLINE${C[reset]}")
  return 0
}

# panel_raw <out-array> <width> <content>  -- content already padded to width-4
panel_raw() {
  local -n _po=$1
  _po+=("${C[border]}$G_VLINE${C[reset]} $3 ${C[border]}$G_VLINE${C[reset]}")
  return 0
}

# panel_close <out-array> <width>
panel_close() {
  local -n _po=$1
  rep_v "$G_HLINE" $(($2 - 2))
  _po+=("${C[border]}$G_BL$REP_OUT$G_BR${C[reset]}")
  return 0
}

# hstack <out-array> <gap> <arr-name>:<width> ...
hstack() {
  local -n _hout=$1
  local gap=$2
  shift 2
  local -a names=() widths=()
  local spec maxh=0 i r line gapstr
  for spec in "$@"; do
    names+=("${spec%%:*}")
    widths+=("${spec##*:}")
  done
  for i in "${!names[@]}"; do
    local -n _hp=${names[i]}
    ((${#_hp[@]} > maxh)) && maxh=${#_hp[@]}
    unset -n _hp
  done
  rep_v ' ' "$gap"; gapstr=$REP_OUT
  _hout=()
  for ((r = 0; r < maxh; r++)); do
    line=''
    for i in "${!names[@]}"; do
      local -n _hp=${names[i]}
      ((i > 0)) && line+=$gapstr
      if ((r < ${#_hp[@]})); then
        pad_v "${_hp[r]}" "${widths[i]}"
        line+=$PAD_OUT
      else
        rep_v ' ' "${widths[i]}"
        line+=$REP_OUT
      fi
      unset -n _hp
    done
    _hout+=("$line")
  done
  return 0
}

# kv_v <label> <value> <label-width> [value-colour]
kv_v() {
  pad_v "$1" "$3"
  KV_OUT="${C[dim]}$PAD_OUT${4:-${C[fg]}}$2${C[reset]}"
  return 0
}

# status_dot_v <state> [text] -- coloured bullet, state drives the colour.
# ${2-$1} not ${2:-$1}: passing an explicitly empty string means "bullet only".
# With :- an empty argument falls back to the state name and prints it twice.
STATUS_OUT=''
status_dot_v() {
  local c
  case $1 in
    ok | active | running | up | listening) c=${C[ok]} ;;
    warn | degraded | activating | reloading) c=${C[warn]} ;;
    crit | failed | dead | down | inactive) c=${C[crit]} ;;
    *) c=${C[dim]} ;;
  esac
  local txt=${2-$1}
  if [[ -z $txt ]]; then STATUS_OUT="$c$G_DOT${C[reset]}"
  else STATUS_OUT="$c$G_DOT $txt${C[reset]}"; fi
  return 0
}

# ---------------------------------------------------------------------------
# printing wrappers -- one-shot CLI paths only, never inside the render loop
# ---------------------------------------------------------------------------
rep() { rep_v "$@"; printf '%s' "$REP_OUT"; }
pad() { pad_v "$@"; printf '%s' "$PAD_OUT"; }
fit() { fit_v "$@"; printf '%s' "$FIT_OUT"; }
bar() { bar_v "$@"; printf '%s' "$BAR_OUT"; }
grad() { grad_v "$@"; printf '%s' "$GRAD_OUT"; }
kv() { kv_v "$@"; printf '%s' "$KV_OUT"; }
status_dot() { status_dot_v "$@"; printf '%s' "$STATUS_OUT"; }

# arr_max_v <array-name> <window> -- max of the last <window> samples, in
# ARR_MAX. Graphs scale to what is on screen, not to all-time history.
ARR_MAX=0
arr_max_v() {
  local -n _ma=$1
  local w=$2 n=${#_ma[@]} i start
  ARR_MAX=0
  start=$((n - w)); ((start < 0)) && start=0
  for ((i = start; i < n; i++)); do ((${_ma[i]:-0} > ARR_MAX)) && ARR_MAX=${_ma[i]}; done
  return 0
}

ui_init() {
  ui_locale
  glyphs_init
  bmask_init
  return 0
}
