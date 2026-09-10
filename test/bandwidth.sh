#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_PROC="$WORK/proc"
mkdir -p "$HYN_PROC/net" "$HYN_PROC/sys/kernel/random"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/net.sh"
source "$ROOT/lib/cloud.sh"
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
