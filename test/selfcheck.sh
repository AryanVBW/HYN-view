#!/usr/bin/env bash
# hyn-view :: self-check
#
# Builds a fake /proc and /sys with hand-computed counters, runs the real
# collectors against it, and asserts the exact numbers they should produce. That
# is the part worth testing: a syntax check proves the script parses, it does not
# prove that field 21 of /proc/<pid>/stat is RSS or that a counter delta over
# 1000ms is the rate it claims.
#
#   bash test/selfcheck.sh
#
# No framework, no fixtures directory, no network. Exits non-zero on failure.

set -uo pipefail

HERE=$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)
ROOT=$(cd -P "$HERE/.." && pwd)

PASS=0 FAIL=0
declare -a FAILURES=()

ok() { ((PASS++)); }
bad() {
  ((FAIL++))
  FAILURES+=("$1")
  printf '  FAIL  %s\n' "$1" >&2
}

# eq <label> <expected> <actual>
eq() {
  if [[ $2 == "$3" ]]; then ok; else bad "$1: expected [$2] got [$3]"; fi
}
contains() {
  if [[ $3 == *"$2"* ]]; then ok; else bad "$1: [$3] does not contain [$2]"; fi
}
truthy() {
  if eval "$2" >/dev/null 2>&1; then ok; else bad "$1: expected success from: $2"; fi
}
falsy() {
  if eval "$2" >/dev/null 2>&1; then bad "$1: expected failure from: $2"; else ok; fi
}
section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------------------
# fixture tree
# ---------------------------------------------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hyn-selfcheck.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
FP="$TMP/proc" FS="$TMP/sys"
mkdir -p "$FP" "$FS/class/net/eth0" "$FS/block/sda" "$FP/net" "$FP/pressure" \
  "$FP/sys/net/ipv4" "$FP/sys/net/core" "$FP/sys/net/netfilter" "$FP/sys/fs" \
  "$FP/sys/kernel/random" "$FP/1000" "$FP/1001"

# /proc/stat -- deltas are chosen so every derived percentage is a round number:
# total +1000 jiffies, of which idle+iowait +820, so busy is exactly 18%.
write_stat() {
  cat >"$FP/stat" <<EOF
cpu  $1 100 $2 $3 $4 $5 $6 $7 0 0
cpu0 $((${1} / 2)) 50 $((${2} / 2)) $((${3} / 2)) $((${4} / 2)) $((${5} / 2)) $((${6} / 2)) $((${7} / 2)) 0 0
cpu1 $((${1} / 2)) 50 $((${2} / 2)) $((${3} / 2)) $((${4} / 2)) $((${5} / 2)) $((${6} / 2)) $((${7} / 2)) 0 0
intr $8 1 2 3
ctxt $9
btime 1700000000
processes ${10}
procs_running 2
procs_blocked 0
EOF
}
#          user sys  idle iowait irq soft steal  intr    ctxt   forks
write_stat 1000 500 8000 200 50 25 100 12345 500000 12000

# /proc/net/dev -- rx +2,000,000 B and tx +1,000,000 B over 1000ms.
write_netdev() {
  cat >"$FP/net/dev" <<EOF
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:     100       1    0    0    0     0          0         0      100       1    0    0    0     0       0          0
  eth0: $1 $2 $3 $4 0 0 0 0 $5 $6 $7 $8 0 0 0 0
EOF
}
write_netdev 1000000 1000 0 0 500000 500 0 0

cat >"$FP/meminfo" <<'EOF'
MemTotal:       16384000 kB
MemFree:         1024000 kB
MemAvailable:    8192000 kB
Buffers:          512000 kB
Cached:          4096000 kB
SReclaimable:     256000 kB
Shmem:            128000 kB
Dirty:             12000 kB
SwapTotal:       2048000 kB
SwapFree:        1024000 kB
Committed_AS:    9000000 kB
EOF

# Gateway 192.168.1.1 stored little-endian as 0101A8C0. Flags 0003 has
# RTF_GATEWAY (0x2) set, which is what marks the real default route.
cat >"$FP/net/route" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
eth0	00000000	0101A8C0	0003	0	0	100	00000000	0	0	0
eth0	0001A8C0	00000000	0001	0	0	0	00FFFFFF	0	0	0
EOF

cat >"$FP/net/sockstat" <<'EOF'
sockets: used 200
TCP: inuse 5 orphan 0 tw 12 alloc 20 mem 3
UDP: inuse 2 mem 1
UDPLITE: inuse 0
RAW: inuse 0
FRAG: inuse 0 memory 0
EOF

