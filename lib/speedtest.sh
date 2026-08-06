#!/usr/bin/env bash
# hyn-view :: throughput measurement + history
#
# A speed test on a live relay node is a hostile act if you are careless about
# it: saturating the uplink to measure the uplink can make the node miss the
# work it is paid for. So this is deliberately conservative:
#
#   * bounded by bytes AND by wall clock (speedtest_down_mb / _timeout);
#   * skipped outright if the link is already busy (speedtest_guard_pct), and
#     the skip is recorded so the gap in history has a stated reason;
#   * scheduled with RandomizedDelaySec, because a lot of operators run the same
#     installer and a fleet all testing at 06:00 is a self-inflicted outage;
#   * uses whatever real speedtest client is installed before falling back to
#     curl against Cloudflare's endpoints, so no new dependency is required.
#
# History is TSV, not JSON: `read` parses it with no dependency and no fork.
# Columns: epoch  down_bps  up_bps  latency_us  jitter_us  provider  iface  note

ST_FILE=''
st_file_v() {
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null
  ST_FILE="$STATE_DIR/speedtest.tsv"
  return 0
}
st_file() { st_file_v; printf '%s' "$ST_FILE"; }

ST_DOWN=0 ST_UP=0 ST_LAT=0 ST_JIT=0 ST_PROVIDER='' ST_NOTE='' ST_TS=0

# ---------------------------------------------------------------------------
# provider selection
# ---------------------------------------------------------------------------
st_provider() {
  local want=${CFG[speedtest_provider]}
  case $want in
    ookla | speedtest-cli | curl | iperf3) printf '%s' "$want"; return 0 ;;
  esac
  # Ookla's client reports the truest number; speedtest-cli is close; curl
  # against a CDN is a floor, not a ceiling, and the panel labels it as such.
  if have speedtest && speedtest --version 2>/dev/null | grep -qi ookla; then
    printf ookla
  elif have speedtest-cli; then
    printf speedtest-cli
  elif have curl; then
    printf curl
  else
    printf none
  fi
  return 0
}

