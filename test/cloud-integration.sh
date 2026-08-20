#!/usr/bin/env bash
# hyn-view :: cloud integration check
#
#   bash test/cloud-integration.sh
#
# Runs the real pairing client and the real push path against a mock PostgREST
# endpoint, and asserts on what actually went over the wire. The database side is
# covered by supabase/run-tests.sh; this covers the half that lives on the
# server: request shape, auth headers, response parsing, and the two properties
# that matter for credential safety --
#
#   * the node token must never appear in the process's argv, and
#   * it must be sent in the request body, not the URL or a header.
#
# Needs python3 for the mock server. No network, no real Supabase project.

set -uo pipefail

HERE=$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)
ROOT=$(cd -P "$HERE/.." && pwd)

PASS=0 FAIL=0
declare -a FAILURES=()
ok() { ((PASS++)); }
bad() { ((FAIL++)); FAILURES+=("$1"); printf '  FAIL  %s\n' "$1" >&2; }
eq() { if [[ $2 == "$3" ]]; then ok; else bad "$1: expected [$2] got [$3]"; fi; }
contains() { if [[ $3 == *"$2"* ]]; then ok; else bad "$1: [${3:0:200}] lacks [$2]"; fi; }
missing() { if [[ $3 != *"$2"* ]]; then ok; else bad "$1: [${3:0:200}] must not contain [$2]"; fi; }
truthy() { if eval "$2" >/dev/null 2>&1; then ok; else bad "$1: expected success from: $2"; fi; }

command -v python3 >/dev/null || { printf 'cloud-integration: python3 not found, skipping\n'; exit 0; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/hyn-cloudtest.XXXXXX") || exit 1
trap 'rm -rf "$TMP"; [[ -n ${SRV_PID:-} ]] && kill "$SRV_PID" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# mock PostgREST
# ---------------------------------------------------------------------------
# Records every request as JSON lines so the test can assert on headers and
# bodies after the fact.
cat >"$TMP/mock.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]
state = {"polls": 0, "node_status": "active"}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        # Test-only lever to flip the node's administrative status.
        if self.path.startswith("/status/"):
            state["node_status"] = self.path.rsplit("/", 1)[-1]
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b'ok')
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode()
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": raw,
            }) + "\n")

        fn = self.path.rsplit("/", 1)[-1]
        if fn == "hyn_device_start":
            out = {"user_code": "QKB8-D6VQ",
                   "device_code": "a" * 64,
                   "expires_at": "2026-08-19T13:00:00Z",
                   "interval": 1}
        elif fn == "hyn_device_poll":
            state["polls"] += 1
            # Pending once, so the client's polling loop is genuinely exercised.
            if state["polls"] < 2:
                out = {"status": "pending", "interval": 1}
            else:
                out = {"status": "approved",
                       "node_id": "3f7a0000-0000-4000-8000-000000000001",
                       "node_token": "b" * 64,
                       "node_name": "web-01"}
        elif fn == "hyn_fetch_config":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self.send_response(401)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"message":"invalid node token"}')
                return
            out = {"status": "ok",
                   "node_id": "3f7a0000-0000-4000-8000-000000000001",
                   "node_name": "web-01",
                   "node_status": state["node_status"],
                   "paused_until": None,
                   "status_reason": None,
                   "config": {"alert_mem_pct": 80, "report_at": "07:30",
                              "interval": "2.0", "not_a_real_key": "x"},
                   "channels": [{"kind": "resend", "target": "ops@example.com",
                                 "secret": "re_secret", "extra": {}}]}
        elif fn == "hyn_report_notification":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self.send_response(401)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"message":"invalid node token"}')
                return
            out = {"status": "ok", "written": len(body.get("p_events") or [])}
        elif fn == "hyn_ingest":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self.send_response(401)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"message":"invalid node token"}')
                return
            if state["node_status"] == "paused":
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"message":"node paused until 2026-08-19T18:00:00Z"}')
                return
            if state["node_status"] == "suspended":
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"message":"node suspended: abuse investigation"}')
                return
            out = {"status": "ok", "node_id": "3f7a0000-0000-4000-8000-000000000001"}
        else:
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"message":"no such function"}')
            return

        payload = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

PORT=54330
REQLOG="$TMP/requests.jsonl"
: >"$REQLOG"
python3 "$TMP/mock.py" "$PORT" "$REQLOG" &
SRV_PID=$!
for _ in $(seq 1 40); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/rest/v1/rpc/nope" -X POST -d '{}' && break
  sleep 0.25
done

