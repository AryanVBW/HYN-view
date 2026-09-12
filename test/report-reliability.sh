#!/usr/bin/env bash
# Isolated compact-history durability and report arithmetic regressions.
set -uo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT" HYN_VAR="$WORK/state" HYN_ETC="$WORK/etc"
export XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/user-state" HYN_CONFIG=''
mkdir -p "$HYN_VAR" "$HYN_ETC"
source "$HYN_LIB/core.sh"
source "$HYN_LIB/report.sh"
is_root() { return 0; }
cfg_load
unset EPOCHSECONDS
EPOCHSECONDS=1000000
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else printf 'FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); fi; }
f=$(metrics_file)
row() {
  printf '%s\t%s\t0\t0\t%s\t0\t100\t20\t0\t0\t%s\t%s\t0\t0\t0\t1\t100\t10\t20\t0\t%s\t%s\teth0' \
    "$1" "$2" "$3" "${6:-100}" "${7:-50}" "$4" "$5"
  [[ -z ${8:-} ]] || printf '\t%s\t%s' "$8" "$9"
  printf '\n'
}

row 998800 90 90 1000 boot-a >"$f"
row 998860 90 90 1000 boot-a >>"$f"
row 998920 10 10 2000 boot-a >>"$f"
row 999700 90 90 2000 boot-a >>"$f"
row 999760 90 90 4000 boot-b >>"$f"
row 999820 90 90 - boot-b >>"$f"
row 999880 90 90 4000 boot-b >>"$f"
row 999940 90 90 4000 boot-b >>"$f"
check 'report aggregates complete samples' 'report_aggregate 24 && [[ $R_ROWS == 8 ]]'
check 'covered duration excludes offline gaps and reboot intervals' '[[ ${R[observed_s]} == 300 && ${R[gap_s]} == 840 && ${R[gaps]} == 2 ]]'
check 'busy duration uses observed time instead of configured minutes per row' '[[ ${R[cpu_busy_s2]} == 540 && ${R[mem_busy_s2]} == 540 && ${R[cpu_busy_min]} == 4 ]]'
check 'power integration excludes unavailable sensors and unobserved hours' '[[ ${R[pwr_dws2]} == 780000 && ${R[pwr_span_s]} == 180 && ${R[pwr_mwh]} == 10833 ]]'

row 999880 10 50 0 boot-a >"$f"
row 999940 20 60 0 boot-a >>"$f"
printf '999945\t99\t0\n' >>"$f"
bad=$(row 999950 30 70 0 boot-a)
printf '%s\n' "${bad/$'\t30\t'/$'\t\t'}" >>"$f"
printf '%s\n' "${bad/$'\t30\t'/$'\t1+2\t'}" >>"$f"
row 1000030 99 99 1000 boot-a >>"$f"
row 999900 99 99 1000 boot-a >>"$f"
check 'partial rows, empty fields and arithmetic expressions never become zero samples' 'report_aggregate 24 && [[ $R_ROWS == 2 && ${R[cpu_avg]} == 15 && ${R[invalid_rows]} == 3 ]]'
check 'future and out-of-order rows are counted and excluded' '[[ ${R[future_rows]} == 1 && ${R[out_of_order_rows]} == 1 && ${R[skipped_rows]} == 5 ]]'
check 'measured zero power remains a valid sensor reading' '[[ ${R[pwr_n]} == 2 && ${R[pwr_span_s]} == 60 && ${R[pwr_mwh]} == 0 ]]'

legacy=$(row 999900 10 50 - boot-a)
legacy=${legacy%$'\t'*}; legacy=${legacy%$'\t'*}; legacy=${legacy%$'\t'*}
printf '%s\n' "$legacy" >"$f"
check 'valid historical twenty-column rows remain readable' 'report_aggregate 24 && [[ $R_ROWS == 1 && ${R[pwr_n]} == 0 && ${R[cpu_busy_min]} == 0 ]]'
check 'a single sample does not invent a whole sampling interval of activity' '[[ ${R[observed_s]} == 0 && ${R[pwr_span_s]} == 0 ]]'

row 990000 90 90 1000 boot-a >"$f"
row 993600 90 90 1000 boot-a >>"$f"
CFG[record_interval_min]=60
check 'sparse hourly samples do not imply an hour of continuous energy use' 'report_aggregate 24 && [[ ${R[observed_s]} == 0 && ${R[pwr_span_s]} == 0 && ${R[gap_s]} == 3600 ]]'
CFG[record_interval_min]=5

