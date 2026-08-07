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
#
# Fixture files are written with printf, never heredocs. bash 5.3 routes both
# heredocs and here-strings through a pipe, and macOS starts pipes at a 512-byte
# buffer, so anything past roughly ten lines deadlocks before the receiving
# command is even exec'd. That cost real debugging time three separate times;
# keep printf.

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

# True when a rule id is in the currently-firing set.
frame_has_alert() {
  local want=$1 i
  for i in "${!AL_ID[@]}"; do [[ ${AL_ID[i]} == "$want" ]] && return 0; done
  return 1
}

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

printf '%s\n' \
  'MemTotal:       16384000 kB' \
  'MemFree:         1024000 kB' \
  'MemAvailable:    8192000 kB' \
  'Buffers:          512000 kB' \
  'Cached:          4096000 kB' \
  'SReclaimable:     256000 kB' \
  'Shmem:            128000 kB' \
  'Dirty:             12000 kB' \
  'SwapTotal:       2048000 kB' \
  'SwapFree:        1024000 kB' \
  'Committed_AS:    9000000 kB' \
  > "$FP/meminfo"

# Gateway 192.168.1.1 stored little-endian as 0101A8C0. Flags 0003 has
# RTF_GATEWAY (0x2) set, which is what marks the real default route.
printf '%s\n' \
  'Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT' \
  'eth0	00000000	0101A8C0	0003	0	0	100	00000000	0	0	0' \
  'eth0	0001A8C0	00000000	0001	0	0	0	00FFFFFF	0	0	0' \
  > "$FP/net/route"

printf '%s\n' \
  'sockets: used 200' \
  'TCP: inuse 5 orphan 0 tw 12 alloc 20 mem 3' \
  'UDP: inuse 2 mem 1' \
  'UDPLITE: inuse 0' \
  'RAW: inuse 0' \
  'FRAG: inuse 0 memory 0' \
  > "$FP/net/sockstat"

# st column is field 4. 0A=LISTEN on port 0x1F90 (8080), 01=ESTAB, 06=TIME_WAIT.
printf '%s\n' \
  '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode' \
  '   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345 1' \
  '   1: 0100007F:C350 0100007F:1F90 01 00000000:00000000 00:00000000 00000000     0        0 12346 1' \
  '   2: 0100007F:C351 0100007F:1F90 06 00000000:00000000 00:00000000 00000000     0        0 12347 1' \
  > "$FP/net/tcp"

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

printf '%s\n' \
  'some avg10=1.25 avg60=0.80 avg300=0.30 total=1234567' \
  > "$FP/pressure/cpu"
printf '%s\n' \
  'some avg10=0.00 avg60=0.00 avg300=0.00 total=0' \
  'full avg10=0.00 avg60=0.00 avg300=0.00 total=0' \
  > "$FP/pressure/io"

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

for m in core ui net collect highway speedtest notify alerts report update panels; do
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
# The eighth blocks come in two axes and picking the wrong one is visible. A
# horizontal bar's partial cell must come from the LEFT ramp (U+258F..U+2589,
# growing rightward); the lower ramp (U+2581..U+2587) renders a squat mark on the
# baseline that reads as a glitch rather than as sub-cell precision.
bar_v 47 10 ''
truthy 'bar partial cell is a left block' '[[ $BAR_OUT == *$'"'"'\u258b'"'"'* ]]'
falsy  'bar partial cell is not a lower block' '[[ $BAR_OUT == *$'"'"'\u2585'"'"'* ]]'
# ...and the sparkline must keep using the lower ramp, or columns grow sideways.
declare -a SP2=(4)
sparkline_v SP2 1 8 ''
truthy 'sparkline column is a lower block' '[[ $SPARK_OUT == *$'"'"'\u2584'"'"'* ]]'
truthy 'the two ramps are distinct' '[[ ${GLYPH_BLOCK[4]} != "${GLYPH_LBLOCK[4]}" ]]'
eq 'both ramps share the full block' "${GLYPH_BLOCK[8]}" "${GLYPH_LBLOCK[8]}"
eq 'both ramps have 9 steps' '9' "${#GLYPH_LBLOCK[@]}"
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
printf '%s\n' \
  '# a comment' \
  'theme = gruvbox' \
  'net_unit="bytes"     # trailing comment' \
  'proc_rows=12' \
  'bogus_key=whatever' \
  > "$HYN_ETC/config"
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

# Mount filtering. A stock Ubuntu server mounts every snap as a read-only
# squashfs loop at /snap/..., and squashfs is ALWAYS 100% full, so without
# filtering the disk panel fills with them and every one fires a permanent,
# uncleanable "disk critically full" alert.
printf '%s\n' \
  '/dev/vda2 / ext4 rw,relatime 0 0' \
  '/dev/vda1 /boot/efi vfat rw,relatime 0 0' \
  '/dev/vdb1 /var ext4 rw,relatime 0 0' \
  '/dev/loop0 /snap/core22/1612 squashfs ro,nodev,relatime 0 0' \
  '/dev/loop1 /snap/snapd/21759 squashfs ro,nodev,relatime 0 0' \
  '/dev/loop2 /snap/lxd/29351 squashfs ro,nodev,relatime 0 0' \
  'tmpfs /run tmpfs rw,nosuid,nodev 0 0' \
  'overlay /var/lib/docker/overlay2/abc/merged overlay rw,relatime 0 0' \
  'proc /proc proc rw,nosuid,nodev,noexec 0 0' \
  '/dev/vdc1 /mnt/backup ext4 ro,relatime 0 0' \
  '192.168.1.9:/export /mnt/nfs nfs4 rw,relatime 0 0' \
  > "$FP/mounts"