# ---------------------------------------------------------------------------
# busy-link guard
# ---------------------------------------------------------------------------
# Samples the WAN counters a second apart and compares against the best result
# we have ever recorded. Without a baseline we cannot judge "busy", so the first
# ever test always runs.
ST_BUSY_PCT=0
st_link_busy() {
  local iface=$1 guard=$2 baseline=$3
  local a=0 b=0 line ifn rest
  local -a f=()
  ((baseline <= 0)) && return 1
  ((guard <= 0)) && return 1
  while IFS= read -r line; do
    [[ $line == *:* ]] || continue
    ifn=${line%%:*}; ifn=${ifn//[[:space:]]/}
    [[ $ifn == "$iface" ]] || continue
    rest=${line#*:}; f=($rest)
    a=$((${f[0]} + ${f[8]}))
  done <"$HYN_PROC/net/dev"
  sleep 1
  while IFS= read -r line; do
    [[ $line == *:* ]] || continue
    ifn=${line%%:*}; ifn=${ifn//[[:space:]]/}
    [[ $ifn == "$iface" ]] || continue
    rest=${line#*:}; f=($rest)
    b=$((${f[0]} + ${f[8]}))
  done <"$HYN_PROC/net/dev"
  local rate=$((b - a))
  ((rate < 0)) && rate=0
  ST_BUSY_PCT=$((rate * 100 / baseline))
  ((ST_BUSY_PCT > guard))
}

# Best download ever recorded, as the capacity baseline for the guard.
st_baseline() {
  local f ts down rest best=0
  st_file_v; f=$ST_FILE
  [[ -r $f ]] || { printf 0; return 0; }
  while IFS=$'\t' read -r ts down rest; do
    [[ $down =~ ^[0-9]+$ ]] || continue
    ((down > best)) && best=$down
  done <"$f"
  printf '%d' "$best"
}

# ---------------------------------------------------------------------------
# curl-based measurement (no dependencies beyond curl)
# ---------------------------------------------------------------------------
ST_CF_DOWN='https://speed.cloudflare.com/__down?bytes='
ST_CF_UP='https://speed.cloudflare.com/__up'

# Median of 5 connect times, plus spread as jitter. Median rather than mean so a
# single scheduling hiccup does not define the node's reported latency.
_st_curl_latency() {
  local i v out
  local -a samples=()
  for i in 1 2 3 4 5; do
    out=$(curl -fsS -o /dev/null --max-time 5 -w '%{time_connect}' \
      "${ST_CF_DOWN}1000" 2>/dev/null) || continue
    parse_fixed3_v "$out"
    samples+=("$((FIX3 * 1000))")
  done
  ((${#samples[@]} == 0)) && { ST_LAT=0 ST_JIT=0; return 1; }
  local n=${#samples[@]} j t
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      ((samples[j] < samples[i])) && { t=${samples[i]}; samples[i]=${samples[j]}; samples[j]=$t; }
    done
  done
  ST_LAT=${samples[n / 2]}
  ST_JIT=$((samples[n - 1] - samples[0]))
  return 0
}

st_run_curl() {
  local mb_down=$1 mb_up=$2 tmo=$3
  local bytes out
  ST_PROVIDER='curl/cloudflare'
  _st_curl_latency

  bytes=$((mb_down * 1000000))
  out=$(curl -fsS -o /dev/null --max-time "$tmo" -w '%{speed_download}' \
    "${ST_CF_DOWN}${bytes}" 2>/dev/null) || out=0
  ST_DOWN=${out%%.*}
  [[ $ST_DOWN =~ ^[0-9]+$ ]] || ST_DOWN=0

  if ((mb_up > 0)); then
    bytes=$((mb_up * 1000000))
    # Body from /dev/zero via head: no temp file, no dd, and curl does not
    # compress request bodies so incompressible data buys nothing here.
    out=$(head -c "$bytes" /dev/zero 2>/dev/null |
      curl -fsS -o /dev/null --max-time "$tmo" -w '%{speed_upload}' \
        -H 'Content-Type: application/octet-stream' \
        --data-binary @- "$ST_CF_UP" 2>/dev/null) || out=0
    ST_UP=${out%%.*}
    [[ $ST_UP =~ ^[0-9]+$ ]] || ST_UP=0
  fi
  ((ST_DOWN > 0))
}

# ---------------------------------------------------------------------------
# external clients
# ---------------------------------------------------------------------------
# Both emit JSON. Rather than take a JSON parser dependency for four numbers,
# pull the fields with parameter expansion -- these are flat, machine-generated
# documents with stable key names, not arbitrary user input.
_json_num() {
  local doc=$1 key=$2 v
  [[ $doc == *"\"$key\":"* ]] || return 1
  v=${doc#*\"$key\":}
  v=${v%%,*}
  v=${v%%\}*}
  v=${v//[^0-9.]/}
  [[ -n $v ]] || return 1
  printf '%s' "$v"
}

st_run_ookla() {
  local out v
  ST_PROVIDER='ookla'
  out=$(speedtest --format=json --accept-license --accept-gdpr 2>/dev/null) || return 1
  # Ookla reports bandwidth in bytes/sec.
  v=$(_json_num "${out#*\"download\":}" bandwidth) && ST_DOWN=${v%%.*}
  v=$(_json_num "${out#*\"upload\":}" bandwidth) && ST_UP=${v%%.*}
  v=$(_json_num "${out#*\"ping\":}" latency) && { parse_fixed3_v "$v"; ST_LAT=$((FIX3 * 1000)); }
  v=$(_json_num "${out#*\"ping\":}" jitter) && { parse_fixed3_v "$v"; ST_JIT=$((FIX3 * 1000)); }
  [[ $ST_DOWN =~ ^[0-9]+$ ]] || ST_DOWN=0
  [[ $ST_UP =~ ^[0-9]+$ ]] || ST_UP=0
  ((ST_DOWN > 0))
}

st_run_cli() {
  local out v
  ST_PROVIDER='speedtest-cli'
  out=$(speedtest-cli --json 2>/dev/null) || return 1
  # speedtest-cli reports bits/sec; normalise to bytes/sec.
  v=$(_json_num "$out" download) && ST_DOWN=$((${v%%.*} / 8))
  v=$(_json_num "$out" upload) && ST_UP=$((${v%%.*} / 8))
  v=$(_json_num "$out" ping) && { parse_fixed3_v "$v"; ST_LAT=$((FIX3 * 1000)); }
  [[ $ST_DOWN =~ ^[0-9]+$ ]] || ST_DOWN=0
  [[ $ST_UP =~ ^[0-9]+$ ]] || ST_UP=0
  ((ST_DOWN > 0))
}

# ---------------------------------------------------------------------------
# orchestration
# ---------------------------------------------------------------------------
# st_run <force> -- force=1 ignores the busy-link guard (manual `hyn speedtest`).
st_run() {
  local force=${1:-0} prov iface baseline guard
  ST_DOWN=0 ST_UP=0 ST_LAT=0 ST_JIT=0 ST_NOTE='' ST_TS=${EPOCHSECONDS:-0}

  net_sample
  iface=${NET_WAN:-unknown}
  guard=${CFG[speedtest_guard_pct]}
  [[ $guard =~ ^[0-9]+$ ]] || guard=25

  if ((force == 0)); then
    baseline=$(st_baseline)
    if st_link_busy "$iface" "$guard" "$baseline"; then
      ST_NOTE="skipped: link ${ST_BUSY_PCT}% busy (guard ${guard}%)"
      st_append "$iface"
      return 2
    fi
  fi

  prov=$(st_provider)
  [[ $prov == none ]] && { ST_NOTE='no provider: install curl'; st_append "$iface"; return 1; }

  local ok=1
  case $prov in
    ookla) st_run_ookla || ok=0 ;;
    speedtest-cli) st_run_cli || ok=0 ;;
    curl) st_run_curl "${CFG[speedtest_down_mb]}" "${CFG[speedtest_up_mb]}" "${CFG[speedtest_timeout]}" || ok=0 ;;
  esac

  # A configured client that failed still leaves curl as a usable answer, but
  # only when the provider was auto-selected -- an explicit choice is honoured.
  if ((ok == 0)) && [[ $prov != curl && ${CFG[speedtest_provider]} == auto ]] && have curl; then
    ST_NOTE="$prov failed, fell back to curl"
    st_run_curl "${CFG[speedtest_down_mb]}" "${CFG[speedtest_up_mb]}" "${CFG[speedtest_timeout]}" && ok=1
  fi
  ((ok == 0)) && [[ -z $ST_NOTE ]] && ST_NOTE="$prov failed"

  st_append "$iface"
  ((ok == 1))
}

st_append() {
  local iface=$1 f tmp n keep
  st_file_v; f=$ST_FILE
  [[ -n $f ]] || return 1
  keep=${CFG[speedtest_history]}
  [[ $keep =~ ^[0-9]+$ ]] || keep=90
  local row
  printf -v row '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$ST_TS" "$ST_DOWN" "$ST_UP" "$ST_LAT" "$ST_JIT" "${ST_PROVIDER:-none}" "$iface" "${ST_NOTE:-ok}"
  {
    if [[ -r $f ]]; then
      local -a lines=()
      local l
      while IFS= read -r l; do lines+=("$l"); done <"$f"
      ((${#lines[@]} >= keep)) && lines=("${lines[@]: -$((keep - 1))}")
      ((${#lines[@]} > 0)) && printf '%s\n' "${lines[@]}"
    fi
    printf '%s\n' "$row"
  } >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  return 0
}

# ---------------------------------------------------------------------------
# history for the panel
# ---------------------------------------------------------------------------
declare -a ST_H_TS=() ST_H_DOWN=() ST_H_UP=() ST_H_LAT=() ST_H_NOTE=()
ST_LAST_TS=0 ST_LAST_DOWN=0 ST_LAST_UP=0 ST_LAST_LAT=0 ST_LAST_JIT=0
ST_LAST_NOTE='' ST_LAST_PROV=''
ST_READ_LAST=0

st_history_read() {
  local force=${1:-0} now=${EPOCHSECONDS:-0} f
  ((force == 0 && ST_READ_LAST > 0 && now - ST_READ_LAST < 20)) && return 0
  ST_READ_LAST=$now
  st_file_v; f=$ST_FILE
  [[ -r $f ]] || return 1
  ST_H_TS=() ST_H_DOWN=() ST_H_UP=() ST_H_LAT=() ST_H_NOTE=()
  local ts down up lat jit prov iface note
  while IFS=$'\t' read -r ts down up lat jit prov iface note; do
    [[ $ts =~ ^[0-9]+$ ]] || continue
    ST_H_TS+=("$ts") ST_H_DOWN+=("${down:-0}") ST_H_UP+=("${up:-0}")
    ST_H_LAT+=("${lat:-0}") ST_H_NOTE+=("${note:-}")
    # Last row with a real measurement wins; a skipped run must not blank out
    # the last known-good figure the operator is watching.
    if [[ ${down:-0} =~ ^[0-9]+$ ]] && ((down > 0)); then
      ST_LAST_TS=$ts ST_LAST_DOWN=$down ST_LAST_UP=${up:-0}
      ST_LAST_LAT=${lat:-0} ST_LAST_JIT=${jit:-0} ST_LAST_PROV=${prov:-}
    fi
    ST_LAST_NOTE=${note:-}
  done <"$f"
  return 0
}

# OnCalendar for N tests per day. Offset 7 minutes past the hour keeps us clear
# of the cron/backup rush that lands on :00.
st_calendar() {
  local n=${1:-4} hours='' h hh step
  [[ $n =~ ^[0-9]+$ ]] || n=4
  ((n < 1)) && n=1
  ((n > 24)) && n=24
  step=$((24 / n))
  ((step < 1)) && step=1
  # hh is separate from h on purpose: reusing the loop counter for the zero
  # padded form makes bash read "08" as octal on the next increment and abort.
  for ((h = 0; h < 24; h += step)); do
    printf -v hh '%02d' "$h"
    hours+="${hours:+,}$hh"
  done
  printf '*-*-* %s:07:00' "$hours"
}

st_print() {
  local json=${1:-0}
  if ((json)); then
    printf '{"timestamp":%s,"download_bps":%s,"upload_bps":%s,"latency_us":%s,"jitter_us":%s,"provider":"%s","note":"%s"}\n' \
      "$ST_TS" "$ST_DOWN" "$ST_UP" "$ST_LAT" "$ST_JIT" "$ST_PROVIDER" "$ST_NOTE"
    return 0
  fi
  printf 'provider   %s\n' "${ST_PROVIDER:-none}"
  printf 'download   %s\n' "$(fmt_rate "$ST_DOWN")"
  printf 'upload     %s\n' "$(fmt_rate "$ST_UP")"
  if ((ST_LAT > 0)); then printf 'latency    %s ms\n' "$(fmt_fixed "$ST_LAT" 1000 2)"; fi
  if ((ST_JIT > 0)); then printf 'jitter     %s ms\n' "$(fmt_fixed "$ST_JIT" 1000 2)"; fi
  [[ -n $ST_NOTE ]] && printf 'note       %s\n' "$ST_NOTE"
  return 0
}