row 999800 10 50 - boot-a 18446744073709551000 0 >"$f"
row 999850 10 50 - boot-a 18446744073709551615 10 >>"$f"
row 999900 10 50 - boot-b 0 0 >>"$f"
row 999950 10 50 - boot-b 18446744073709551615 20 >>"$f"
check 'uint64 samples and totals above uint64 remain exact across resets' 'report_aggregate 24 && [[ ${R[rx_bytes]} == 18446744073709552230 && ${R[tx_bytes]} == 30 && ${R[network_resets]} == 1 ]]'
check 'large byte totals render exactly without signed overflow' '_report_size_v "${R[rx_bytes]}" && [[ $FMT_OUT == "18446744073709552230 B" ]]'
(
  for module in ui net collect highway speedtest notify; do source "$HYN_LIB/$module.sh"; done
  net_identity() { return 0; }
  report_speed() { return 1; }
  HOSTNAME_S=fixture-host CPU_COUNT=1 UPTIME_S=86400
  CFG[highway_track]=off
  report_text 24 >"$WORK/large-report.txt"
  report_html 24 >"$WORK/large-report.html"
)
check 'text report retains the complete large transfer count' 'grep -q "18446744073709552230 B down / 30 B up" "$WORK/large-report.txt"'
check 'HTML headline sums receive and send with exact arithmetic' 'grep -q "18446744073709552260 B" "$WORK/large-report.html" && grep -q "18446744073709552230 B" "$WORK/large-report.html"'

row 999997 10 50 - boot-a 100 50 7 100000 >"$f"
row 999998 10 50 - boot-a 300 100 7 101200 >>"$f"
row 999998 10 50 - boot-a 200 80 7 101100 >>"$f"
row 999999 10 50 - boot-a 400 120 7 102000 >>"$f"
check 'a late older sample within the same second cannot double count traffic' 'report_aggregate 24 && [[ ${R[rx_bytes]} == 300 && ${R[tx_bytes]} == 70 && ${R[out_of_order_rows]} == 1 && ${R[network_resets]} == 0 ]]'
row 1000000 10 50 - boot-a 9000 4000 8 103000 >>"$f"
row 1000000 10 50 - boot-a 10000 4500 8 103500 >>"$f"
check 'a recreated NIC with the same name cannot inherit the old counter baseline' 'report_aggregate 24 && [[ ${R[rx_bytes]} == 1300 && ${R[tx_bytes]} == 570 && ${R[network_resets]} == 1 ]]'
full_disk=$(row 999999 10 50 - boot-a)
printf '%s\n' "${full_disk/$'\t100\t20\t'/$'\t100\t101\t'}" >"$f"
check 'a real df percentage over one hundred remains in the report' 'report_aggregate 24 && [[ $R_ROWS == 1 && ${R[disk_max]} == 101 ]]'
printf 'broken\n999999\t10\n' >"$f"
check 'an invalid-only file clears prior report charts and data' '! report_aggregate 24 && [[ $R_ROWS == 0 && ${#RH_CPU[@]} == 0 && ${R[invalid_rows]} == 2 ]]'

# A fresh process needs baseline SNMP and Highway process counters before the
# sampling wait, then must use actual elapsed time and persist lineage metadata.
(
  export HYN_PROC="$WORK/proc" HYN_SYS="$WORK/sys"
  mkdir -p "$HYN_PROC/sys/kernel/random" "$HYN_SYS/class/net/eth0"
  printf 'boot-record\n' >"$HYN_PROC/sys/kernel/random/boot_id"
  printf '8\n' >"$HYN_SYS/class/net/eth0/ifindex"
  declare -A NET_RX=([eth0]=400) NET_TX=([eth0]=100) NET_RXR=([eth0]=10) NET_TXR=([eth0]=5)
  declare -A MP_PCT=() LAT_MS=() HW_RESTARTS=()
  declare -a MOUNTS=() HW_UNITS=()
  CPU_PCT=10 CPU_STEAL=0 CPU_IOWAIT=0 MEM_PCT=50 SWAP_PCT=0 NET_RETRANS_PM=0
  PWR_INPUT_DW=1000 NET_WAN=eth0 LOAD1=0.0 clocks=0
  CFG[highway_track]=on
  sample_clock_ms_v() { clocks=$((clocks + 1)); SAMPLE_CLOCK_MS=$((clocks == 1 ? 1000 : 2300)); }
  net_sample() { NET_SAMPLE_MONO_MS=$SAMPLE_CLOCK_MS; }
  net_snmp() { printf 'snmp:%s\n' "$1" >>"$WORK/sample-order"; }
  hw_process() { printf 'hw-seed:%s\n' "$1" >>"$WORK/sample-order"; }
  hw_sample() { printf 'hw:%s\n' "$1" >>"$WORK/sample-order"; }
  sleep() { printf 'sleep:%s\n' "$1" >>"$WORK/sample-order"; }
  for fn in cpu_sample power_read mem_sample sys_sample psi_sample disk_usage net_conntrack net_latency_read net_retrans_permille cloud_payload_v local_store_snapshot; do
    eval "$fn() { return 0; }"
  done
  _metrics_append_rows() { printf '%s\n' "$3" >"$WORK/recorded-row"; }
  record_sample
)
check 'fresh SNMP and Highway rates are seeded before the wait' '[[ $(<"$WORK/sample-order") == $'"'"'snmp:0\nhw-seed:0\nsleep:1\nsnmp:1300\nhw:1300'"'"' ]]'
check 'recorded samples carry interface generation and actual monotonic timestamp' '_metrics_row_v "$(<"$WORK/recorded-row")" && [[ ${#METRIC_FIELDS[@]} == 25 && ${METRIC_FIELDS[21]} == boot-record && ${METRIC_FIELDS[23]} == 8 && ${METRIC_FIELDS[24]} == 2300 ]]'