# st column is field 4. 0A=LISTEN on port 0x1F90 (8080), 01=ESTAB, 06=TIME_WAIT.
cat >"$FP/net/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1
   1: 0100007F:C350 0100007F:1F90 01 00000000:00000000 00:00000000 00000000     0        0 12346 1
   2: 0100007F:C351 0100007F:1F90 06 00000000:00000000 00:00000000 00000000     0        0 12347 1
EOF

write_snmp() {
  cat >"$FP/net/snmp" <<EOF
Ip: Forwarding DefaultTTL InReceives InHdrErrors InDiscards
Ip: 1 64 100000 0 0
Tcp: RtoAlgorithm RtoMin RtoMax MaxConn ActiveOpens PassiveOpens AttemptFails EstabResets CurrEstab InSegs OutSegs RetransSegs InErrs OutRsts InCsumErrors
Tcp: 1 200 120000 -1 100 200 5 3 50 10000 $1 $2 0 10 0
Udp: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors
Udp: 5000 1 0 4000 0 0
EOF
  cat >"$FP/net/netstat" <<EOF
TcpExt: ListenOverflows ListenDrops TCPSynRetrans TCPTimeouts
TcpExt: 0 $3 0 0
EOF
}
write_snmp 20000 100 0

cat >"$FP/pressure/cpu" <<'EOF'
some avg10=1.25 avg60=0.80 avg300=0.30 total=1234567
EOF
cat >"$FP/pressure/io" <<'EOF'
some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
EOF

write_diskstats() {
  printf '   8       0 sda 1000 0 %s 500 800 0 %s 300 0 %s 800 0 0 0 0\n' "$1" "$2" "$3" >"$FP/diskstats"
}
write_diskstats 2000 4000 200

printf '123456.78 987654.32\n' >"$FP/uptime"
printf '0.42 0.38 0.31 2/512 12345\n' >"$FP/loadavg"
printf 'model name\t: Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz\n' >"$FP/cpuinfo"
printf '6.8.0-51-generic\n' >"$FP/sys/kernel/osrelease"
printf 'test-node\n' >"$FP/sys/kernel/hostname"
printf '3800\n' >"$FP/sys/kernel/random/entropy_avail"
printf '1024\t0\t9223372036854775807\n' >"$FP/sys/fs/file-nr"
printf '4200\n' >"$FP/sys/net/netfilter/nf_conntrack_count"
printf '65536\n' >"$FP/sys/net/netfilter/nf_conntrack_max"
printf 'bbr\n' >"$FP/sys/net/ipv4/tcp_congestion_control"
printf 'fq\n' >"$FP/sys/net/core/default_qdisc"
printf '4096\n' >"$FP/sys/net/core/somaxconn"
printf '1000\n' >"$FP/sys/net/core/netdev_max_backlog"
printf '4096\t131072\t6291456\n' >"$FP/sys/net/ipv4/tcp_rmem"

printf '1000\n' >"$FS/class/net/eth0/speed"
printf 'full\n' >"$FS/class/net/eth0/duplex"
printf '1500\n' >"$FS/class/net/eth0/mtu"
printf '1\n' >"$FS/class/net/eth0/carrier"
printf 'up\n' >"$FS/class/net/eth0/operstate"
printf '52:54:00:12:34:56\n' >"$FS/class/net/eth0/address"

# /proc/<pid>/stat. utime is field 14 and rss field 24; the parenthesised comm
# is written with an embedded ')' on purpose, because real ones have them
# ("(sd-pam)") and a naive parse silently shifts every field after it.
write_proc() {
  local pid=$1 comm=$2 ut=$3 st=$4 rss=$5
  printf '%s (%s) S 1 %s %s 0 -1 4194304 100 0 0 0 %s %s 0 0 20 0 11 0 5000 100000000 %s 0 0 0 0 0 0 0 0 0\n' \
    "$pid" "$comm" "$pid" "$pid" "$ut" "$st" "$rss" >"$FP/$pid/stat"
  printf '%s\n' "$comm" >"$FP/$pid/comm"
  printf 'Name:\t%s\nUid:\t0\t0\t0\t0\n' "$comm" >"$FP/$pid/status"
}
write_proc 1000 'highway' 500 200 25600
write_proc 1001 'sshd(x)' 10 5 2560

# ---------------------------------------------------------------------------
# load the library against the fixture
# ---------------------------------------------------------------------------
export HYN_PROC="$FP" HYN_SYS="$FS" HYN_ETC="$TMP/etc" HYN_VAR="$TMP/var"
mkdir -p "$HYN_ETC" "$HYN_VAR"
HYN_LIB="$ROOT/lib"
HYN_ROOT="$ROOT"
export HYN_LIB HYN_ROOT
export TERM=xterm-256color COLORTERM=truecolor