_disk_scan_mounts
truthy 'root kept'            '[[ -v _MP_OK[/] ]]'
truthy 'second ext4 kept'     '[[ -v _MP_OK[/var] ]]'
truthy 'nfs kept'             '[[ -v _MP_OK[/mnt/nfs] ]]'
falsy  'snap squashfs dropped'    '[[ -v _MP_OK[/snap/core22/1612] ]]'
falsy  'snapd squashfs dropped'   '[[ -v _MP_OK[/snap/snapd/21759] ]]'
falsy  'lxd squashfs dropped'     '[[ -v _MP_OK[/snap/lxd/29351] ]]'
falsy  'tmpfs dropped'            '[[ -v _MP_OK[/run] ]]'
falsy  'docker overlay dropped'   '[[ -v _MP_OK[/var/lib/docker/overlay2/abc/merged] ]]'
falsy  'procfs dropped'           '[[ -v _MP_OK[/proc] ]]'
falsy  'efi partition dropped'    '[[ -v _MP_OK[/boot/efi] ]]'
# Read-only means it cannot fill up, so it is not worth alerting on.
falsy  'read-only mount dropped'  '[[ -v _MP_OK[/mnt/backup] ]]'
eq 'exactly three real mounts' '3' "${#_MP_OK[@]}"
# /proc/mounts octal-escapes spaces; the key must match what df prints.
printf '/dev/vdd1 /mnt/my\\040disk ext4 rw,relatime 0 0\n' >>"$FP/mounts"
_disk_scan_mounts
truthy 'escaped space decoded' '[[ -v _MP_OK["/mnt/my disk"] ]]'

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
# block: rx line + scale axis + tx line + time axis = 4
eq 'block mode adds 4 graph rows' "$((h_off + 4))" "$h_block"