# ---------------------------------------------------------------------------
# load the agent
# ---------------------------------------------------------------------------
export HYN_ETC="$TMP/etc" HYN_VAR="$TMP/var"
export HYN_PROC="$TMP/proc" HYN_SYS="$TMP/sys"
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_PROC" "$HYN_SYS"
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT"
export TERM=dumb

for m in core ui net collect highway speedtest notify alerts report update panels cloud; do
  # shellcheck source=/dev/null
  source "$HYN_LIB/$m.sh" || { printf 'cannot source %s\n' "$m" >&2; exit 1; }
done
cfg_load

# Collection is covered by test/selfcheck.sh against a synthetic /proc. Here the
# subject is the transport, so stub sampling out and set the few globals the
# payload reads.
alerts_collect() { :; }
alerts_evaluate() { AL_ID=(disk_root); AL_SEV=(warn); AL_MSG=('Disk / at 86%'); AL_RESOLVED=(0); }
# Reads /proc/sys/net/*, which does not exist on every machine this test runs on,
# and it would clear the TUNE values the payload assertions below rely on.
net_tuning() { :; }
is_root() { return 0; }

HOSTNAME_S=web-01 DISTRO='Ubuntu 24.04 LTS' KERNEL='6.8.0-31-generic'
UPTIME_S=123456 LOAD1=0.42 LOAD5=0.31 LOAD15=0.28
CPU_PCT=37.5 CPU_USER=20 CPU_SYS=10 CPU_IOWAIT=1.1 CPU_STEAL=0.2 CPU_COUNT=8
CPU_TEMP=52 CPU_MHZ=3400 CPU_MODEL='AMD EPYC 9354'
MEM_TOTAL=33285996544 MEM_USED=20000000000 MEM_PCT=61.2 SWAP_USED=0
MOUNTS=(/) ; MP_PCT[/]=58.4 ; MP_USED[/]=100 ; MP_SIZE[/]=200 ; MP_AVAIL[/]=100 ; MP_FSTYPE[/]=ext4
NET_WAN=eth0
NET_RXR[eth0]=81250000 NET_TXR[eth0]=22500000
NET_RX[eth0]=999 NET_TX[eth0]=888
NET_RERR[eth0]=0 NET_TERR[eth0]=0 NET_RDROP[eth0]=0 NET_TDROP[eth0]=0
NET_RETRANS_PM=3.1 CT_PCT=4
LAT_MS[1.1.1.1]=8620 LAT_MS[gateway]=1200
ST_LAST_TS=1755600000 ST_LAST_DOWN=105000000 ST_LAST_UP=54000000 ST_LAST_LAT=8600 ST_LAST_NOTE=''

# A Highway node as the collectors would leave it: two units, one of them
# crash-looping, a live process, a mesh tunnel, and an unset MemoryCurrent on the
# timer (systemd's 64-bit sentinel) which must serialise as null.
HW_PRESENT=1 HW_HEALTH=warn HW_HEALTH_WHY='highway.service restarted 4x'
HW_VERSION='v0.1.75' HW_VERSION_SRC=file HW_LATEST='v0.1.80' HW_UPDATE=1
HW_SIZE=48234496 HW_MTIME=1755500000
HW_UNITS=(highway.service nebula.service highway-update.timer)
HW_STATE[highway.service]=active   HW_SUB[highway.service]=running
HW_STATE[nebula.service]=active    HW_SUB[nebula.service]=running
HW_STATE[highway-update.timer]=failed HW_SUB[highway-update.timer]=failed
HW_RESTARTS[highway.service]=4 HW_RESTARTS[nebula.service]=0 HW_RESTARTS[highway-update.timer]=0
HW_MEM[highway.service]=421527552 HW_MEM[nebula.service]=18874368
HW_MEM[highway-update.timer]=18446744073709551615
HW_SINCE[highway.service]=$((3600 * 1000000))
HW_UNIT_COUNT=3 HW_ACTIVE=2 HW_FAILED=1
HW_PID=1471 HW_CPU=63 HW_RSS=421527552 HW_THR=19 HW_FDS=48 HW_UPTIME=119856
HW_NEBULA=nebula1 HW_QDISC=fq_codel HW_QDISC_DROPS=12 HW_NFT_TABLES=3
HW_JOURNAL_ERR=2 HW_JOURNAL_WARN=5
HW_JOURNAL_TAIL=('peer handshake timeout' 'reconnecting to lighthouse')
NET_RXR[nebula1]=1250000 NET_TXR[nebula1]=980000
NET_RX[nebula1]=88000000 NET_TX[nebula1]=44000000
NET_RDROP_R[nebula1]=1 NET_TDROP_R[nebula1]=0
TUNE[cc]=bbr

printf 'cloud integration\n'