for m in core ui net collect highway speedtest panels; do
  # shellcheck source=/dev/null
  source "$HYN_LIB/$m.sh" || { printf 'cannot source %s\n' "$m" >&2; exit 1; }
done

cfg_load
color_detect
theme_load hiway || { printf 'theme load failed\n' >&2; exit 1; }
ui_init
collect_init
# The fixture's numbers assume the common amd64 values. This host may differ
# (arm64 macOS pages are 16K), and the point of the test is the arithmetic, not
# the local kernel's page size.
CLK_TCK=100
PAGE_SIZE=4096

printf 'hyn-view selfcheck  (bash %s)\n' "$BASH_VERSION"

# ---------------------------------------------------------------------------
section 'formatters'
# ---------------------------------------------------------------------------
fmt_size_v 0;          eq 'fmt_size 0'        '0 B'      "$FMT_OUT"
fmt_size_v 500;        eq 'fmt_size 500'      '500 B'    "$FMT_OUT"
fmt_size_v 2048;       eq 'fmt_size 2K'       '2.0 KiB'  "$FMT_OUT"
fmt_size_v 1610612736; eq 'fmt_size 1.5G'     '1.5 GiB'  "$FMT_OUT"
fmt_size_v 104857600;  eq 'fmt_size 100M'     '100 MiB'  "$FMT_OUT"

CFG[net_unit]=bits
fmt_rate_v 2000000;    eq 'fmt_rate 16Mbps'   '16.0 Mbps' "$FMT_OUT"
fmt_rate_v 125000000;  eq 'fmt_rate 1Gbps'    '1.0 Gbps'  "$FMT_OUT"
fmt_rate_v 50;         eq 'fmt_rate 400bps'   '400 bps'   "$FMT_OUT"
CFG[net_unit]=bytes
fmt_rate_v 2097152;    eq 'fmt_rate bytes'    '2.0 MiB/s' "$FMT_OUT"
CFG[net_unit]=bits

fmt_dur_v 45;          eq 'fmt_dur 45s'       '45s'        "$FMT_OUT"
fmt_dur_v 3661;        eq 'fmt_dur 1h'        '1h 01m'     "$FMT_OUT"
fmt_dur_v 1234567;     eq 'fmt_dur 14d'       '14d 06:56'  "$FMT_OUT"
fmt_fixed_v 8456 1000 2; eq 'fmt_fixed'       '8.45'       "$FMT_OUT"
fmt_fixed_v 1205 100 2;  eq 'fmt_fixed pad'   '12.05'      "$FMT_OUT"
fmt_thousands_v 1234567; eq 'fmt_thousands'   '1,234,567'  "$FMT_OUT"
fmt_count_v 1234;        eq 'fmt_count K'     '1.2K'       "$FMT_OUT"
fmt_count_v 12345678;    eq 'fmt_count M'     '12.3M'      "$FMT_OUT"
parse_fixed3_v '1.25';   eq 'parse_fixed3'    '1250'       "$FIX3"
parse_fixed3_v '8';      eq 'parse_fixed3 int' '8000'      "$FIX3"

# ---------------------------------------------------------------------------
section 'ansi-aware width'
# ---------------------------------------------------------------------------
vlen $'\033[1mAB\033[0m';        eq 'vlen strips sgr' '2' "$VLEN"
vlen $'\033[38;2;1;2;3mXYZ';     eq 'vlen truecolor'  '3' "$VLEN"
pad_v $'\033[1mAB\033[0m' 5;     vlen "$PAD_OUT"; eq 'pad to width' '5' "$VLEN"
fit_v 'ABCDEFGHIJ' 5;            vlen "$FIT_OUT"; eq 'fit truncates' '5' "$VLEN"
fit_v $'\033[1mABCDEFGHIJ' 5;    vlen "$FIT_OUT"; eq 'fit keeps sgr' '5' "$VLEN"
contains 'fit resets colour' $'\033[0m' "$FIT_OUT"
rep_v '-' 4;                     eq 'rep'  '----' "$REP_OUT"
rep_v '-' 0;                     eq 'rep 0' ''    "$REP_OUT"

# ---------------------------------------------------------------------------
section 'braille plotting'
# ---------------------------------------------------------------------------
# One cell, right sub-column filled two dots from the bottom => U+28A0.
declare -a G=(0 2)
braille_plot G 1 1 4 '' 0
contains 'braille bottom-up' $'\u28a0' "${BR_OUT[0]}"
# Same input flipped grows from the top => U+2818.
braille_plot G 1 1 4 '' 1
contains 'braille flipped'   $'\u2818' "${BR_OUT[0]}"
# A non-zero sample must never render blank: "a little traffic" and "no
# traffic" are different facts.
declare -a G2=(0 1)
braille_plot G2 1 1 100000 '' 0
if [[ ${BR_OUT[0]} == *$'\u2800'* || ${BR_OUT[0]} == '' ]]; then
  bad 'braille tiny value must not be blank'