# The tx plot's HEIGHT scales with its share of the shared maximum: the scale
# stays shared (so a dot height means the same rate in both plots and they remain
# comparable) but rows that could only ever be blank are given back to the
# layout. Assert the property, not a magic total.
CFG[graph]=braille
HRX_eth0=(); HTX_eth0=()
for i in $(seq 1 300); do HRX_eth0+=(1000); HTX_eth0+=(250); done
panel_net P_NET 140 6
h_quarter=${#P_NET[@]}
HTX_eth0=()
for i in $(seq 1 300); do HTX_eth0+=(1000); done
panel_net P_NET 140 6
h_equal=${#P_NET[@]}
# equal traffic: 6 rx + axis + 6 tx + time axis = 14
eq 'symmetric traffic uses 2h+2 rows' "$((h_off + 14))" "$h_equal"
# a quarter of the scale needs ceil(6/4)=2 tx rows: 6 + axis + 2 + time axis = 10
eq 'light upload uses fewer tx rows' "$((h_off + 10))" "$h_quarter"
truthy 'asymmetric graph is shorter' '((h_quarter < h_equal))'

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
section 'version comparison and profiles'
# ---------------------------------------------------------------------------
truthy 'newer patch is newer'       'ver_gt 1.0.1 1.0.0'
truthy 'newer minor is newer'       'ver_gt 1.1.0 1.0.9'
truthy 'newer major is newer'       'ver_gt 2.0.0 1.9.9'
falsy  'equal is not newer'         'ver_gt 1.0.0 1.0.0'
falsy  'older is not newer'         'ver_gt 1.0.0 1.0.1'
truthy 'v prefix tolerated'         'ver_gt v1.0.1 v1.0.0'
# The comparison that string sorting gets wrong, and the range real projects
# actually live in.
truthy '0.1.75 is newer than 0.1.9' 'ver_gt 0.1.75 0.1.9'
falsy  '0.1.9 is not newer than 0.1.75' 'ver_gt 0.1.9 0.1.75'
falsy  'garbage is not newer'       'ver_gt "" 1.0.0'

# A profile fills in defaults but must never overwrite a deliberate setting.
CFG[profile]=performance; CFG_EXPLICIT=(); profile_apply
eq 'performance sets block graph' 'block' "${CFG[graph]}"
eq 'performance slows refresh'    '2.0'   "${CFG[interval]}"
eq 'performance drops gradient'   'off'   "${CFG[graph_gradient]}"
CFG[profile]=best; CFG_EXPLICIT=(); profile_apply
eq 'best sets braille graph'      'braille' "${CFG[graph]}"
eq 'best enables gradient'        'on'      "${CFG[graph_gradient]}"
eq 'best uses 1s refresh'         '1.0'     "${CFG[interval]}"
# Explicit beats preset.
CFG[profile]=best; CFG[graph]=block; CFG_EXPLICIT=([graph]=1); profile_apply
eq 'explicit graph survives the profile' 'block' "${CFG[graph]}"
CFG_EXPLICIT=(); CFG[profile]=best; profile_apply

# ---------------------------------------------------------------------------
section 'graph presentation'
# ---------------------------------------------------------------------------
declare -a GG=(1 2 3 4 5 6 7 8)
# Gradient mode must colour rows differently; flat mode must not.
braille_plot GG 4 4 8 "${C[rx]}" 0 1
g_top=${BR_OUT[0]%%$'\u2800'*}; g_bot=${BR_OUT[3]%%$'\u2800'*}
falsy 'gradient colours rows differently' '[[ ${BR_OUT[0]:0:12} == ${BR_OUT[3]:0:12} ]]'
braille_plot GG 4 4 8 "${C[rx]}" 0 0
truthy 'flat mode uses one colour' '[[ ${BR_OUT[0]:0:12} == ${BR_OUT[3]:0:12} ]]'
braille_plot GG 4 4 8 '' 0 1
eq 'gradient keeps the row count' '4' "${#BR_OUT[@]}"
for i in "${!BR_OUT[@]}"; do vlen "${BR_OUT[i]}"; ((VLEN == 4)) || bad "gradient row $i width is $VLEN not 4"; done
ok

time_axis_v 60 1 2
vlen "$TIME_AXIS"; eq 'time axis fills its width' '60' "$VLEN"
contains 'time axis marks now' 'now' "$TIME_AXIS"
contains 'time axis marks the span' '-2m' "$TIME_AXIS"
time_axis_v 12 1 2
vlen "$TIME_AXIS"; eq 'narrow axis degrades to a rule' '12' "$VLEN"

declare -a ST2=(10 20 30 40)
arr_stats_v ST2 4
eq 'stats min' '10' "$ARR_MIN"
eq 'stats avg' '25' "$ARR_AVG"
eq 'stats max' '40' "$ARR_MAX"
arr_stats_v ST2 2
eq 'stats honour the window' '35' "$ARR_AVG"

# ---------------------------------------------------------------------------
section 'connection identity'
# ---------------------------------------------------------------------------
eq 'ethernet detected'  'ethernet' "$(net_iface_type eth0)"
mkdir -p "$FS/class/net/wlan0/wireless"
printf 'up\n' >"$FS/class/net/wlan0/operstate"
eq 'wireless detected'  'wifi'     "$(net_iface_type wlan0)"
mkdir -p "$FS/class/net/tun0"; printf '0x0001\n' >"$FS/class/net/tun0/tun_flags"
eq 'tunnel detected'    'tunnel'   "$(net_iface_type tun0)"
mkdir -p "$FS/class/net/br0/bridge"
eq 'bridge detected'    'bridge'   "$(net_iface_type br0)"
eq 'loopback detected'  'loopback' "$(net_iface_type lo)"
# Gateway decode is already covered; identity must survive absent tooling.
NET_IDENT_LAST=0
net_identity 1
truthy 'identity run does not fail without iw/nmcli' 'true'
NET_WAN=eth0
net_ident_label
truthy 'identity label is populated' '[[ -n $NET_IDENT_LABEL ]]'
IF_SSID=([eth0]='MyNetwork-5G')
NET_SSID='MyNetwork-5G'
net_ident_label
contains 'ssid used as the label' 'MyNetwork-5G' "$NET_IDENT_LABEL"
NET_SSID=''

# ---------------------------------------------------------------------------
section 'attribution'
# ---------------------------------------------------------------------------
eq 'author constant' 'Vivek W (AryanVBW)' "$HYN_AUTHOR"
contains 'copyright names the author' 'Vivek W (AryanVBW)' "$HYN_COPYRIGHT"
TERM_COLS=140 TERM_ROWS=45
footer_line 140
contains 'footer carries the credit' 'Vivek W (AryanVBW)' "$FTR_OUT"
vlen "$FTR_OUT"; truthy 'footer fits the width' '((VLEN <= 140))'
# Even at 80 columns the credit survives; the key hints are what get dropped.
footer_line 80
contains 'credit survives at 80 cols' 'AryanVBW' "$FTR_OUT"
vlen "$FTR_OUT"; truthy 'narrow footer still fits' '((VLEN <= 80))'
UPD_AVAILABLE=1 UPD_LATEST=9.9.9
footer_line 140
contains 'update badge shown in footer' '9.9.9' "$FTR_OUT"
UPD_AVAILABLE=0 UPD_LATEST=''

# ---------------------------------------------------------------------------
section 'self update'
# ---------------------------------------------------------------------------
uf="$TMP/var/update-check"
printf '%s\n9.9.9\n' "${EPOCHSECONDS:-0}" >"$uf"
truthy 'update cache reads'        'update_read'
eq 'latest from cache' '9.9.9' "$UPD_LATEST"
eq 'update flagged available' '1' "$UPD_AVAILABLE"
printf '%s\n0.0.1\n' "${EPOCHSECONDS:-0}" >"$uf"
update_read
eq 'older release not flagged' '0' "$UPD_AVAILABLE"
printf '%s\n%s\n' "${EPOCHSECONDS:-0}" "$HYN_VERSION" >"$uf"
update_read
eq 'same version not flagged' '0' "$UPD_AVAILABLE"
rm -f "$uf"
falsy 'missing cache reports nothing' 'update_read'
# auto_update=off must not even try.
CFG[auto_update]=off
update_check_async
falsy 'off means no cache is written' '[[ -f $uf ]]'
CFG[auto_update]=check
update_detect_method
truthy 'install method is classified' '[[ -n $UPD_METHOD ]]'

# ---------------------------------------------------------------------------
section 'notification safety'
# ---------------------------------------------------------------------------
json_escape_v 'plain'; eq 'json plain' 'plain' "$JSON_OUT"
json_escape_v 'say "hi"'; eq 'json quotes' 'say \"hi\"' "$JSON_OUT"
json_escape_v 'back\slash'; eq 'json backslash' 'back\\slash' "$JSON_OUT"
json_escape_v $'two\nlines'; eq 'json newline' 'two\nlines' "$JSON_OUT"
json_escape_v $'tab\there'; eq 'json tab' 'tab\there' "$JSON_OUT"
# A journal line is attacker-influenced text that ends up inside a JSON string.
json_escape_v $'evil","x":"pwned'; contains 'json injection neutralised' '\"' "$JSON_OUT"
falsy 'no raw quote survives escaping' '[[ $JSON_OUT == *[^\\]\"* ]]'
json_escape_v $'ctrl\x01char'; eq 'json strips control chars' 'ctrlchar' "$JSON_OUT"

truthy 'accepts a normal address'   'valid_email ops@example.com'
truthy 'accepts plus addressing'    'valid_email ops+hyn@example.co.uk'
falsy  'rejects missing domain'     'valid_email ops@'
falsy  'rejects missing tld'        'valid_email ops@example'
falsy  'rejects no at sign'         'valid_email example.com'
falsy  'rejects empty'              'valid_email ""'
# Header injection: a newline in an address would let a crafted value add its
# own SMTP headers.
falsy  'rejects embedded newline'   'valid_email "$(printf "a@b.com\nBcc: x@y.com")"'
falsy  'rejects embedded CR'        'valid_email "$(printf "a@b.com\rX: y")"'

valid_email_list 'a@b.com, c@d.com'
eq 'parses a recipient list' '2' "${#VALID_TO[@]}"
valid_email_list 'a@b.com,broken,c@d.com' 2>/dev/null
eq 'drops invalid recipients' '2' "${#VALID_TO[@]}"
falsy 'rejects an all-invalid list' 'valid_email_list "nope,alsonope" 2>/dev/null'

truthy 'accepts an api-key charset'  'valid_token re_AbC123-_.=+/'
falsy  'rejects a key with a space'  'valid_token "abc def"'
falsy  'rejects a key with a quote'  'valid_token '"'"'ab"cd'"'"''
falsy  'rejects a key with newline'  'valid_token "$(printf "a\nb")"'

# redact must scrub any configured secret out of text bound for a log.
SEC=([resend_api_key]='re_supersecretvalue123') SECRETS_LOADED=1
out=$(redact 'curl failed using re_supersecretvalue123 oops')
falsy 'redact removes the secret' '[[ $out == *supersecret* ]]'
contains 'redact leaves a marker' '<redacted>' "$out"
SEC=() SECRETS_LOADED=1

# ---------------------------------------------------------------------------
section 'alert engine'
# ---------------------------------------------------------------------------
# Hysteresis: a value parked between the fire and clear thresholds must hold its
# previous state. Without this, a disk sitting at exactly 85% mails every cycle.
_reset_alerts() {
  AL_ID=() AL_SEV=() AL_MSG=() AL_NEW=() AL_VAL=() AL_RESOLVED=()
  AL_CRIT=0 AL_WARN=0 AL_INFO=0 AL_FIRING=0
  _AL_SEEN=()
}

_reset_alerts; _AL_PREV_STATE=()
_check_num t_mem warn 91 90 82 'mem'
eq 'fires above the threshold' '1' "$AL_FIRING"
eq 'marked as new'             '1' "${AL_NEW[0]}"

_reset_alerts; _AL_PREV_STATE=([t_mem]=firing)
_check_num t_mem warn 85 90 82 'mem'
eq 'stays firing between thresholds' '1' "$AL_FIRING"
eq 'not new on the second run'       '0' "${AL_NEW[0]}"

_reset_alerts; _AL_PREV_STATE=([t_mem]=firing); _AL_PREV_NOTIFIED=([t_mem]=1000)
_check_num t_mem warn 81 90 82 'mem'
eq 'clears below the clear threshold' '0' "$AL_FIRING"
eq 'reports one recovery'             '1' "${#AL_RESOLVED[@]}"

# A rule that never notified should not announce a recovery nobody heard about.
_reset_alerts; _AL_PREV_STATE=([t_mem]=firing); _AL_PREV_NOTIFIED=([t_mem]=0)
_check_num t_mem warn 10 90 82 'mem'
eq 'silent recovery when never notified' '0' "${#AL_RESOLVED[@]}"

_reset_alerts; _AL_PREV_STATE=()
_check_num t_off warn 99 0 0 'disabled rule'
eq 'threshold 0 disables the rule' '0' "$AL_FIRING"
falsy 'disabled rule is not even evaluated' '[[ -v _AL_SEEN[t_off] ]]'

_reset_alerts; _AL_PREV_STATE=()
_check_num t_junk warn 'not-a-number' 90 80 'x'
eq 'non-numeric value is ignored' '0' "$AL_FIRING"

_reset_alerts; _AL_PREV_STATE=()
_check_bool t_down crit 1 'iface down'
eq 'boolean rule fires' '1' "$AL_CRIT"
_reset_alerts; _AL_PREV_STATE=()
_check_bool t_down crit 0 'iface down'
eq 'boolean rule quiet when false' '0' "$AL_FIRING"

eq 'severity ranks crit highest' '3' "$(_sev_rank crit)"
truthy 'warn outranks info' '(( $(_sev_rank warn) > $(_sev_rank info) ))'

# Full rule sweep against the fixture. Memory is 50% and disk 38/71, so the
# resource rules must stay quiet; then push memory up and watch it fire.
mem_sample; sys_sample
MOUNTS=(/ /var); MP_PCT=([/]=38 [/var]=71)
MP_AVAIL=([/]=100000000 [/var]=50000000); MP_SIZE=([/]=200000000 [/var]=160000000)
MP_USED=([/]=76000000 [/var]=110000000)
CPU_STEAL=0 CPU_IOWAIT=0 CPU_PCT=10 LOAD1=0.42 CPU_COUNT=2
NET_RETRANS_PM=0 CT_PCT=6 FAILED_UNITS=() REBOOT_REQ=0 HW_PRESENT=0
LAT_MS=([1.1.1.1]=8200) LAT_LOSS=([1.1.1.1]=0)
ST_LAST_DOWN=0
CFG[highway_track]=off
_AL_PREV_STATE=()
alerts_evaluate
eq 'healthy fixture fires nothing' '0' "$AL_FIRING"

MEM_PCT=97
_AL_PREV_STATE=()
alerts_evaluate
truthy 'high memory fires'      '(( AL_FIRING >= 1 ))'
truthy 'and it is critical'     '(( AL_CRIT >= 1 ))'
MEM_PCT=50

MP_PCT=([/]=38 [/var]=97)
_AL_PREV_STATE=()
alerts_evaluate
truthy 'full disk fires critical' '(( AL_CRIT >= 1 ))'
al_disk=0
for i in "${!AL_ID[@]}"; do [[ ${AL_ID[i]} == diskcrit_* ]] && al_disk=1; done
eq 'disk rule is per-mount' '1' "$al_disk"
MP_PCT=([/]=38 [/var]=71)

# Latency and loss come from the probe cache, and loss is critical because a
# relay node that cannot be reached is not earning.
LAT_MS=([1.1.1.1]=900000) LAT_LOSS=([1.1.1.1]=40)
_AL_PREV_STATE=()
alerts_evaluate
truthy 'high latency fires' 'frame_has_alert latency_high'
truthy 'packet loss fires'  'frame_has_alert packet_loss'
LAT_MS=([1.1.1.1]=8200) LAT_LOSS=([1.1.1.1]=0)

# Highway rules
CFG[highway_track]=on
HW_PRESENT=1 HW_FAILED=1 HW_UNIT_COUNT=1 HW_ACTIVE=0 HW_JOURNAL_ERR=0
HW_UNITS=(highway.service) HW_RESTARTS=([highway.service]=0) HW_NEBULA=nebula1
HW_UPDATE=0 HW_PID=1000
_AL_PREV_STATE=()
alerts_evaluate
truthy 'failed highway unit fires'  'frame_has_alert hw_failed'
truthy 'inactive highway unit fires' 'frame_has_alert hw_inactive'
HW_FAILED=0 HW_ACTIVE=1 HW_RESTARTS=([highway.service]=9)
_AL_PREV_STATE=()
alerts_evaluate
truthy 'crash-looping unit fires' 'frame_has_alert hw_restarts'
HW_RESTARTS=([highway.service]=0)
HW_NEBULA=''
_AL_PREV_STATE=()
alerts_evaluate
truthy 'missing mesh tunnel fires' 'frame_has_alert hw_tunnel_down'
HW_NEBULA=nebula1
CFG[highway_track]=off

# Notification gating: below min severity nothing goes out.
CFG[notify_channels]=stdout
CFG[alert_min_severity]=crit
_reset_alerts; _AL_PREV_STATE=(); _AL_PREV_NOTIFIED=()
_check_bool t_warn warn 1 'a warning'
alerts_notify 0 >"$TMP/notif.txt" 2>&1; out=$(cat "$TMP/notif.txt")
eq 'warn suppressed when min is crit' '0' "$AL_NOTIFY"
CFG[alert_min_severity]=warn
_reset_alerts; _AL_PREV_STATE=(); _AL_PREV_NOTIFIED=()
_check_bool t_warn warn 1 'a warning'
alerts_notify 0 >"$TMP/notif.txt" 2>&1; out=$(cat "$TMP/notif.txt")
eq 'warn delivered when min is warn' '1' "$AL_NOTIFY"
contains 'digest names the host' 'test-node' "$out"

# Cooldown: still firing, already notified a minute ago, must stay quiet.
_reset_alerts
_AL_PREV_STATE=([t_warn]=firing)
_AL_PREV_NOTIFIED=([t_warn]=$((${EPOCHSECONDS:-0} - 60)))
CFG[alert_repeat_hours]=6
_check_bool t_warn warn 1 'a warning'
alerts_notify 0 >"$TMP/notif.txt" 2>&1; out=$(cat "$TMP/notif.txt")
eq 'no re-notify inside the cooldown' '0' "$AL_NOTIFY"
# ...and speaks up again once the repeat window has passed.
_reset_alerts
_AL_PREV_STATE=([t_warn]=firing)
_AL_PREV_NOTIFIED=([t_warn]=$((${EPOCHSECONDS:-0} - 7 * 3600)))
_check_bool t_warn warn 1 'a warning'
alerts_notify 0 >"$TMP/notif.txt" 2>&1; out=$(cat "$TMP/notif.txt")
eq 'renotifies after the cooldown' '1' "$AL_NOTIFY"

# One message, not one per rule.
_reset_alerts; _AL_PREV_STATE=(); _AL_PREV_NOTIFIED=()
_check_bool t_a crit 1 'problem one'
_check_bool t_b warn 1 'problem two'
_check_bool t_c warn 1 'problem three'
alerts_notify 0 >"$TMP/notif.txt" 2>&1; out=$(cat "$TMP/notif.txt")
# A pipe, not a here-string: bash 5.3 routes <<< through a pipe, and on macOS
# the initial pipe buffer is 512 bytes, so a here-string of a multi-KB digest
# deadlocks before grep is exec'd.
eq 'three problems, one digest' '1' "$(printf '%s\n' "$out" | grep -c '^--- \[')"
contains 'digest subject counts them' '3 issues' "$out"
contains 'digest leads with severity' 'CRITICAL' "$out"
contains 'digest lists each problem' 'problem three' "$out"

# The daily send cap is the backstop against a flapping rule burning quota.
CFG[notify_max_per_day]=2
rm -f "$TMP/var/notify-budget"
notify_send info 'one' 'body' >/dev/null 2>&1
notify_send info 'two' 'body' >/dev/null 2>&1
falsy 'third send blocked by daily cap' 'notify_send info three body >/dev/null 2>&1'
CFG[notify_max_per_day]=50
rm -f "$TMP/var/notify-budget"

# ---------------------------------------------------------------------------
section 'daily report'
# ---------------------------------------------------------------------------
# Hand-built metric rows: cpu 10/20/30, mem 50/60/70, disk 80->82 over 24h,
# and rx_total climbing by 2000 bytes.
mf="$TMP/var/metrics.tsv"
now=${EPOCHSECONDS:-0}
: >"$mf"
printf '%s\t10\t1\t2\t50\t0\t420\t80\t100\t50\t1000\t500\t5\t8200\t6\t1\t1000\t10\t100\t0\n' $((now - 86400)) >>"$mf"
printf '%s\t20\t2\t4\t60\t0\t840\t81\t200\t60\t2000\t700\t7\t9000\t7\t1\t2000\t20\t150\t0\n' $((now - 43200)) >>"$mf"
printf '%s\t30\t3\t6\t70\t0\t1260\t82\t300\t70\t3000\t900\t9\t9500\t8\t1\t3000\t30\t200\t0\n' "$now" >>"$mf"
CFG[record_interval_min]=5
truthy 'aggregation succeeds' 'report_aggregate 24'
eq 'row count'        '3'    "$R_ROWS"
eq 'cpu average'      '20'   "${R[cpu_avg]}"
eq 'cpu peak'         '30'   "${R[cpu_max]}"
eq 'memory average'   '60'   "${R[mem_avg]}"
eq 'memory peak'      '70'   "${R[mem_max]}"
eq 'steal peak'       '3'    "${R[steal_max]}"
eq 'load average'     '840'  "${R[load_avg]}"
eq 'disk now'         '82'   "${R[disk_now]}"
eq 'disk 24h change'  '2'    "${R[disk_delta]}"
eq 'bytes received'   '2000' "${R[rx_bytes]}"
eq 'bytes sent'       '400'  "${R[tx_bytes]}"
eq 'peak rx rate'     '300'  "${R[rx_peak]}"
eq 'processes peak'   '200'  "${R[procs_max]}"
# 18 points of headroom growing 2 points/day is 9 days.
eq 'days until full'  '9'    "${R[disk_days]}"

# A counter that goes backwards means a reboot or NIC reset. The day's transfer
# must not come out negative.
printf '%s\t10\t0\t0\t50\t0\t100\t82\t10\t10\t50\t20\t0\t0\t0\t1\t0\t0\t10\t0\n' $((now + 1)) >>"$mf"
report_aggregate 24
truthy 'transfer never goes negative' '(( ${R[rx_bytes]} >= 0 ))'

# Rows older than the window are excluded.
printf '%s\t99\t0\t0\t99\t0\t100\t99\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n' $((now - 200000)) >>"$mf"
report_aggregate 24
falsy 'stale rows excluded from peak' '(( ${R[cpu_max]} == 99 ))'

# Alert log feeds the report's alert section.
: >"$TMP/var/alert-log"
printf '%s\tcrit\tdisk_full\tDisk /var critically full\n' $((now - 3600)) >>"$TMP/var/alert-log"
printf '%s\twarn\tmem_high\tMemory at 91%%\n' $((now - 1800)) >>"$TMP/var/alert-log"
report_alerts 24
eq 'alert log rows'  '2' "${#RA_TS[@]}"
eq 'critical counted' '1' "$RA_CRIT"
eq 'warning counted'  '1' "$RA_WARN"

# The report itself must render, and must contain the sections that make it
# worth reading rather than just not crashing.
rep=$(report_text 24)
contains 'report names the host'     'test-node'   "$rep"
contains 'report has a verdict'      'ATTENTION'   "$rep"
contains 'report has performance'    'PERFORMANCE' "$rep"
contains 'report has storage'        'STORAGE'     "$rep"
contains 'report has network'        'NETWORK'     "$rep"
contains 'report has alerts'         'ALERTS'      "$rep"
contains 'report shows disk trend'   'projection'  "$rep"
contains 'report lists a real alert' 'critically full' "$rep"
truthy  'report is substantial'      '(( $(printf "%s\n" "$rep" | wc -l) > 25 ))'

reph=$(report_html 24)
contains 'html report has a wrapper' '<div'      "$reph"
contains 'html report names host'    'test-node' "$reph"
falsy 'html escapes stray angle brackets' '[[ $(html_escape "<b>") == *"<b>"* ]]'
eq 'html_escape converts ampersand' 'a&amp;b' "$(html_escape 'a&b')"
# Pins the bash 5.2 replacement-& behaviour. Written with an UNQUOTED replacement,
# ${s//</&lt;} yields "<lt;" on bash >= 5.2 because & means "the matched text"
# there -- which silently broke escaping on Ubuntu 24.04 and would let a crafted
# hostname or journal line inject markup into an operator's email.
eq 'escapes < and >'        'a&lt;b&gt;c'      "$(html_escape 'a<b>c')"
eq 'escapes a full tag'     '&lt;script&gt;'   "$(html_escape '<script>')"
eq 'escapes & before < >'   '&amp;lt;'         "$(html_escape '&lt;')"
eq 'escapes double quotes'  '&quot;x&quot;'    "$(html_escape '"x"')"
falsy 'no literal <lt; artefact' '[[ $(html_escape "<") == *"<lt;"* ]]'
eq 'plain text is untouched' 'hello world'     "$(html_escape 'hello world')"

# Verdict must reflect severity, not just say something cheerful.
RA_CRIT=0 RA_WARN=0 RA_TS=()
R[disk_days]=0 R[hw_up_pct]=100
contains 'healthy verdict' 'HEALTHY' "$(_verdict)"
RA_WARN=2
contains 'warning verdict' 'MOSTLY HEALTHY' "$(_verdict)"
RA_CRIT=1
contains 'critical verdict' 'ATTENTION' "$(_verdict)"
RA_CRIT=0 RA_WARN=0
R[disk_days]=3
contains 'disk projection verdict' 'PLAN AHEAD' "$(_verdict)"
R[disk_days]=0

# The crash a user actually hit: on a fresh install report_aggregate finds no
# samples, so R is entirely empty, and _verdict read R[disk_days] with no default.
# Bash expands BOTH operands of `((a && b))` before evaluating, so the `&&` did
# not protect the second reference and `set -u` aborted mid-email — three times,
# once per _verdict call. Every R lookup outside an R_ROWS>0 block must be
# defaulted.
mv "$mf" "$mf.saved"
R=(); R_ROWS=0; RA_CRIT=0; RA_WARN=0; RA_TS=()
falsy 'aggregation reports no data' 'report_aggregate 24'
eq 'no rows counted' '0' "$R_ROWS"
v_out=$(_verdict 2>&1)
falsy 'verdict has no unbound-variable error' '[[ $v_out == *"unbound variable"* ]]'
contains 'verdict says there is no history' 'NO HISTORY' "$v_out"
# The whole report must render on a fresh install, not just the verdict.
t_out=$(report_text 24 2>&1)
falsy 'text report has no unbound error' '[[ $t_out == *"unbound variable"* ]]'
contains 'text report explains the gap' 'none recorded yet' "$t_out"
h_out=$(report_html 24 2>&1)
falsy 'html report has no unbound error' '[[ $h_out == *"unbound variable"* ]]'
contains 'html report explains the gap' 'No samples recorded yet' "$h_out"
# And with alerts present but still no metrics.
RA_CRIT=1
v_out=$(_verdict 2>&1)
contains 'alerts still win the verdict' 'ATTENTION' "$v_out"
RA_CRIT=0
mv "$mf.saved" "$mf"
report_aggregate 24

# ---------------------------------------------------------------------------
section 'accounts and access'
# ---------------------------------------------------------------------------
sys_whoami
truthy 'running-as user resolved' '[[ -n $RUN_AS ]]'
eq 'uid matches EUID' "${EUID:-0}" "$RUN_UID"
# Resolution must fall through to NSS. A local account is in /etc/passwd, but an
# LDAP/SSSD/AD account on a managed server is not, and neither is any account on
# macOS (Directory Services). Without the getent fallback those all render as a
# bare number.
_UIDNAME=()
_uid_name_v 0
eq 'uid 0 resolves to root' 'root' "$UID_NAME"
# sys_whoami must always produce a NAME, even where the uid is in neither
# /etc/passwd nor NSS (macOS Directory Services, and some managed Linux setups).
_UIDNAME=()
sys_whoami
falsy 'running-as is never a bare number' '[[ $RUN_AS == "${EUID:-0}" ]]'
# $USER/$LOGNAME are not trusted: they survive into a sudo shell still naming the
# original human while EUID is 0, which would misreport who the timer ran as.
USER=someoneelse LOGNAME=someoneelse sys_whoami
falsy 'stale USER is not believed' '[[ $RUN_AS == someoneelse ]]'
SUDO_USER=realperson sys_whoami
eq 'sudo invoker recorded separately' 'realperson' "$LOGIN_USER"
unset SUDO_USER
sys_whoami
eq 'no invoker without sudo' '' "$LOGIN_USER"
_UIDNAME=()
_uid_name_v 4294967000
eq 'an unknown uid falls back to the number' '4294967000' "$UID_NAME"
truthy 'lookups are cached' '[[ -v _UIDNAME[4294967000] ]]'
_UIDNAME=()
# `who` output parsing: a remote session reports its host in parentheses, a local
# console session reports none.
_parse_who() {
  SESS_USER=() SESS_TTY=() SESS_FROM=() SESS_WHEN=()
  local u tty d t rest host
  while read -r u tty d t rest; do
    [[ -n $u && -n $tty ]] || continue
    host='local'
    if [[ $rest == *'('*')'* ]]; then
      host=${rest#*\(}; host=${host%%\)*}
    fi
    [[ -z $host ]] && host='local'
    SESS_USER+=("$u") SESS_TTY+=("$tty") SESS_FROM+=("$host") SESS_WHEN+=("$d $t")
  done
}
printf '%s\n' \
  'vivek    pts/0        2026-08-07 10:30 (192.168.1.5)' \
  'root     pts/1        2026-08-07 11:02 (10.0.0.9)' \
  'console  tty1         2026-08-06 22:11' \
  > "$TMP/who.txt"
_parse_who < "$TMP/who.txt"
eq 'three sessions parsed'   '3'             "${#SESS_USER[@]}"
eq 'first user'              'vivek'         "${SESS_USER[0]}"
eq 'first tty'               'pts/0'         "${SESS_TTY[0]}"
eq 'remote host extracted'   '192.168.1.5'   "${SESS_FROM[0]}"
eq 'second remote host'      '10.0.0.9'      "${SESS_FROM[1]}"
eq 'local session has no host' 'local'       "${SESS_FROM[2]}"
contains 'login time captured' '2026-08-07 10:30' "${SESS_WHEN[0]}"

# The report must name the account and list the sessions.
RUN_AS=root RUN_UID=0 LOGIN_USER=vivek
FAILED_LOGINS=1284 FAILED_LOGIN_TOP='203.0.113.9 (900x)'
acc=$(report_access_text 24)
contains 'access section names the account'  'ran as' "$acc"
contains 'access section names root'          'root'       "$acc"
contains 'access section names the invoker'   'vivek'      "$acc"
contains 'access section lists a session'     'pts/0'      "$acc"
contains 'access section shows the source'    '192.168.1.5' "$acc"
contains 'access section counts rejections'   '1284'       "$acc"
contains 'access section names worst offender' '203.0.113.9' "$acc"
# A number that is never zero needs the caveat, or it reads as an incident.
contains 'rejections are put in context' 'watch the trend' "$acc"
SESS_USER=() SESS_TTY=() SESS_FROM=() SESS_WHEN=()
acc=$(report_access_text 24)
contains 'empty session list is explicit' 'nobody' "$acc"
FAILED_LOGINS=0 FAILED_LOGIN_TOP=''
_parse_who < "$TMP/who.txt"

# ---------------------------------------------------------------------------
section 'email rendering'
# ---------------------------------------------------------------------------
# Trend series feed the sparklines and must be downsampled, or 288 samples
# becomes 288 characters and wraps into noise on a phone.
truthy 'cpu trend series built'  '((${#RH_CPU[@]} > 0))'
truthy 'trend is downsampled'    '((${#RH_CPU[@]} <= RH_BUCKETS))'
declare -a BIG=()
for i in $(seq 1 500); do BIG+=("$i"); done
_downsample BIG DS
eq 'downsample caps at the bucket count' "$RH_BUCKETS" "${#DS[@]}"
truthy 'downsample preserves direction' '((${DS[0]} < ${DS[-1]}))'
declare -a SMALL=(5 6 7)
_downsample SMALL DS2
eq 'short series passes through' '3' "${#DS2[@]}"

# Severity colours must be distinct, or the design conveys nothing.
truthy 'crit and warn differ' '[[ $(e_sevcolor crit) != $(e_sevcolor warn) ]]'
truthy 'warn and ok differ'   '[[ $(e_sevcolor warn) != $(e_sevcolor ok) ]]'
eq 'low usage is green'  "$E_OK"   "$(e_level 10)"
eq 'high usage is amber' "$E_WARN" "$(e_level 75)"
eq 'full is red'         "$E_CRIT" "$(e_level 95)"
eq 'garbage is muted'    "$E_MUTED" "$(e_level abc)"

# Email HTML has to survive clients that strip <style>, so structure must be
# tables with inline styles and bars must be coloured table cells.
h=$(report_html 24)
contains 'email uses table layout'      '<table role="presentation"' "$h"
contains 'email styles are inline'      'style="' "$h"
falsy   'email has no style block'      '[[ $h == *"<style"* ]]'
falsy   'email has no external image'   '[[ $h == *"<img"* ]]'
falsy   'email avoids flexbox'          '[[ $h == *"display:flex"* ]]'
contains 'email has a preheader'        'display:none' "$h"
contains 'email has KPI figures'        'CPU avg' "$h"
contains 'email has a bar'              'border-radius:4px' "$h"
contains 'email has the alerts section' 'Alerts' "$h"
contains 'email has connection detail'  'Connection' "$h"
contains 'email credits the author'     'Vivek W (AryanVBW)' "$h"
contains 'email has the access section' 'Access' "$h"
contains 'email names the account'      'Report ran as' "$h"
contains 'email lists the session user' 'vivek' "$h"
# Escaping still applies to every interpolated value.
HOSTNAME_S='evil<script>alert(1)</script>'
h=$(report_html 24)
falsy 'hostname is escaped in html' '[[ $h == *"<script>"* ]]'
contains 'hostname escaped safely' '&lt;script&gt;' "$h"
HOSTNAME_S='test-node'

# The alert email renders with the same components.
_reset_alerts; _AL_PREV_STATE=(); _AL_PREV_NOTIFIED=()
_check_bool e_a crit 1 'disk /var critically full'
_check_bool e_b warn 1 'memory at 91%'
ah=$(alerts_html "0" "1" crit)
contains 'alert email has a severity pill' 'CRITICAL' "$ah"
contains 'alert email has resource bars'   'Resources' "$ah"
contains 'alert email explains silencing'  'silence' "$ah"
contains 'alert email credits the author'  'AryanVBW' "$ah"
contains 'alert email names the account'   'Running as' "$ah"
contains 'alert email lists sessions'      'Session' "$ah"
# A session from an address the operator does not recognise is a security signal,
# so the source must survive into the alert, not just the report.
contains 'alert email shows session source' '192.168.1.5' "$ah"
falsy   'alert email has no style block'   '[[ $ah == *"<style"* ]]'
_reset_alerts

# ---------------------------------------------------------------------------
section 'first-run onboarding'
# ---------------------------------------------------------------------------
# First run means no config AND no marker. Either signal alone gets it wrong:
# a user who declined has no config either and must not be asked again, and
# `sudo hyn setup` writes a config without ever touching the marker.
ob_etc="$HYN_ETC/config"
ob_marker=$(onboard_marker)
rm -f "$ob_etc" "$ob_marker"
truthy 'fresh install is a first run' 'is_first_run'

printf 'theme=nord\n' >"$ob_etc"
falsy 'existing config is not a first run' 'is_first_run'
rm -f "$ob_etc"
truthy 'first run again once config is gone' 'is_first_run'

onboard_mark_done skipped
truthy 'marker is written' '[[ -r $ob_marker ]]'
falsy 'a remembered decline is not re-asked' 'is_first_run'
contains 'marker records the outcome' 'skipped' "$(cat "$ob_marker")"
onboard_mark_done completed
contains 'marker updates the outcome' 'completed' "$(cat "$ob_marker")"
rm -f "$ob_marker"

# The onboarding prompt is opt-out via config.
eq 'onboarding defaults on' 'on' "${CFG[onboarding]}"
CFG[onboarding]=off
falsy 'onboarding can be disabled' 'cfg_on onboarding'
CFG[onboarding]=on
truthy 'onboarding re-enabled' 'cfg_on onboarding'

# The wizard file must load cleanly and expose both entry points: the full
# first-run flow and the notifications-only re-run.
source "$HYN_LIB/wizard.sh"
truthy 'onboard_run exists'    'declare -F onboard_run >/dev/null'
truthy 'onboard_prompt exists' 'declare -F onboard_prompt >/dev/null'
truthy 'wizard_run exists'     'declare -F wizard_run >/dev/null'
truthy 'detection helper exists' 'declare -F onboard_detect >/dev/null'
# Non-interactive must be refused rather than hanging waiting for stdin.
W_TTY=0
falsy 'onboarding refuses a non-tty' 'onboard_run'
falsy 'prompt refuses a non-tty'     'onboard_prompt'

# Validators used by the prompts.
truthy 'accepts a valid time'    '_v_hhmm 08:30'
truthy 'accepts midnight'        '_v_hhmm 00:00'
truthy 'accepts 23:59'           '_v_hhmm 23:59'
falsy  'rejects hour 24'         '_v_hhmm 24:00'
falsy  'rejects minute 60'       '_v_hhmm 12:60'
falsy  'rejects a bare hour'     '_v_hhmm 8'
truthy 'accepts a long topic'    '_v_topic hyn-abc123456'
falsy  'rejects a short topic'   '_v_topic short'
falsy  'rejects a topic with a slash' '_v_topic "abc/def12345"'
truthy 'accepts an https url'    '_v_url https://example.com/ping'
falsy  'rejects a non-url'       '_v_url notaurl'
truthy 'accepts a hostname'      '_v_host smtp.gmail.com'
falsy  'rejects a host with a space' '_v_host "bad host"'

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