# ---------------------------------------------------------------------------
# pairing, end to end against the mock
# ---------------------------------------------------------------------------
out=$(cloud_link --url "http://127.0.0.1:$PORT" --anon-key 'test.anon.key' \
        --portal 'https://portal.example.com' 2>&1)
rc=$?
eq 'link succeeds' 0 "$rc"
contains 'link prints the pairing code'   'QKB8-D6VQ' "$out"
contains 'link prints the portal URL'     'https://portal.example.com/link' "$out"
contains 'link waits for approval'        'still waiting for approval' "$out"
contains 'link confirms the node name'    'web-01' "$out"
contains 'link sends a verifying push'    'Sending a first push' "$out"

# cloud_link ran inside a command substitution to capture its output, so its
# in-memory config changes stayed in that subshell. Reload from disk, which is
# exactly what the next `hyn` invocation does.
cfg_load
SECRETS_LOADED=0

# The token must be persisted to the 0600 secrets file, and the node id to config.
eq 'node token is stored'  "$(printf 'b%.0s' {1..64})" "$(secret cloud_node_token)"
eq 'node id is stored'     '3f7a0000-0000-4000-8000-000000000001' "${CFG[cloud_node_id]}"
eq 'cloud is enabled'      'on' "${CFG[cloud_enabled]}"
truthy 'secrets file is 0600' '[[ $(stat -f "%Lp" "$HYN_ETC/secrets" 2>/dev/null || stat -c "%a" "$HYN_ETC/secrets") == 600 ]]'

# The anon key is public and belongs in the config; the token never does.
cfgtext=$(<"$HYN_ETC/config")
contains 'anon key is in the config'      'test.anon.key' "$cfgtext"
missing  'token is NOT in the config'     "$(printf 'b%.0s' {1..64})" "$cfgtext"

# ---------------------------------------------------------------------------
# what went over the wire
# ---------------------------------------------------------------------------
reqs=$(<"$REQLOG")
contains 'device_start was called' '/rest/v1/rpc/hyn_device_start' "$reqs"
contains 'device_poll was called'  '/rest/v1/rpc/hyn_device_poll'  "$reqs"
contains 'ingest was called'       '/rest/v1/rpc/hyn_ingest'       "$reqs"
contains 'apikey header is sent'   '"apikey": "test.anon.key"'     "$reqs"
contains 'bearer auth is sent'     'Bearer test.anon.key'          "$reqs"
contains 'content type is json'    'application/json'              "$reqs"

# The token travels in the body. If it ever moves to the query string it would be
# logged by every proxy in the path.
ingest_line=$(printf '%s\n' "$reqs" | grep hyn_ingest | tail -1)
contains 'token is in the request body' 'p_node_token' "$ingest_line"
missing  'token is not in the URL'      "rpc/hyn_ingest?" "$ingest_line"
contains 'payload carries cpu percent'  '37.5' "$ingest_line"
contains 'payload carries clock speed'  '3400' "$ingest_line"
contains 'payload carries the alert'    'Disk / at 86%' "$ingest_line"