else ok; fi
declare -a G3=(5 5 5 5)
braille_plot G3 2 2 5 '' 0
eq 'braille row count' '2' "${#BR_OUT[@]}"

declare -a SP=(1 2 3 4)
sparkline_v SP 4 4 ''
vlen "$SPARK_OUT"; eq 'sparkline width' '4' "$VLEN"
bar_v 50 10 ''
vlen "$BAR_OUT"; eq 'bar width' '10' "$VLEN"
bar_v 0 10 ''
vlen "$BAR_OUT"; eq 'bar width at 0' '10' "$VLEN"
bar_v 100 10 ''
vlen "$BAR_OUT"; eq 'bar width at 100' '10' "$VLEN"
declare -a H=(0 50 100)
heat_strip_v H 3
vlen "$HEAT_OUT"; eq 'heat strip width' '3' "$VLEN"

# ---------------------------------------------------------------------------
section 'colour'
# ---------------------------------------------------------------------------
COLOR_DEPTH=24; hex_esc_v '#22d3ee'
eq 'truecolor escape' $'\033[38;2;34;211;238m' "$HEX_ESC"
COLOR_DEPTH=256; hex_esc_v '#000000'; eq '256 black' $'\033[38;5;16m' "$HEX_ESC"
COLOR_DEPTH=256; hex_esc_v '#ffffff'; eq '256 white' $'\033[38;5;231m' "$HEX_ESC"
COLOR_DEPTH=0; hex_esc_v '#22d3ee'; eq 'no colour is empty' '' "$HEX_ESC"
COLOR_DEPTH=24
hex_rgb '#f0a'; eq 'short hex r' '255' "$_HEX_R"; eq 'short hex b' '170' "$_HEX_B"

# ---------------------------------------------------------------------------
section 'theme loading and path safety'
# ---------------------------------------------------------------------------
truthy 'hiway theme resolves'  'theme_path hiway'
falsy  'traversal rejected'    'theme_path "../../../etc/passwd"'
falsy  'dotdot rejected'       'theme_path "..%2fx"'
falsy  'slash rejected'        'theme_path "sub/dir"'
falsy  'unknown theme'         'theme_path definitely-not-a-theme'
theme_load nord && eq 'theme name' 'nord' "$THEME_NAME" || bad 'nord failed to load'
truthy 'theme list non-empty'  '[[ -n $(theme_list) ]]'
theme_load hiway

