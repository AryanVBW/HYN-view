#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_PROC="$WORK/proc"
export HYN_VAR="$WORK/state" HYN_ETC="$WORK/etc" XDG_STATE_HOME="$WORK/user-state"
mkdir -p "$HYN_PROC/net" "$HYN_PROC/sys/kernel/random"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/net.sh"
source "$ROOT/lib/cloud.sh"
source "$ROOT/test/flock-fixture.sh"
is_root() { return 0; }
printf 'boot-test\n' >"$HYN_PROC/sys/kernel/random/boot_id"
printf 'eth0: 1024 0 0 0 0 0 0 0 2048 0 0 0 0 0 0 0\n' >"$HYN_PROC/net/dev"
CFG[wan_iface]=eth0
_jstr() { printf '%s' "$1"; }
_cloud_rpc() { printf '%s\n%s\n' "$1" "$2" >"$WORK/request"; CLOUD_LAST_BODY=changed; return 1; }
CLOUD_LAST_BODY=heartbeat-ok
cloud_record_bandwidth fixture-token
[[ $CLOUD_LAST_BODY == heartbeat-ok ]]
python3 - "$WORK/request" <<'PY'
import json,sys
lines=open(sys.argv[1]).read().splitlines()
assert lines[0]=='hyn_record_bandwidth'
p=json.loads(lines[1])
assert p=={'p_node_token':'fixture-token','p_iface':'eth0','p_boot_id':'boot-test','p_rx':1024,'p_tx':2048}
PY
printf 'PASS  WAN counters report exact bytes without changing successful heartbeat state\n'
rm "$WORK/request"
CFG[wan_iface]='../../etc'
cloud_record_bandwidth fixture-token
[[ ! -e $WORK/request ]]
printf 'PASS  invalid interface is ignored without reading arbitrary paths\n'

CFG[wan_iface]=auto
printf 'eth0 00000000 00000000 0001 0 0 100 00000000 0 0 0\n' >"$HYN_PROC/net/route"
net_find_wan
[[ $NET_WAN == eth0 ]]
printf 'eth1 00000000 00000000 0001 0 0 50 00000000 0 0 0\n' >"$HYN_PROC/net/route"
net_sample 0
[[ $NET_WAN == eth1 ]]
printf 'PASS  WAN selection follows changed on-link default routes\n'
rm "$HYN_PROC/net/route"
printf '%s\n' \
 '00000000000000000000000000000000 00 00000000000000000000000000000000 00 00000000000000000000000000000000 ffffffff 00000001 00000000 00200200 lo' \
 '00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000001 00000400 00000001 00000000 00000003 eth6' \
 '00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000002 00000800 00000001 00000000 00000003 eth7' >"$HYN_PROC/net/ipv6_route"
net_find_wan
[[ $NET_WAN == eth6 ]]
printf 'PASS  IPv6-only WAN discovery selects the lowest metric and skips reject routes\n'

delta_rate boundary 18446744073709551000 1000
delta_rate boundary 18446744073709551500 1250
[[ $DELTA_RAW == 500 && $DELTA_RATE == 400 && $DELTA_VALID == 1 ]]
delta_rate overflow 0 1000
delta_rate overflow 10000000000000000 1250
[[ $DELTA_RAW == 10000000000000000 && $DELTA_RATE == 8000000000000000 ]]
delta_rate reset 900 1000
delta_rate reset 10 1000
[[ $DELTA_RAW == 0 && $DELTA_RATE == 0 && $DELTA_VALID == 0 ]]
printf 'PASS  uint64 counter deltas and rate multiplication never overflow or round\n'

CFG[wan_iface]=eth0
printf 'eth0: 100 0 0 0 0 0 0 0 50 0 0 0 0 0 0 0\n' >"$HYN_PROC/net/dev"
net_sample 0
: >"$HYN_PROC/net/dev"
net_sample 1000
[[ ! -v NET_RX[eth0] ]]
printf 'eth0: 900000 0 0 0 0 0 0 0 800000 0 0 0 0 0 0 0\n' >"$HYN_PROC/net/dev"
net_sample 1000
[[ ${NET_RXR[eth0]} == 0 && ${NET_TXR[eth0]} == 0 ]]
printf 'PASS  disappearing and reappearing NICs cannot reuse a stale rate baseline\n'

source "$ROOT/lib/report.sh"
metrics_file() { printf '%s/metrics.tsv' "$WORK"; }
now=${EPOCHSECONDS:-0}
row() { printf '%s\t10\t0\t0\t50\t0\t100\t20\t0\t0\t%s\t%s\t0\t0\t0\t0\t0\t0\t0\t0\t-\t%s\t%s\n' "$now" "$1" "$2" "$3" "$4" >>"$WORK/metrics.tsv"; }
row 100 50 boot-1 eth0
row 200 80 boot-1 eth0
row 9000 4000 boot-1 eth1
row 9050 4020 boot-1 eth1
row 9900 5000 boot-2 eth1
row 9950 5020 boot-2 eth1
report_aggregate 24 || exit 1
[[ ${R[rx_bytes]} == 200 && ${R[tx_bytes]} == 70 && ${R[network_resets]} == 2 && ${R[pwr_n]} == 0 ]]
printf 'PASS  reports preserve exact observed deltas across interface changes and reboots with larger counters\n'