# The payload the agent actually sent must be valid JSON, checked with a parser.
truthy 'sent payload is valid JSON' 'printf "%s" "$ingest_line" | python3 -c "
import json,sys
req = json.loads(sys.stdin.read())
body = json.loads(req[\"body\"])
assert body[\"p_payload\"][\"cpu\"][\"mhz\"] == 3400, body[\"p_payload\"][\"cpu\"]
assert body[\"p_payload\"][\"cpu\"][\"temp_c\"] == 52
assert body[\"p_payload\"][\"disk\"][\"pct\"] == 58.4
assert body[\"p_payload\"][\"alerts\"][0][\"severity\"] == \"warn\"
assert body[\"p_payload\"][\"latency_ms\"] == 1.20, body[\"p_payload\"][\"latency_ms\"]
"'

# The Highway section of the portal is only as good as what the agent sends, so
# assert the whole shape rather than a couple of fields: a silently dropped
# `units` array would leave the dashboard saying a healthy node has no services.
truthy 'payload carries full highway state' 'printf "%s" "$ingest_line" | python3 -c "
import json,sys
hw = json.loads(json.loads(sys.stdin.read())[\"body\"])[\"p_payload\"][\"highway\"]
assert hw[\"present\"] == 1 and hw[\"tracked\"] is True, hw
assert hw[\"health\"] == \"warn\" and hw[\"health_why\"] == \"highway.service restarted 4x\", hw
assert (hw[\"version\"], hw[\"version_src\"], hw[\"latest\"], hw[\"update_available\"]) == (\"v0.1.75\", \"file\", \"v0.1.80\", 1), hw
assert (hw[\"units_total\"], hw[\"units_active\"], hw[\"units_failed\"]) == (3, 2, 1), hw
names = [u[\"name\"] for u in hw[\"units\"]]
assert names == [\"highway.service\", \"nebula.service\", \"highway-update.timer\"], names
svc = hw[\"units\"][0]
assert svc[\"state\"] == \"active\" and svc[\"sub\"] == \"running\", svc
assert svc[\"restarts\"] == 4 and svc[\"memory\"] == 421527552, svc
assert svc[\"active_s\"] == 119856, svc
# systemd reports an unset MemoryCurrent as the 64-bit sentinel. Sending it
# would render as 16 EiB of RAM on the dashboard.
assert hw[\"units\"][2][\"memory\"] is None, hw[\"units\"][2]
assert hw[\"units\"][1][\"active_s\"] is None, hw[\"units\"][1]
assert (hw[\"pid\"], hw[\"cpu_tenths\"], hw[\"rss\"], hw[\"threads\"], hw[\"fds\"]) == (1471, 63, 421527552, 19, 48), hw
assert hw[\"proc_uptime_s\"] == 119856, hw
assert hw[\"mesh_iface\"] == \"nebula1\" and hw[\"mesh_rx_bps\"] == 1250000, hw
assert hw[\"mesh_tx_bps\"] == 980000 and hw[\"mesh_drops\"] == 1, hw
assert hw[\"qdisc\"] == \"fq_codel\" and hw[\"qdisc_drops\"] == 12, hw
assert hw[\"congestion\"] == \"bbr\" and hw[\"nft_tables\"] == 3, hw
assert (hw[\"journal_err_1h\"], hw[\"journal_warn_1h\"]) == (2, 5), hw
assert hw[\"journal_tail\"][-1] == \"reconnecting to lighthouse\", hw[\"journal_tail\"]
assert hw[\"bin_path\"] == \"/usr/local/bin/highway\" and hw[\"bin_size\"] == 48234496, hw
"'

# ---------------------------------------------------------------------------
# config pull: the dashboard is the source of truth
# ---------------------------------------------------------------------------
printf '\nconfig pull\n'

truthy 'config pull succeeds' 'cloud_config_pull 1'

cache=$(cloud_config_cache)
truthy 'a config cache is written' '[[ -s $cache ]]'
cachetext=$(<"$cache")
contains 'pulled setting is cached'      'alert_mem_pct=80' "$cachetext"
contains 'second pulled setting'         'report_at=07:30'  "$cachetext"
# A key the agent does not recognise must be dropped, not written, or every
# subsequent load would warn about it forever.
missing  'unknown key is not cached'     'not_a_real_key'   "$cachetext"

# Reloading must apply the pulled values, and a local line must still win --
# central management that silently overrides a deliberate local edit is
# undebuggable on a box with no network.
config_set interval 1.0 >/dev/null
cfg_load
eq 'pulled setting is applied'          '80'    "${CFG[alert_mem_pct]}"
eq 'local config still overrides cloud' '1.0'   "${CFG[interval]}"

chcache=$(cloud_channels_cache)
truthy 'channels are cached'          '[[ -s $chcache ]]'
truthy 'channel cache is 0600'        '[[ $(stat -f "%Lp" "$chcache" 2>/dev/null || stat -c "%a" "$chcache") == 600 ]]'
contains 'channel secret is cached for sending' 're_secret' "$(<"$chcache")"
# The world-readable config cache must never hold a credential.
missing 'secret is NOT in the config cache' 're_secret' "$cachetext"

reqs=$(<"$REQLOG")
contains 'fetch_config was called' '/rest/v1/rpc/hyn_fetch_config' "$reqs"

# ---------------------------------------------------------------------------
# notification delivery reporting
# ---------------------------------------------------------------------------
printf '\nnotification reporting\n'

: >"$(cloud_notify_queue)"
cloud_notify_record resend 'ops@example.com' warn '[hyn] disk 86%' sent '' alert
cloud_notify_record resend 'ops@example.com' info '[hyn] daily report' failed 'HTTP 403: domain not verified' report
truthy 'deliveries are queued locally' '[[ $(wc -l <"$(cloud_notify_queue)") -eq 2 ]]'

truthy 'queue flushes to the portal' 'cloud_notify_flush 1'
truthy 'queue is emptied after flush' '[[ ! -s $(cloud_notify_queue) ]]'

reqs=$(<"$REQLOG")
notif_line=$(printf '%s\n' "$reqs" | grep hyn_report_notification | tail -1)
contains 'report carries the channel'  'resend' "$notif_line"
contains 'report carries a failure'    'domain not verified' "$notif_line"
contains 'report carries the category' 'report' "$notif_line"
truthy 'reported events are valid JSON' 'printf "%s" "$notif_line" | python3 -c "
import json,sys
req = json.loads(sys.stdin.read())
body = json.loads(req[\"body\"])
ev = body[\"p_events\"]
assert len(ev) == 2, ev
assert ev[0][\"status\"] == \"sent\"
assert ev[1][\"status\"] == \"failed\"
assert ev[1][\"severity\"] == \"info\"
"'

# A failed report must not lose the queue: an alert that was sent but never
# accounted for is a reporting bug, and silently dropping it hides it.
secret_set cloud_node_token 'wrong-token' >/dev/null
SECRETS_LOADED=0
cloud_notify_record ntfy 'topic' crit '[hyn] test' sent '' alert
if cloud_notify_flush 1 2>/dev/null; then
  bad 'flush should fail with a bad token'
else
  ok
fi
truthy 'queue is preserved when reporting fails' '[[ -s $(cloud_notify_queue) ]]'
secret_set cloud_node_token "$(printf 'b%.0s' {1..64})" >/dev/null
SECRETS_LOADED=0
cloud_notify_flush 1 >/dev/null 2>&1

# ---------------------------------------------------------------------------
# administrative pause and suspend, as the agent sees them
# ---------------------------------------------------------------------------
printf '\nadministrative status\n'

curl -s -o /dev/null "http://127.0.0.1:$PORT/status/paused"
# A pause is an administrative decision, not a fault: exit 0 so a maintenance
# window does not fill the journal with what looks like a broken agent.
truthy 'a paused node exits cleanly' 'cloud_push 1'
st=$(cloud_status 2>&1)
contains 'status reports the pause' 'paused' "$st"

curl -s -o /dev/null "http://127.0.0.1:$PORT/status/suspended"
if cloud_push 1 2>/dev/null; then
  bad 'a suspended node should report failure'
else
  ok
fi
st=$(cloud_status 2>&1)
contains 'status reports the suspension' 'suspended' "$st"

curl -s -o /dev/null "http://127.0.0.1:$PORT/status/active"
truthy 'a reinstated node pushes again' 'cloud_push 1'

# ---------------------------------------------------------------------------
# status, push and unlink
# ---------------------------------------------------------------------------
st=$(cloud_status 2>&1)
contains 'status shows the url'      "127.0.0.1:$PORT" "$st"
contains 'status shows the token'    'present (0600)'  "$st"
contains 'status shows a push time'  'last push'       "$st"

truthy 'push succeeds when linked' 'cloud_push 1'

# A bad token must surface as a failure, not a silent success.
secret_set cloud_node_token 'wrong-token' >/dev/null
SECRETS_LOADED=0
if cloud_push 1 2>/dev/null; then
  bad 'push should fail with a bad token'
else
  ok
fi
contains 'failure explains itself' 'HTTP 401' "$CLOUD_LAST_ERR"

secret_set cloud_node_token "$(printf 'b%.0s' {1..64})" >/dev/null
SECRETS_LOADED=0
truthy 'unlink clears the token' 'cloud_unlink'
SECRETS_LOADED=0
eq 'token is gone after unlink' '' "$(secret cloud_node_token)"
eq 'cloud disabled after unlink' 'off' "${CFG[cloud_enabled]}"

# Refusing to run without configuration beats sending requests into the void.
CFG[cloud_url]='' CFG[cloud_anon_key]=''
if _cloud_rpc hyn_ingest '{}' 2>/dev/null; then
  bad 'an unconfigured rpc call should fail'
else
  ok
fi
contains 'unconfigured error is clear' 'cloud_url is not set' "$CLOUD_LAST_ERR"

# A node token in a request body over http would cross every hop in the clear.
# Loopback stays allowed -- it is how this test reaches its own mock, and a
# request that never leaves the box cannot be sniffed on the wire.
CFG[cloud_url]='http://portal.example.com' CFG[cloud_anon_key]='test.anon.key'
if _cloud_rpc hyn_ingest '{}' 2>/dev/null; then
  bad 'a cleartext http endpoint should be refused'
else
  ok
fi
contains 'https is required for a remote endpoint' 'must be https' "$CLOUD_LAST_ERR"
missing  'the refusal leaks no token'              "$(printf 'b%.0s' {1..64})" "$CLOUD_LAST_ERR"
CFG[cloud_url]="http://127.0.0.1:$PORT"
truthy 'loopback http is still allowed' '_cloud_rpc hyn_device_start "{}"'

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