# ---------------------------------------------------------------------------
section 'config parsing'
# ---------------------------------------------------------------------------
cat >"$HYN_ETC/config" <<'EOF'
# a comment
theme = gruvbox
net_unit="bytes"     # trailing comment
proc_rows=12
bogus_key=whatever
EOF
CFG_WARNINGS=()
cfg_load
eq 'config value'          'gruvbox' "${CFG[theme]}"
eq 'config strips quotes'  'bytes'   "${CFG[net_unit]}"
eq 'config numeric'        '12'      "${CFG[proc_rows]}"
if ((${#CFG_WARNINGS[@]} >= 1)); then ok; else bad 'unknown config key should warn'; fi
falsy 'unknown key not applied' '[[ -v CFG[bogus_key] ]]'
CFG[net_unit]=bits
CFG[theme]=hiway

# ---------------------------------------------------------------------------
section 'network collectors'
# ---------------------------------------------------------------------------
eq 'gateway little-endian' '192.168.1.1' "$(net_gateway_ip)"
# Explicit elapsed time so the expected rates are exact. Deriving the interval
# from the wall clock inside the test would make every assertion off-by-a-few.
net_sample 0                     # seeds the counters
write_netdev 3000000 1500 1 2 1500000 800 3 4
net_sample 1000
eq 'wan from default route' 'eth0' "$NET_WAN"
eq 'rx rate B/s'  '2000000' "${NET_RXR[eth0]}"
eq 'tx rate B/s'  '1000000' "${NET_TXR[eth0]}"
eq 'rx pps'       '500'     "${NET_RPPS[eth0]}"
eq 'tx pps'       '300'     "${NET_TPPS[eth0]}"
eq 'rx errs delta' '1'      "${NET_RERR_R[eth0]}"
eq 'rx drops delta' '2'     "${NET_RDROP_R[eth0]}"
eq 'tx errs delta' '3'      "${NET_TERR_R[eth0]}"
eq 'rx total'     '3000000' "${NET_RX[eth0]}"
falsy 'lo is hidden by default' '[[ " ${NET_IFACES[*]} " == *" lo "* ]]'
truthy 'rx history recorded' '((${#HRX_eth0[@]} >= 2))'

# A counter going backwards (device reset, or a wrap) must report zero, not a
# fabricated multi-gigabit spike.
write_netdev 10 5 0 0 10 5 0 0
net_sample 1000
eq 'counter reset -> 0' '0' "${NET_RXR[eth0]}"

net_link eth0
eq 'link speed' '1000' "$LINK_SPEED"
eq 'link state' 'up'   "$LINK_STATE"

net_sockstat
eq 'sockstat tcp inuse' '5'  "${SOCK[TCP.inuse]}"
eq 'sockstat timewait'  '12' "${SOCK[TCP.tw]}"
eq 'sockstat udp inuse' '2'  "${SOCK[UDP.inuse]}"

net_tcp_states
eq 'tcp listen count' '1' "${TCPST[LISTEN]}"
eq 'tcp estab count'  '1' "${TCPST[ESTAB]}"
eq 'tcp timewait'     '1' "${TCPST[TIME_WAIT]}"
eq 'tcp total'        '3' "${TCPST[TOTAL]}"
contains 'listen port decoded' '8080' "${LISTEN_PORTS[*]}"

net_snmp 1000
eq 'snmp retrans base' '100' "${SNMP[Tcp.RetransSegs]}"
write_snmp 21000 110 0
net_snmp 1000
eq 'retrans rate/s' '10' "${SNMPR[Tcp.RetransSegs]}"
net_retrans_permille
eq 'retrans permille' '10' "$NET_RETRANS_PM"

net_conntrack
eq 'conntrack count' '4200'  "$CT_COUNT"
eq 'conntrack pct'   '6'     "$CT_PCT"
net_tuning
eq 'tuning cc'    'bbr' "${TUNE[cc]}"
eq 'tuning qdisc' 'fq'  "${TUNE[qdisc]}"
eq 'tuning rmem max' '6291456' "${TUNE[rmem]}"

# ---------------------------------------------------------------------------
section 'cpu / memory / disk'
# ---------------------------------------------------------------------------
cpu_sample 1000                   # first pass only seeds
eq 'cpu first tick is 0' '0' "$CPU_PCT"
write_stat 1100 550 8800 220 55 30 120 13345 504000 12100
cpu_sample 1000
eq 'cpu busy pct' '18' "$CPU_PCT"
eq 'cpu user'     '10' "$CPU_USER"
eq 'cpu sys'      '5'  "$CPU_SYS"
eq 'cpu iowait'   '2'  "$CPU_IOWAIT"
eq 'cpu steal'    '2'  "$CPU_STEAL"
eq 'cpu irq'      '1'  "$CPU_IRQ"
eq 'core count'   '2'  "$CPU_COUNT"
eq 'ctxt per sec' '4000' "$CPU_CTXT_R"
eq 'forks per sec' '100' "$CPU_FORK_R"
eq 'load1'        '0.42' "$LOAD1"
eq 'procs running' '2'  "$PROCS_RUN"

mem_sample
eq 'mem total'  '16777216000' "$MEM_TOTAL"
eq 'mem used'   '8388608000'  "$MEM_USED"
eq 'mem pct'    '50'          "$MEM_PCT"
eq 'mem cache'  '4325376000'  "$MEM_CACHE"
eq 'swap used'  '1048576000'  "$SWAP_USED"
eq 'swap pct'   '50'          "$SWAP_PCT"

psi_sample
eq 'psi cpu avg10 (x100)' '125' "${PSI[cpu.some]}"

disk_sample 1000
write_diskstats 6000 8000 300
disk_sample 1000
eq 'disk in list'    'sda'     "${DISKS[0]}"
eq 'disk read B/s'   '2048000' "${DISK_RD[sda]}"
eq 'disk write B/s'  '2048000' "${DISK_WR[sda]}"
eq 'disk util pct'   '10'      "${DISK_UTIL[sda]}"

sys_sample
eq 'uptime seconds' '123456' "$UPTIME_S"
eq 'entropy'        '3800'   "$ENTROPY"
eq 'fd used'        '1024'   "$FD_USED"
eq 'hostname'       'test-node' "$HOSTNAME_S"
eq 'kernel'         '6.8.0-51-generic' "$KERNEL"
# Marketing noise stripped, model and clock kept.
eq 'cpu model trimmed' 'Intel Xeon Gold 6248 @ 2.50GHz' "$CPU_MODEL"

# ---------------------------------------------------------------------------
section 'processes'
# ---------------------------------------------------------------------------
proc_sample 1000 5 cpu           # seeds the per-pid baselines
write_proc 1000 'highway' 600 200 25600
write_proc 1001 'sshd(x)' 15 5 2560
proc_sample 1000 5 cpu
eq 'proc count'        '2'    "$PROC_TOTAL"
eq 'thread total'      '22'   "$PROC_THREADS"
eq 'busiest pid first' '1000' "${P_PID[0]}"
eq 'comm parsed'       'highway' "${P_NAME[0]}"
# 100 jiffies over 1000ms at 100Hz is exactly one core, reported in tenths.
eq 'cpu tenths'        '1000' "${P_CPU[0]}"
eq 'rss bytes'         '104857600' "${P_RSS[0]}"
eq 'thread count'      '11'   "${P_THR[0]}"
# comm containing ')' must not shift the field offsets
eq 'comm with paren'   'sshd(x)' "${P_NAME[1]}"
eq 'second proc rss'   '10485760' "${P_RSS[1]}"
proc_sample 1000 5 mem
eq 'mem sort picks biggest' '1000' "${P_PID[0]}"

# ---------------------------------------------------------------------------
section 'speed test history'
# ---------------------------------------------------------------------------
eq 'calendar 4/day' '*-*-* 00,06,12,18:07:00' "$(st_calendar 4)"
# 8/day crosses 09, which bash reads as invalid octal if the loop counter is
# reused for the zero-padded form.
eq 'calendar 8/day' '*-*-* 00,03,06,09,12,15,18,21:07:00' "$(st_calendar 8)"
eq 'calendar 1/day' '*-*-* 00:07:00' "$(st_calendar 1)"
eq 'calendar clamps' '*-*-* 00:07:00' "$(st_calendar 0)"

ST_TS=1700000000 ST_DOWN=11000000 ST_UP=5000000 ST_LAT=7800 ST_JIT=400
ST_PROVIDER='curl/cloudflare' ST_NOTE='ok'
st_append eth0
ST_TS=1700003600 ST_DOWN=0 ST_UP=0 ST_NOTE='skipped: link 40% busy'
st_append eth0
st_history_read 1
eq 'history rows'            '2'        "${#ST_H_TS[@]}"
# A skipped run must not blank the last known-good reading the operator watches.
eq 'last good download kept' '11000000' "$ST_LAST_DOWN"
eq 'last good ts kept'       '1700000000' "$ST_LAST_TS"
contains 'skip reason recorded' 'skipped' "$ST_LAST_NOTE"
eq 'baseline is best result' '11000000' "$(st_baseline)"

# ---------------------------------------------------------------------------
section 'highway tracker'
# ---------------------------------------------------------------------------
HW_BIN="$TMP/nonexistent-highway"
hw_binary 1
eq 'absent binary detected' '0' "$HW_PRESENT"
hw_health
eq 'health when absent' 'absent' "$HW_HEALTH"

HW_BIN="$TMP/fake-highway"
printf 'not really a binary\n' >"$HW_BIN"
hw_binary 1
eq 'present binary detected' '1' "$HW_PRESENT"

# Version comparison must be numeric per component: 0.1.9 is older than 0.1.75.
HW_VERSION='v0.1.9' HW_LATEST='v0.1.75'
hw_update_flag
eq 'update available (0.1.9 < 0.1.75)' '1' "$HW_UPDATE"
HW_VERSION='v0.1.75' HW_LATEST='v0.1.75'
hw_update_flag
eq 'no update when equal' '0' "$HW_UPDATE"
HW_VERSION='v0.2.0' HW_LATEST='v0.1.75'
hw_update_flag
eq 'no downgrade prompt' '0' "$HW_UPDATE"

# The process finder must locate the node by comm and read its resources.
HW_PID=0 HW_UNIT_COUNT=0
UPTIME_S=123456
_HW_SCAN_LAST=0
hw_process 1000
eq 'found node pid' '1000' "$HW_PID"
_HW_SCAN_LAST=0
write_proc 1000 'highway' 700 200 25600
hw_process 1000
eq 'node cpu tenths' '1000' "$HW_CPU"
eq 'node rss'        '104857600' "$HW_RSS"

HW_PRESENT=1 HW_FAILED=1 HW_UNIT_COUNT=1 HW_ACTIVE=0
hw_health
eq 'failed unit is critical' 'crit' "$HW_HEALTH"
HW_FAILED=0 HW_ACTIVE=1 HW_UNITS=(highway.service) HW_RESTARTS=([highway.service]=7)
HW_JOURNAL_ERR=0
hw_health
eq 'restart loop is a warning' 'warn' "$HW_HEALTH"
contains 'restart count explained' '7x' "$HW_HEALTH_WHY"
HW_RESTARTS=([highway.service]=0)
hw_health
eq 'healthy node' 'ok' "$HW_HEALTH"

# The update check must rate-limit the ATTEMPT, not just cache successes. A host
# that cannot reach the endpoint never writes the cache file, and an earlier
# version therefore spawned a fresh curl on every single tick.
HW_LATEST_URL='http://127.0.0.1:1/nope'   # refused instantly, no real network
CFG[highway_update_check]=on
_HW_FETCH_AT=0 _HW_FETCH_PID=0
rm -f "$TMP/var/hw-latest"
hw_latest_check
first_at=$_HW_FETCH_AT
truthy 'first update check attempts a fetch' '((first_at > 0))'
hw_latest_check
eq 'second check does not re-spawn' "$first_at" "$_HW_FETCH_AT"
hw_latest_check
eq 'third check does not re-spawn' "$first_at" "$_HW_FETCH_AT"
wait 2>/dev/null || true
CFG[highway_update_check]=off

# ---------------------------------------------------------------------------
section 'read-only guarantee'
# ---------------------------------------------------------------------------
# The Highway tracker must never mutate node state. Grep the source rather than
# trusting review: this is the one property a monitoring tool cannot get wrong.
# Comments are stripped first -- the file's own header documents the prohibition
# by naming the forbidden verbs, and matching prose would be a false positive.
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
if code_only "$HYN_LIB/highway.sh" |
  grep -qE 'systemctl[^|]*[[:space:]](start|stop|restart|reload|kill|enable|disable|mask)[[:space:]]'; then
  bad 'highway.sh contains a state-changing systemctl call'
else ok; fi
if code_only "$HYN_LIB/highway.sh" |
  grep -qE '\b(tc|nft|iptables)\b[^|#]*\b(add|del|delete|flush|replace|change)\b'; then
  bad 'highway.sh contains a mutating firewall/tc call'
else ok; fi
if code_only "$HYN_LIB/highway.sh" | grep -qE '>[[:space:]]*"?(/etc|/var/lib|/opt)/(highway|hw-os)'; then
  bad 'highway.sh writes into a Highway directory'
else ok; fi
# setup.sh may enable its own timer, but must never touch Highway units.
if code_only "$HYN_LIB/setup.sh" | grep -qE 'systemctl.*(highway|nebula|mosaic|hw-)'; then
  bad 'setup.sh references Highway units'
else ok; fi

# ---------------------------------------------------------------------------
section 'frame rendering'
# ---------------------------------------------------------------------------
TERM_COLS=140 TERM_ROWS=45
PUB_IP='203.0.113.9'
LAT_MS=([gw]=420 [1.1.1.1]=8200 [dns]=12000)
LAT_LOSS=([gw]=0 [1.1.1.1]=0 [dns]=0)
LAT_JIT=([gw]=100 [1.1.1.1]=300 [dns]=-1)
LAT_AGE=3
HW_PRESENT=1 HW_HEALTH=ok HW_NEBULA='' HW_VERSION='v0.1.75'
panels_enabled
render_dash
eq 'dash fills the screen' '45' "${#FB[@]}"
# Every row must be exactly the terminal width or narrower; an over-wide row is
# what makes a bash TUI wrap and smear.
overwide=0; blankrows=0
for i in "${!FB[@]}"; do
  vlen "${FB[i]}"
  ((VLEN > TERM_COLS)) && { overwide=$((overwide + 1)); printf '    row %s is %s cols\n' "$i" "$VLEN" >&2; }
done
eq 'no row exceeds width' '0' "$overwide"
contains 'header has hostname' 'test-node' "${FB[0]}"
# The health badge must survive at every width -- it is the reason the header
# exists for this audience.
contains 'header has node badge' 'HIGHWAY' "${FB[0]}"
contains 'network panel present' 'NETWORK' "${FB[1]}"
truthy 'footer drawn' '[[ ${FB[44]} == *quit* ]]'

# Each panel must appear exactly once. The layout picks between a side-by-side
# bottom band and a full-width one, and an earlier version drew the process list
# in both.
count_panel() {
  local title=$1 n=0 i
  for i in "${!FB[@]}"; do [[ ${FB[i]} == *"$title"* && ${FB[i]} == *"$G_TL"* ]] && ((n++)); done
  printf '%d' "$n"
}
eq 'one NETWORK panel'   '1' "$(count_panel NETWORK)"
eq 'one PROCESSES panel' '1' "$(count_panel PROCESSES)"
eq 'one CPU panel'       '1' "$(count_panel CPU)"
eq 'one DISK panel'      '1' "$(count_panel DISK)"
eq 'one MEMORY panel'    '1' "$(count_panel MEMORY)"
eq 'one NODE panel'      '1' "$(count_panel 'HIGHWAY NODE')"

# Panel borders are not evidence of a panel that works. An earlier refactor
# collected the node rows into an array and never emitted them: the frame still
# had a titled, closed, and completely empty box, and every structural check
# above passed. Assert on content each panel is supposed to contain.
frame_has() {
  local needle=$1 i
  for i in "${!FB[@]}"; do [[ ${FB[i]} == *"$needle"* ]] && return 0; done
  return 1
}
truthy 'net panel has retrans'  'frame_has retrans'
# 8200us -> "8.20"; the "ms" suffix is a separate coloured span, so the number
# and its unit are not contiguous in the rendered line.
truthy 'net panel has latency'  'frame_has 8.20'
truthy 'net panel has tcp line' 'frame_has estab'
truthy 'cpu panel has steal'    'frame_has steal'
truthy 'cpu panel has cores'    'frame_has cores'
truthy 'mem panel has cache'    'frame_has cache'
truthy 'node panel has health'  'frame_has "unit(s) active"'
truthy 'node panel has journal' 'frame_has "journal 1h"'
truthy 'node panel has tunnel'  'frame_has tunnel'
truthy 'proc panel has command' 'frame_has highway'
# The doubled-state bug: status_dot_v with an explicitly empty label printed the
# state name twice ("active active/running").
status_dot_v active ''
falsy 'empty status label stays empty' '[[ $STATUS_OUT == *active* ]]'
status_dot_v active 'running'
contains 'status label honoured' 'running' "$STATUS_OUT"

# Narrow terminal: the layout must degrade, not corrupt.
TERM_COLS=80 TERM_ROWS=24
FB_PREV=()
render_dash
eq 'narrow dash height' '24' "${#FB[@]}"
overwide=0
for i in "${!FB[@]}"; do
  vlen "${FB[i]}"
  ((VLEN > TERM_COLS)) && overwide=$((overwide + 1))
done
eq 'no overflow at 80 cols' '0' "$overwide"
contains 'badge kept at 80 cols' 'HIGHWAY' "${FB[0]}"

# Very small terminal: still must not crash or produce garbage.
TERM_COLS=40 TERM_ROWS=10
FB_PREV=()
render_dash
eq 'tiny dash height' '10' "${#FB[@]}"
overwide=0
for i in "${!FB[@]}"; do
  vlen "${FB[i]}"
  ((VLEN > TERM_COLS)) && overwide=$((overwide + 1))
done
eq 'no overflow at 40 cols' '0' "$overwide"

TERM_COLS=140 TERM_ROWS=45
FB_PREV=()
render_net_full
eq 'net view height' '45' "${#FB[@]}"
# graph=block and graph=off are the documented levers for cutting render cost, so
# they must actually change what gets drawn. Compare the network panel's own
# height rather than hunting for glyph codepoints, which depends on locale
# collation inside glob character ranges.
CFG[graph]=braille
panel_net P_NET 140 6
h_braille=${#P_NET[@]}
CFG[graph]=block
panel_net P_NET 140 6
h_block=${#P_NET[@]}
CFG[graph]=off
panel_net P_NET 140 6
h_off=${#P_NET[@]}
CFG[graph]=braille
truthy 'braille is the tallest graph' '((h_braille > h_block))'
truthy 'block is taller than none'    '((h_block > h_off))'
eq 'block mode uses 3 graph rows' "$((h_off + 3))" "$h_block"
eq 'braille uses 2*h+1 graph rows'  "$((h_off + 13))" "$h_braille"

CFG[graph]=off
FB_PREV=(); render_dash
eq 'graph=off still fills screen' '45' "${#FB[@]}"
truthy 'graph=off keeps the rate line' 'frame_has peak'
CFG[graph]=block
FB_PREV=(); render_dash
eq 'block mode still fills screen' '45' "${#FB[@]}"
CFG[graph]=braille

TERM_COLS=140 TERM_ROWS=45
FB_PREV=()
render_proc_full
eq 'proc view height' '45' "${#FB[@]}"
contains 'proc view has header row' 'COMMAND' "${FB[2]}"
FB_PREV=()
render_node_full
eq 'node view height' '45' "${#FB[@]}"

# The diff renderer must emit nothing when nothing changed.
FB_PREV=("${FB[@]}")
out=$(fb_flush)
eq 'unchanged frame writes nothing' '' "$out"
FB[3]='changed'
out=$(fb_flush)
truthy 'changed frame writes something' '[[ -n $out ]]'

# ---------------------------------------------------------------------------
printf '\n'
if ((FAIL == 0)); then
  printf '%d checks passed\n' "$PASS"
  exit 0
fi
printf '%d passed, %d FAILED\n' "$PASS" "$FAIL"
printf '\nfailures:\n'
for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
exit 1