# The same descriptor-held advisory lock as util-linux, for macOS test hosts.
if ! command -v flock >/dev/null && command -v python3 >/dev/null; then
  flock() {
    python3 - "$@" <<'PY'
import fcntl, sys, time
deadline = time.monotonic() + (float(sys.argv[2]) if sys.argv[1] == '-w' else 0)
while True:
    try:
        fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline: sys.exit(1)
        time.sleep(.01)
PY
  }
  _HAVE[flock]=1
fi
if have flock; then
  printf '1\texpired\n999900\tretained\n' >"$f"
  pids=()
  for i in {1..12}; do _metrics_append_rows "$f" 86400 "1000000"$'\t'"writer-$i" & pids+=("$!"); done
  writers_ok=1
  for pid in "${pids[@]}"; do wait "$pid" || writers_ok=0; done
  check 'concurrent rotation and writes preserve every committed row' '[[ $writers_ok == 1 && $(wc -l <"$f") -eq 13 && $(sort -u "$f" | wc -l) -eq 13 ]] && ! grep -q expired "$f"'
  before=$(<"$f")
  (
    _metrics_sync() { return 1; }
    ! _metrics_append_rows "$f" 86400 "1000000"$'\t'"uncommitted"
  )
  check 'failed durable flush does not replace committed history' '[[ $(<"$f") == "$before" ]]'
  check 'failed transactions release their lock for the next writer' '_metrics_append_rows "$f" 86400 "1000000"$'"'"'\t'"'"'"retry" && [[ $(wc -l <"$f") -eq 14 ]]'
  (
    cat() { return 1; }
    ! _metrics_append_rows "$f" 86400 "1000000"$'\t'"lost-copy"
  )
  check 'an unreadable prior file cannot be replaced by only the new row' '[[ $(wc -l <"$f") -eq 14 ]] && ! grep -q lost-copy "$f"'
  printf '1000000\tpartial' >"$f"
  check 'a legacy interrupted tail cannot corrupt the next committed row' '_metrics_append_rows "$f" 86400 "1000000"$'"'"'\t'"'"'"complete" && [[ $(wc -l <"$f") -eq 2 ]]'
  check 'compact history is private to its owner' '[[ $(find "$f" -perm -004 | wc -l) -eq 0 ]]'
  printf 'interrupted temporary file\n' >"$f.pending.abandoned"
  check 'the next writer removes only unpublished crash leftovers' '_metrics_append_rows "$f" 86400 "1000000"$'"'"'\t'"'"'"after-crash" && [[ ! -e $f.pending.abandoned && -f $f.lock ]]'
  before=$(<"$f")
  (
    mv() { return 1; }
    ! _metrics_append_rows "$f" 86400 "1000000"$'\t'"failed-rename"
  )
  check 'failed atomic publication preserves the prior committed file' '[[ $(<"$f") == "$before" ]]'
  if (
    flushes=0
    _metrics_sync() { flushes=$((flushes + 1)); ((flushes < 2)); }
    _metrics_append_rows "$f" 86400 "1000000"$'\t'"visible-not-flushed"
  ); then flush_failed=0; else flush_failed=1; fi
  check 'post-rename directory flush failure is surfaced with the row still readable' '[[ $flush_failed == 1 ]] && grep -q visible-not-flushed "$f"'
else
  printf 'FAIL operating-system advisory lock is unavailable\n'; FAIL=$((FAIL + 1))
fi
printf '%s checks passed; %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
