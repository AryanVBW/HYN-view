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
falsy() { if eval "$2" >/dev/null 2>&1; then bad "$1: expected failure from: $2"; else ok; fi; }

command -v python3 >/dev/null || { printf 'cloud-integration: python3 not found, skipping\n'; exit 0; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/hyn-cloudtest.XXXXXX") || exit 1
trap 'rm -rf "$TMP"; [[ -n ${SRV_PID:-} ]] && kill "$SRV_PID" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# mock PostgREST
# ---------------------------------------------------------------------------
# Records every request as JSON lines so the test can assert on headers and
# bodies after the fact. Keeping the fixture in a real file also avoids a Bash
# 5.3 macOS deadlock while preparing a large heredoc.

PORT=54330
REQLOG="$TMP/requests.jsonl"
: >"$REQLOG"
python3 "$HERE/cloud-mock.py" "$PORT" "$REQLOG" &
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
# Same reason as test/selfcheck.sh: cfg_load reads the invoking user's own
# ~/.config/hyn-view/config, and a real one there would change what this suite
# thinks the agent decided.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" XDG_STATE_HOME="$TMP/xdgstate"
export HYN_CONFIG=''
# A directory the test owns, standing in for /etc/systemd/system. Its writability
# is what cloud_can_install probes, so this is also how the test switches between
# "run by hand as root" and "run from inside the hardened timer".
export HYN_UNIT_DIR="$TMP/units"
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_PROC" "$HYN_SYS" "$HYN_UNIT_DIR" \
         "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
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
# Keep a fixed process row so this transport test can inspect the exact cloud
# boundary; process collection itself is covered by test/selfcheck.sh.
proc_sample() { :; }
is_root() { return 0; }
# Linking is expected to finish the background integration itself. The real
# systemd writer is covered by selfcheck; this boundary test proves the pairing
# flow invokes it after the credential has been verified.
cloud_install_schedule() { printf 'test-schedule-installed\n'; }
update_startup() { : >"$TMP/update-policy-reconciled"; }
update_read() {
  UPD_LATEST=$HYN_VERSION
  UPD_CHECKED=${EPOCHSECONDS:-0}
  if [[ $HYN_VERSION == "$UPD_LATEST" ]]; then UPD_AVAILABLE=0; else UPD_AVAILABLE=1; fi
}
update_check_now() { update_read; return 0; }
update_apply() {
  update_emit_progress installing "Installing hyn-view $UPD_LATEST"
  update_emit_progress restarting 'Restarting managed timers'
  update_emit_progress verifying 'Verifying the installed CLI'
  HYN_VERSION=$UPD_LATEST
  UPD_AVAILABLE=0
  return 0
}

HOSTNAME_S=web-01 DISTRO='Ubuntu 24.04 LTS' KERNEL='6.8.0-31-generic'
UPTIME_S=123456 LOAD1=0.42 LOAD5=0.31 LOAD15=0.28
CPU_PCT=37.5 CPU_USER=20 CPU_SYS=10 CPU_IOWAIT=1.1 CPU_STEAL=0.2 CPU_COUNT=8
CPU_TEMP=52 CPU_MHZ=3400 CPU_MODEL='AMD EPYC 9354'
# Power: a PSU input rail plus RAPL, and a UPS that has lost mains. Deciwatts
# here, because that is the internal unit; the assertions below check the wire
# carries watts.
PWR_INPUT_DW=1180 PWR_INPUT_SRC=hwmon-input PWR_CPU_DW=150 PWR_DRAM_DW=20
PWR_AC=0 PWR_BAT_PCT=87 PWR_BAT_STATUS=Discharging PWR_BAT_DW=95
declare -A PWR_RAILS=(['pmbus PSU1 Input Power']=1180 ['package-0']=150)
MEM_TOTAL=33285996544 MEM_USED=20000000000 MEM_PCT=61.2 SWAP_USED=0
MOUNTS=(/) ; MP_PCT[/]=58.4 ; MP_USED[/]=100 ; MP_SIZE[/]=200 ; MP_AVAIL[/]=100 ; MP_FSTYPE[/]=ext4
NET_WAN=eth0
NET_RXR[eth0]=81250000 NET_TXR[eth0]=22500000
NET_RX[eth0]=999 NET_TX[eth0]=888
NET_RERR[eth0]=0 NET_TERR[eth0]=0 NET_RDROP[eth0]=0 NET_TDROP[eth0]=0
NET_RETRANS_PM=3.1 CT_PCT=4
LAT_MS[1.1.1.1]=8620 LAT_MS[gateway]=1200
ST_LAST_TS=1755600000 ST_LAST_DOWN=105000000 ST_LAST_UP=54000000 ST_LAST_LAT=8600 ST_LAST_NOTE=''
PROC_TOTAL=42 PROCS_RUN=2 PROCS_BLK=0
P_PID=(4242) P_NAME=('queue-worker') P_CPU=(123) P_RSS=(8388608) P_THR=(4)
P_USER=('private-operator')

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
contains 'link announces the complete first sync' 'Measuring the connection and sending the first full report' "$out"
contains 'link installs its background schedule' 'test-schedule-installed' "$out"
truthy 'a pulled update policy is applied in the same check-in' '[[ -f $TMP/update-policy-reconciled ]]'

# cloud_link ran inside a command substitution to capture its output, so its
# in-memory config changes stayed in that subshell. Reload from disk, which is
# exactly what the next `hyn` invocation does.
cfg_load
SECRETS_LOADED=0

# The token must be persisted to the 0600 secrets file, and the node id to config.
eq 'node token is stored'  "$(printf 'b%.0s' {1..64})" "$(secret cloud_node_token)"
eq 'node id is stored'     '3f7a0000-0000-4000-8000-000000000001' "${CFG[cloud_node_id]}"
eq 'cloud is enabled'      'on' "${CFG[cloud_enabled]}"
eq 'dashboard controls the update policy' 'install' "${CFG[auto_update]}"
# There is no channel to seed: being linked IS having delivery.
falsy 'no local channel list exists to configure' '[[ -v CFG[notify_channels] ]]'
truthy 'secrets file is 0600' '[[ $(stat -c "%a" "$HYN_ETC/secrets" 2>/dev/null || stat -f "%Lp" "$HYN_ETC/secrets") == 600 ]]'

NOTIFY_CATEGORY=alert
truthy 'a linked machine can queue an alert with the portal' \
  'notify_send warn "[hyn] web-01 disk warning" "Disk / is at 86%" "<p>Disk / is at 86%</p>"'
NOTIFY_CATEGORY=''

# The next one-minute check-in receives a portal update command. It must report
# each stage and finish only after a fresh full telemetry push with the new
# version has reached the portal.
before_update_ingest=$(grep -c hyn_ingest "$REQLOG")
curl -sS "http://127.0.0.1:$PORT/command/queue" >/dev/null
cloud_push 0 0
command_rc=$?
after_update_ingest=$(grep -c hyn_ingest "$REQLOG")
eq 'portal update command completes during a push' 0 "$command_rc"
eq 'portal update changes the running agent version' "$UPD_LATEST" "$HYN_VERSION"
eq 'portal update synchronizes exactly one fresh reading' "$((before_update_ingest + 1))" "$after_update_ingest"
update_ingest_line=$(grep -n hyn_ingest "$REQLOG" | tail -1 | cut -d: -f1)
update_complete_line=$(grep -n 'p_stage.*completed' "$REQLOG" | tail -1 | cut -d: -f1)
truthy 'portal update completes only after fresh telemetry is accepted' \
  '[[ $update_ingest_line =~ ^[0-9]+$ && $update_complete_line =~ ^[0-9]+$ && $update_ingest_line -lt $update_complete_line ]]'

# A synchronization is an explicit full-data request. It must bypass the normal
# telemetry interval once and report its distinct collection/upload stages.
printf '%s\tok\n' "${EPOCHSECONDS:-0}" >"$(_cloud_push_stamp)"
before_sync_ingest=$(grep -c hyn_ingest "$REQLOG")
curl -sS "http://127.0.0.1:$PORT/command/sync" >/dev/null
cloud_push 0 1
sync_rc=$?
after_sync_ingest=$(grep -c hyn_ingest "$REQLOG")
eq 'portal sync command completes during a scheduled check-in' 0 "$sync_rc"
eq 'portal sync bypasses the telemetry interval exactly once' "$((before_sync_ingest + 1))" "$after_sync_ingest"

# ---------------------------------------------------------------------------
# an update requested by the scheduled check-in
# ---------------------------------------------------------------------------
# The units have full write access now, so this is no longer about escaping a
# sandbox. The check-in still delegates, for two reasons that outlive the
# sandbox: it fires every sixty seconds and must not be the process holding an
# npm install open, and its MemoryMax is sized for bash rather than for node. The
# claim must be reported as progressing and the maintenance unit must finish that
# very same command, or a portal "Update machine" request sits at "accepted" on a
# machine that is checking in perfectly well.
truthy 'a writable unit directory can install' 'cloud_can_install'
declare -a SYSTEMCTL_CALLS=()
systemctl() { SYSTEMCTL_CALLS+=("$*"); return 0; }
_HAVE[systemctl]=1
HYN_VERSION=1.7.0
curl -sS "http://127.0.0.1:$PORT/command/queue" >/dev/null
before_handoff_ingest=$(grep -c hyn_ingest "$REQLOG")
printf '%s\tok\n' "${EPOCHSECONDS:-0}" >"$(_cloud_push_stamp)"
cloud_push 1 1
eq 'a delegated update sends no telemetry of its own' \
  "$before_handoff_ingest" "$(grep -c hyn_ingest "$REQLOG")"
contains 'the update is handed to the maintenance unit' \
  'start --no-block hyn-update.service' "${SYSTEMCTL_CALLS[*]}"
truthy 'the claimed command is left for the maintenance unit' '[[ -r $(cloud_pending_file) ]]'
status_out=$(cloud_status)
contains 'cloud status names the pending handoff' 'update handed to hyn-update.service' "$status_out"
contains 'the portal is told the update was handed off' \
  'Handed the update to the hyn-view maintenance service' "$(<"$REQLOG")"
eq 'the check-in does not install in place' '1.7.0' "$HYN_VERSION"

# The maintenance unit runs it for real, in this process.
before_pending_ingest=$(grep -c hyn_ingest "$REQLOG")
cloud_run_pending 1
pending_rc=$?
eq 'the maintenance unit finishes the handed-off update' 0 "$pending_rc"
eq 'the maintenance unit installs the new version' "$UPD_LATEST" "$HYN_VERSION"
eq 'the maintenance unit synchronizes one fresh reading' \
  "$((before_pending_ingest + 1))" "$(grep -c hyn_ingest "$REQLOG")"
truthy 'the pending command is consumed exactly once' '! [[ -e $(cloud_pending_file) ]]'
cloud_run_pending 1 >/dev/null
eq 'a second maintenance run finds nothing pending' 0 $?

# The maintenance unit must never hand a command back to itself. On a machine
# whose root really is read-only that would be a restart loop on a unit running
# as root, so it reports a failure that names the obstacle instead.
chmod 500 "$HYN_UNIT_DIR"
truthy 'a read-only unit directory is detected' '! cloud_can_install'
printf '4f8b0000-0000-4000-8000-000000000002\tupdate\n' >"$(cloud_pending_file)"
curl -sS "http://127.0.0.1:$PORT/command/queue" >/dev/null
loop_calls_before=${#SYSTEMCTL_CALLS[@]}
cloud_run_pending 1 >/dev/null 2>&1
loop_rc=$?
chmod 700 "$HYN_UNIT_DIR"
eq 'the maintenance unit refuses an install it cannot do' 1 "$loop_rc"
eq 'the maintenance unit does not restart itself' "$loop_calls_before" "${#SYSTEMCTL_CALLS[@]}"
contains 'the refusal names the actual obstacle' \
  "$HYN_UNIT_DIR is not writable" "$(<"$REQLOG")"
unset -f systemctl
unset '_HAVE[systemctl]'

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
contains 'command claim was called' '/rest/v1/rpc/hyn_claim_node_command' "$reqs"
contains 'command progress was reported' '/rest/v1/rpc/hyn_report_node_command' "$reqs"
contains 'command reports registry check' '\"p_stage\": \"checking\"' "$reqs"
contains 'command reports installation' '\"p_stage\": \"installing\"' "$reqs"
contains 'command reports timer restart' '\"p_stage\": \"restarting\"' "$reqs"
contains 'command reports verification' '\"p_stage\": \"verifying\"' "$reqs"
contains 'command reports post-update synchronization' "Synchronizing fresh telemetry from hyn-view $HYN_VERSION" "$reqs"
contains 'command reports completion' '\"p_stage\": \"completed\"' "$reqs"
contains 'sync reports collection' '\"p_stage\": \"collecting\"' "$reqs"
contains 'sync reports upload' '\"p_stage\": \"uploading\"' "$reqs"
contains 'web alert is queued through the agent RPC' '/rest/v1/rpc/hyn_queue_web_notification' "$reqs"
web_line=$(printf '%s\n' "$reqs" | grep hyn_queue_web_notification | tail -1)
missing 'web alert cannot select a recipient' 'recipient' "$web_line"
missing 'web alert cannot carry a provider credential' 'api_key' "$web_line"
delivery_lines=$(printf '%s\n' "$reqs" | grep hyn_report_notification || true)
missing 'queued web alerts are not falsely reported as already sent' '[hyn] web-01 disk warning' "$delivery_lines"
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
pw = body[\"p_payload\"][\"power\"]
# Watts on the wire, not the deciwatts used internally: a dashboard axis in
# tenths of a watt would be wrong by a factor of ten and look plausible.
assert pw[\"input_w\"] == 118.0, pw
assert pw[\"cpu_w\"] == 15.0 and pw[\"dram_w\"] == 2.0, pw
# The source travels with the number. Without it the portal cannot tell a PSU
# measurement from a RAPL estimate, and would plot them on one axis.
assert pw[\"input_src\"] == \"hwmon-input\", pw
assert pw[\"ac_online\"] == 0 and pw[\"battery_pct\"] == 87, pw
assert pw[\"battery_status\"] == \"Discharging\" and pw[\"battery_w\"] == 9.5, pw
assert pw[\"rails\"][\"pmbus PSU1 Input Power\"] == 118.0, pw
assert body[\"p_payload\"][\"agent_version\"] == \"$HYN_VERSION\", body[\"p_payload\"][\"agent_version\"]
assert body[\"p_payload\"][\"agent_update\"][\"latest\"] == \"$HYN_VERSION\", body[\"p_payload\"][\"agent_update\"]
assert body[\"p_payload\"][\"agent_update\"][\"available\"] is False, body[\"p_payload\"][\"agent_update\"]
top = body[\"p_payload\"][\"processes\"][\"top\"][0]
assert top[\"name\"] == \"queue-worker\", top
assert \"user\" not in top, top
assert \"private-operator\" not in json.dumps(body[\"p_payload\"]), body[\"p_payload\"][\"processes\"]
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
assert \"journal_tail\" not in hw, hw
assert \"peer handshake timeout\" not in json.dumps(hw), hw
assert \"reconnecting to lighthouse\" not in json.dumps(hw), hw
assert hw[\"bin_path\"] == \"/usr/local/bin/highway\" and hw[\"bin_size\"] == 48234496, hw
"'

# ---------------------------------------------------------------------------
# heartbeat: the cheapest thing the agent sends, and the one the portal reads as
# proof of life
# ---------------------------------------------------------------------------
printf '\nheartbeat\n'

hb_stamp=$(cloud_heartbeat_stamp)
rm -f "$hb_stamp"
truthy 'a beat is accepted' 'cloud_heartbeat 1'
hb_line=$(<"$hb_stamp")
contains 'the beat outcome is recorded locally' $'\tok\t' "$hb_line"
eq 'the beat learns the node status' 'active' "$CLOUD_HEARTBEAT_STATUS"
hb_req=$(grep 'hyn_heartbeat' "$REQLOG" | tail -1)
# The whole point of a separate RPC: it must NOT be the settings pull. A beat
# that fetched the config would be 2.5x the portal work of the check-in it sits
# beside, every 24 seconds, on every node.
contains 'the beat calls its own RPC'  '/hyn_heartbeat' "$hb_req"
contains 'the beat carries the version' 'p_agent_version' "$hb_req"
missing  'the beat asks for no config'  'alert_template_b64' "$hb_req"
# Same credential rule as every other request: body, never argv, never the URL.
contains 'the token travels in the body' 'p_node_token' "$hb_req"
# The logged request records the path separately from the body, so a token that
# had leaked into the URL would show up in the path field.
hb_path=${hb_req#*\"path\": \"}
hb_path=${hb_path%%\"*}
missing 'the token is not in the request path' "$(printf 'b%.0s' {1..64})" "$hb_path"
# Age is what doctor and the self-heal check read.
cloud_heartbeat_age_v
truthy 'the beat age is readable' '((CLOUD_HEARTBEAT_AGE >= 0 && CLOUD_HEARTBEAT_AGE < 120))'

# A portal that has not applied the migration must not leave a machine with no
# heartbeat at all: the settings pull has always recorded one, so fall back to it
# rather than going quiet.
curl -s -o /dev/null "http://127.0.0.1:$PORT/heartbeat/off"
rm -f "$hb_stamp"
truthy 'a portal without the RPC still records a beat' 'cloud_heartbeat 1'
contains 'the fallback is recorded as such' 'fallback' "$(<"$hb_stamp")"
contains 'the fallback used the settings pull' '/hyn_fetch_config' "$(tail -1 "$REQLOG")"
curl -s -o /dev/null "http://127.0.0.1:$PORT/heartbeat/on"

# An unlinked machine must not beat, and must not treat that as a fault worth
# retrying: there is no credential to beat with.
rm -f "$hb_stamp"
(
  cloud_linked() { return 1; }
  ! cloud_heartbeat 1
) && ok || bad 'an unlinked machine tries to beat anyway'
falsy 'no stamp is written without a credential' '[[ -e $hb_stamp ]]'
# Restore a good stamp for anything downstream that reads it.
cloud_heartbeat 1 >/dev/null 2>&1

# ---------------------------------------------------------------------------
# config pull: the dashboard is the source of truth
# ---------------------------------------------------------------------------
printf '\nconfig pull\n'

# Versions before local-only notification configuration wrote provider JSON to
# this state cache. A safe pull must remove that copy even if an old or
# malicious portal still returns a channel payload.
chcache=$(cloud_channels_cache)
printf '%s\n' '[{"kind":"resend","target":"old@example.com","secret":"legacy_secret"}]' >"$chcache"
chmod 600 "$chcache"

truthy 'config pull succeeds' 'cloud_config_pull 1'

cache=$(cloud_config_cache)
truthy 'a config cache is written' '[[ -s $cache ]]'
cachetext=$(<"$cache")
contains 'pulled setting is cached'      'alert_mem_pct=80' "$cachetext"
contains 'second pulled setting'         'report_at=07:30'  "$cachetext"
missing  'unsafe allowed-key value is not cached' 'alert_disk_pct' "$cachetext"
# A key the agent does not recognise must be dropped, not written, or every
# subsequent load would warn about it forever.
missing  'unknown key is not cached'     'not_a_real_key'   "$cachetext"
missing  'remote access-detail opt-in is not cached' 'notify_access_details' "$cachetext"
missing  'remote webhook is not cached'       'webhook_url'        "$cachetext"
missing  'remote heartbeat is not cached'     'heartbeat_url'      "$cachetext"
missing  'remote recipient is not cached'     'notify_to'          "$cachetext"
missing  'remote Telegram target is not cached' 'telegram_chat_id' "$cachetext"
missing  'remote ntfy target is not cached'   'ntfy_topic'         "$cachetext"
missing  'remote portal URL is not cached'    'cloud_url'          "$cachetext"
missing  'remote refresh interval is not cached' 'interval='       "$cachetext"

# Reloading must apply the pulled values, and a local line must still win --
# central management that silently overrides a deliberate local edit is
# undebuggable on a box with no network.
config_set interval 1.0 >/dev/null
cfg_load
eq 'pulled setting is applied'          '80'    "${CFG[alert_mem_pct]}"
eq 'local config still overrides cloud' '1.0'   "${CFG[interval]}"
eq 'notification access details remain private' 'off' "${CFG[notify_access_details]}"
# This arithmetic shape mirrors the alert engine. Before value validation, the
# mock response's command substitution created this harmless marker.
x=0
: $(( ${CFG[alert_disk_pct]} - 5 ))
truthy 'rejected remote arithmetic never executes' '[[ ! -e $HYN_VAR/cloud-rce-marker ]]'

truthy 'legacy central channel cache is deleted' '[[ ! -e $chcache ]]'

# A settings change must be visible on the portal in the same check-in that
# accepted it. Without this the agent takes the new value within a minute but the
# reading that shows its effect waits up to cloud_push_min, so someone who edits a
# threshold and watches the page concludes it did not work.
# No queued maintenance command, so the only thing that can trigger a reading
# below is the settings change itself.
curl -sS "http://127.0.0.1:$PORT/command/clear" >/dev/null
rm -f -- "$cache"
cloud_config_pull 1
eq 'a first pull with no cache is a change' 1 "$CLOUD_CONFIG_CHANGED"
cloud_config_pull 1
eq 'an identical pull is not a change' 0 "$CLOUD_CONFIG_CHANGED"
# With nothing changed and a fresh reading already sent, the check-in stays cheap.
printf '%s\tok\n' "${EPOCHSECONDS:-0}" >"$(_cloud_push_stamp)"
before_quiet=$(grep -c hyn_ingest "$REQLOG")
cloud_push 1 1
eq 'an unchanged check-in sends no reading' "$before_quiet" "$(grep -c hyn_ingest "$REQLOG")"
# Now make the portal return something different and confirm the reading follows
# immediately, without waiting for the interval.
curl -sS "http://127.0.0.1:$PORT/config/report_at/09:15" >/dev/null
printf '%s\tok\n' "${EPOCHSECONDS:-0}" >"$(_cloud_push_stamp)"
before_changed=$(grep -c hyn_ingest "$REQLOG")
cloud_push 1 1
eq 'a changed setting is pushed in the same check-in' \
  "$((before_changed + 1))" "$(grep -c hyn_ingest "$REQLOG")"
eq 'the changed value is the one now in effect' '09:15' "${CFG[report_at]}"
# And the cache is rewritten wholesale, so a setting the portal stops sending
# falls back to the agent default rather than staying pinned for ever.
curl -sS "http://127.0.0.1:$PORT/config/drop/report_at" >/dev/null
cloud_config_pull 1
cfg_load
eq 'a withdrawn setting returns to the agent default' '08:00' "${CFG[report_at]}"
# The world-readable config cache must never hold a credential.
missing 'secret is NOT in the config cache' 're_secret' "$cachetext"

alert_template=$(notification_template_path alert)
report_template=$(notification_template_path report)
truthy 'alert template is cached locally' '[[ -s $alert_template ]]'
truthy 'report template is cached locally' '[[ -s $report_template ]]'
contains 'alert template keeps its content slot' '{{content}}' "$(<"$alert_template")"
notify_apply_template alert warn 'Disk <full>' '<strong>generated alert</strong>'
contains 'pulled wrapper reaches the actual send renderer' 'data-template="alert"' "$HTML_OUT"
contains 'generated HTML is inserted into the wrapper' '<strong>generated alert</strong>' "$HTML_OUT"
contains 'scalar placeholders are escaped' 'Disk' "$HTML_OUT"

reqs=$(<"$REQLOG")
contains 'fetch_config was called' '/rest/v1/rpc/hyn_fetch_config' "$reqs"

# ---------------------------------------------------------------------------
# there is no local delivery report to send
# ---------------------------------------------------------------------------
printf '\nnotification reporting\n'

# The agent used to queue its own delivery outcomes and drain them to the portal,
# because it was the only thing that knew whether Resend had accepted a message.
# It is not any more: the portal's own worker performs the send and writes the log,
# so a local report could only ever be a guess about work this process did not do.
falsy 'no local delivery queue exists'   'declare -F cloud_notify_queue >/dev/null'
falsy 'nothing records a local outcome'  'declare -F cloud_notify_record >/dev/null'
falsy 'nothing flushes one to the portal' 'declare -F cloud_notify_flush >/dev/null'
# Queueing an event must not claim it was delivered. Only the portal knows that.
reqs=$(<"$REQLOG")
truthy 'the agent never reports a delivery it did not make' \
  '[[ $(printf "%s\n" "$reqs" | grep -c hyn_report_notification) -eq 0 ]]'
contains 'the agent queues events instead' 'hyn_queue_web_notification' "$reqs"

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

# The system timer wakes every minute so dashboard config changes are fetched
# promptly, but collection/ingest still honours the per-node push interval.
before_ingest=$(grep -c hyn_ingest "$REQLOG")
truthy 'scheduled push exits cleanly before its interval' 'cloud_push 1 1'
after_ingest=$(grep -c hyn_ingest "$REQLOG")
eq 'scheduled push does not collect early' "$before_ingest" "$after_ingest"
printf '%s\tok\n' "$((EPOCHSECONDS - 600))" >"$(_cloud_push_stamp)"
truthy 'scheduled push sends after its interval' 'cloud_push 1 1'
after_due_ingest=$(grep -c hyn_ingest "$REQLOG")
eq 'due scheduled push reaches ingest' "$((before_ingest + 1))" "$after_due_ingest"

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

# Hosted pairing is the normal customer path: no Supabase prompt and no CLI
# flags. The common API configuration belongs to the deployed portal.
CFG[cloud_api_url]="http://127.0.0.1:$PORT/api/agent/v1"
CFG[cloud_portal_url]='https://www.hyn-view.in'
CFG[cloud_url]='' CFG[cloud_anon_key]=''
out=$(cloud_link 2>&1)
rc=$?
eq 'zero-config hosted link succeeds' 0 "$rc"
missing 'hosted link does not ask for a Supabase URL' 'Supabase project URL' "$out"
missing 'hosted link does not ask for an anon key' 'Supabase anon key' "$out"
contains 'hosted link prints the product pairing page' 'https://www.hyn-view.in/link' "$out"
cfg_load
SECRETS_LOADED=0
truthy 'hosted link stores a node token' '[[ -n $(secret cloud_node_token) ]]'
cloud_unlink >/dev/null
SECRETS_LOADED=0

# A hosted install uses the branded API without asking the operator for a
# Supabase URL or public key. This is the path a fresh npm install takes.
CFG[cloud_url]='' CFG[cloud_anon_key]=''
CFG[cloud_api_url]="http://127.0.0.1:$PORT/api/agent/v1"
truthy 'hosted API works without Supabase configuration' '_cloud_rpc hyn_device_start "{}"'
reqs=$(<"$REQLOG")
contains 'hosted API route is used' '/api/agent/v1/hyn_device_start' "$reqs"

# An explicit empty hosted endpoint disables that default and must fail clearly.
CFG[cloud_api_url]=''
if _cloud_rpc hyn_ingest '{}' 2>/dev/null; then
  bad 'an unconfigured rpc call should fail'
else
  ok
fi
contains 'unconfigured error is clear' 'cloud API URL is not set' "$CLOUD_LAST_ERR"

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
