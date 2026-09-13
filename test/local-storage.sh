#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_LIB="$ROOT/lib" HYN_ROOT="$ROOT" HYN_ETC="$WORK/etc" HYN_VAR="$WORK/state"
export XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/user-state" HYN_CONFIG=''
mkdir -p "$HYN_ETC" "$HYN_VAR"
source "$HYN_LIB/core.sh"
source "$HYN_LIB/notify.sh"
source "$HYN_LIB/cloud.sh"
source "$ROOT/test/flock-fixture.sh"
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else printf 'FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); fi; }
is_root() { return 0; }
cfg_load
check 'default history uploads and beats every five minutes' '[[ ${CFG[cloud_storage]} == cloud && ${CFG[cloud_push_min]} == 5 && ${CFG[cloud_checkin_min]} == 5 && ${CFG[heartbeat_sec]} == 300 && ${CFG[record_interval_min]} == 1 ]]'
check 'bad numeric property is refused without changing file' '! config_set cloud_checkin_min 0 2>/dev/null && [[ ! -f $HYN_ETC/config ]]'
BAD_SETTING=$'mono\ncloud_storage=cloud'
check 'multiline cannot inject a second property' '! config_set theme "$BAD_SETTING" 2>/dev/null'
check 'managed storage policy is explicit and bounded to local/cloud' '_cfg_cloud_allowed cloud_storage && _cfg_cloud_value_allowed cloud_storage cloud && _cfg_cloud_value_allowed cloud_storage local && ! _cfg_cloud_value_allowed cloud_storage other && ! _cfg_cloud_allowed cloud_notifications'
CLOUD_PAYLOAD='{"cpu":{"pct":42},"host":"private-host"}'
local_store_snapshot
check 'snapshot round trips locally' '[[ $(local_history) == "$CLOUD_PAYLOAD" ]]'
config_set auto_update off
check 'CLI history --local reaches local history instead of speed tests' '[[ $(bash "$ROOT/bin/hyn" history --local 1) == "$CLOUD_PAYLOAD" ]]'
check 'private files' '[[ $(find "$HYN_VAR/local" -type f -perm -004 | wc -l) -eq 0 ]]'
for i in {1..8}; do local_store_snapshot & done
wait
check 'concurrent snapshots are retained independently' '[[ $(find "$HYN_VAR/local/snapshots" -name "*.json" | wc -l) -eq 9 ]]'
printf '{}\n' >"$HYN_VAR/local/snapshots/old.json"
touch -t 202001010000 "$HYN_VAR/local/snapshots/old.json"
local_store_prune
check 'expired local history is rotated' '[[ ! -e $HYN_VAR/local/snapshots/old.json ]]'
local_store_report 'daily report stays on this server'
check 'daily reports are retained privately' '[[ $(find "$HYN_VAR/local/snapshots" -name "*-report-*.txt" | wc -l) -eq 1 ]]'
CFG[local_max_mb]=1
dd if=/dev/zero of="$HYN_VAR/local/snapshots/2000-quota.json" bs=1048576 count=2 2>/dev/null
printf 'in-flight write' >"$HYN_VAR/local/snapshots/.snapshot.active"
local_store_prune
check 'space limit rotates published history without deleting an active write' '[[ ! -e $HYN_VAR/local/snapshots/2000-quota.json && -f $HYN_VAR/local/snapshots/.snapshot.active ]]'
rm "$HYN_VAR/local/snapshots/.snapshot.active"
CFG[local_max_mb]=256

# The checkpoint is authoritative across independent processes, while every
# previous committed calculation remains inspectable in the bounded archive.
ledger_dir="$HYN_VAR/local"
local_bandwidth_record eth0 boot-1 18446744073709551000 9007199254740993 1000000 1000
local_bandwidth_record eth0 boot-1 18446744073709551500 9007199254741193 1001500 2500
check 'uint64 inputs and exact observed byte deltas persist' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"700\""* ]]'
local_bandwidth_record eth0 boot-1 18446744073709551550 9007199254741203 1001600 2600
check 'a new process continues the stored baseline' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"760\""* ]]'
baseline=$(cat "$ledger_dir/bandwidth-state")
local_bandwidth_record eth0 boot-1 18446744073709551020 9007199254741003 1000200 1200
check 'overlapping stale collection cannot rewind the baseline' '[[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]]'
local_bandwidth_record eth0 boot-1 18446744073709551550 9007199254741203 1001600 2600
check 'identical samples cannot double count' '[[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]]'
local_bandwidth_record eth0 boot-1 18446744073709551500 9007199254741193 1001600 2600
check 'same-tick stale sample cannot create a false reset' '[[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]]'
local_bandwidth_record eth0 boot-1 20 10 1001700 2700
check 'counter reset preserves totals and declares incomplete coverage' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"incomplete\":true,\"reason\":\"counter_reset\""* && $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"760\""* ]]'
local_bandwidth_record eth1 boot-1 9000 5000 1001800 2800
local_bandwidth_record eth1 boot-2 10000 6000 1001900 1
check 'interface switches and reboots do not fabricate bytes' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"760\""* && $(tail -1 "$ledger_dir/bandwidth-state") == *"\"discontinuities\":3"* ]]'
local_bandwidth_record eth1 boot-2 10030 6010 999900 101
check 'wall-clock regression still counts monotonic observed deltas' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"800\""* ]]'
for i in {1..12}; do local_bandwidth_record eth1 boot-2 11030 6210 1002900 1101 & done
wait
check 'concurrent identical writers count the same interval once' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"2000\""* ]]'
python3 - "$ledger_dir" <<'PY'
import glob,json,os,sys
directory=sys.argv[1]
records=[json.load(open(f)) for f in glob.glob(directory+'/bandwidth/*.json')]
records.append(json.loads(open(directory+'/bandwidth-state').read().splitlines()[1]))
assert len(records)==8, len(records)
assert sorted(r['sequence'] for r in records)==list(range(1,9))
assert sum(int(r['delta_rx_bytes'])+int(r['delta_tx_bytes']) for r in records)==2000
assert all(os.stat(f).st_mode & 0o077 == 0 for f in glob.glob(directory+'/bandwidth/*'))
PY
ledger_parse_rc=$?
check 'all committed calculations survive with exact inputs and private files' '[[ $ledger_parse_rc == 0 ]]'
baseline=$(cat "$ledger_dir/bandwidth-state")
check 'invalid and out-of-range counters cannot replace saved totals' '! local_bandwidth_record eth1 boot-2 18446744073709551616 0 1003000 1200 && [[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]]'
check 'failed durability flush leaves the checkpoint intact' '(_local_store_sync() { return 1; }; ! local_bandwidth_record eth1 boot-2 12000 7000 1004000 2201 && [[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]])'
check 'failure between archive and checkpoint leaves prior totals authoritative' '(_local_store_publish() { if [[ $2 == */bandwidth-state ]]; then rm -f -- "$1"; return 1; fi; mv -f -- "$1" "$2"; }; ! local_bandwidth_record eth1 boot-2 12000 7000 1004000 2201 && [[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" ]])'
printf 'corrupt checkpoint\n' >"$ledger_dir/bandwidth-state"
check 'corrupt checkpoint fails instead of silently resetting totals' '! local_bandwidth_record eth1 boot-2 12000 7000 1004000 2201'
printf '%s\n' "$baseline" >"$ledger_dir/bandwidth-state"
touch -t 202001010000 "$ledger_dir/bandwidth-state" "$ledger_dir"/bandwidth/*.json
local_store_prune
check 'retention never removes cumulative state' '[[ $(cat "$ledger_dir/bandwidth-state") == "$baseline" && $(find "$ledger_dir/bandwidth" -name "*.json" | wc -l) -eq 0 ]]'
export HYN_SYS="$WORK/sys"
mkdir -p "$HYN_SYS/class/net/eth1"
printf '5\n' >"$HYN_SYS/class/net/eth1/ifindex"
local_bandwidth_record eth1 boot-2 999999 99999 1004000 2201
check 'a recreated NIC with larger counters cannot create a usage spike' '[[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"reason\":\"interface_recreated\""* && $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"2000\""* ]]'

# The advisory lock is released by the kernel when its owner is killed.
(
  exec {fixture_fd}>"$ledger_dir/bandwidth.lock"
  flock -w 1 "$fixture_fd" || exit 1
  : >"$WORK/lock-ready"
  while :; do :; done
) &
fixture_pid=$!
for i in {1..100}; do [[ -e $WORK/lock-ready ]] && break; sleep .01; done
check 'lock holder reached the critical section' '[[ -e $WORK/lock-ready ]]'
kill -KILL "$fixture_pid"
wait "$fixture_pid" 2>/dev/null || true
check 'killed writer cannot leave a permanent lock or corrupt baseline' 'local_bandwidth_record eth1 boot-2 1000000 100000 1005000 3201 && [[ $(tail -1 "$ledger_dir/bandwidth-state") == *"\"observed_total_bytes\":\"2002\""* ]]'

# Independent arbitrary precision oracle checks every arithmetic helper with
# reproducible values near signed/unsigned boundaries and beyond uint64 totals.
python3 - "$HYN_LIB/decimal.sh" <<'PY'
import random,subprocess,sys
rng=random.Random(911)
pairs=[(0,0),(2**64-1,2**64-500),(2**80,2**80-7)]
pairs += [(rng.randrange(2**80),rng.randrange(2**80)) for _ in range(40)]
script=['source "$1"']
expected=[]
for a,b in pairs:
    a,b=max(a,b),min(a,b)
    ms=rng.randrange(1,100000)
    for command,result in [('uint_add_v',a+b),('uint_subtract_v',a-b)]:
        script.append(f'{command} {a} {b}; printf "%s\\n" "$UINT_VALUE"')
        expected.append(str(result))
    script.append(f'uint_rate_v {a} {ms}; printf "%s\\n" "$UINT_VALUE"')
    expected.append(str(a*1000//ms))
actual=subprocess.check_output(['bash','-c','\n'.join(script),'fixture',sys.argv[1]],text=True).splitlines()
assert actual==expected
PY
arithmetic_rc=$?
check '129 arithmetic cases match independent arbitrary precision calculations' '[[ $arithmetic_rc == 0 ]]'
check 'HTTP totals and projections preserve values beyond signed integers' '(HYN_VAR="$WORK/usage-large"; STATE_DIR=""; mkdir -p "$HYN_VAR"; local_usage_record fixture 200 18446744073709551615 9007199254740993 0 && local_usage_record fixture 200 18446744073709551615 9007199254740993 0 && output=$(cloud_usage) && [[ $output == *"36893488147419103230 body bytes sent, 18014398509481986 body bytes received"* && $output == *"540431955284459580 received bytes"* ]])'

secret() { printf 'test-private-node-token'; }
_cloud_rpc_once() {
  printf '%s\n' "$1" >>"$WORK/actions"
  CLOUD_LAST_BODY='{"status":"ok","node_status":"active"}'
  [[ $1 != hyn_transient_snapshot ]] || CLOUD_LAST_BODY='{"status":200,"node_id":"local-fixture","storage":"transient","expires_in":300}'
  CLOUD_LAST_CODE=200; CLOUD_LAST_ERR=''
}
CFG[cloud_api_url]='http://127.0.0.1:9999/api/agent/v1'
CFG[cloud_url]=''; CFG[cloud_anon_key]=''
CFG[cloud_storage]=local
check 'manual reading uses transient action' 'cloud_ingest_collected 1 && [[ $(tail -1 "$WORK/actions") == hyn_transient_snapshot ]]'
check 'real transient acknowledgement completes explicit local viewing without an outbox' '[[ $CLOUD_INGESTED == 1 && $(find "$HYN_VAR/local/outbox" -type f -name "*.json" | wc -l) -eq 0 ]]'
check 'a transient acknowledgement cannot retire a durable cloud retry' '(CLOUD_LAST_BODY="{\"status\":200,\"storage\":\"transient\"}"; ! cloud_ingest_acknowledged hyn_ingest)'
check 'a transient success requires the explicit storage marker' '(CLOUD_LAST_BODY="{\"status\":200}"; ! cloud_ingest_acknowledged hyn_transient_snapshot)'
check 'a durable response cannot falsely acknowledge temporary viewing' '(CLOUD_LAST_BODY="{\"status\":\"ok\"}"; ! cloud_ingest_acknowledged hyn_transient_snapshot)'
check 'local beat sends control metadata only' 'cloud_heartbeat 1 && [[ $(tail -1 "$WORK/actions") == hyn_local_heartbeat ]]'
check 'HTTP accounting contains no bodies or tokens' '! grep -REq "test-private-node-token|private-host|p_node_token" "$HYN_VAR/local/usage"'
check 'HTTP accounting reports requests' '[[ $(cloud_usage) == *"2 requests"* ]]'
check 'local notification content cannot leave without opt-in' '! cloud_web_notify secret-subject private-text private-html 2>/dev/null'
CFG[cloud_url]='https://database.example'; CFG[cloud_anon_key]=public
check 'local mode never falls back to direct Supabase ingest' '! cloud_ingest_collected 1 && [[ $(wc -l <"$WORK/actions") -eq 2 ]]'
CFG[cloud_url]=''; CFG[cloud_anon_key]=''
cloud_config_pull() { printf 'pull\n' >>"$WORK/checkins"; CLOUD_CONFIG_CHANGED=1; return 1; }
cloud_command_poll() { CLOUD_COMMAND_CLAIMED=0; printf 'poll\n' >>"$WORK/checkins"; }
update_startup() { :; }
cloud_collect_full() { printf 'unexpected collection\n' >>"$WORK/checkins"; }
check 'scheduled local check-in uploads no reading even when settings fail' 'cloud_push 1 1 && [[ $(wc -l <"$WORK/actions") -eq 2 ]]'
check 'second timer tick sends no control requests' 'cloud_push 1 1 && [[ $(wc -l <"$WORK/checkins") -eq 2 ]]'

# Discovery does not use any credentials or follow redirects, caches success,
# and never extends the trusted host list to a lookalike or a custom endpoint.
curl() {
  printf '%s\n' "$*" >>"$WORK/probes"
  [[ $* != *'--location'* && $* != *'test-private-node-token'* ]] || return 3
  [[ ${*: -1} == https://hyn-view.in/api/agent/v1/health ]] || return 7
  printf '{"service":"hyn-agent-v1"}'
}
CFG[cloud_api_url]='https://www.hyn-view.in/api/agent/v1'
CLOUD_RESOLVED_URL=''
check 'apex is selected when www is down' 'cloud_resolve_portal && [[ $(cloud_url) == https://hyn-view.in/api/agent/v1 ]]'
check 'successful discovery is cached across calls' 'cloud_resolve_portal && [[ $(wc -l <"$WORK/probes") -eq 2 ]]'
CFG[cloud_api_url]='https://private.example/api/agent/v1'
check 'explicit custom endpoint overrides a cached official domain' 'cloud_resolve_portal && [[ $(cloud_url) == https://private.example/api/agent/v1 ]]'
CFG[cloud_api_url]='https://www.hyn-view.in.attacker.example/api/agent/v1'
check 'a lookalike is not an official domain' '! cloud_official_url'
CFG[cloud_api_url]='https://www.hyn-view.in/api/agent/v1'
_cloud_rpc_once() { printf 'POST\n' >>"$WORK/posts"; CLOUD_LAST_CODE=503; CLOUD_LAST_BODY='temporarily unavailable'; return 1; }
check 'an ambiguous POST failure is not replayed on another host' '! _cloud_rpc hyn_claim_node_command "{}" && [[ $(wc -l <"$WORK/posts") -eq 1 ]]'
check 'failed host is invalidated for the next operation' '[[ $(cat "$HYN_VAR/portal-endpoint") == "0 https://hyn-view.in/api/agent/v1" ]]'

# Keep the established resident loop alive while backing network failures off.
source "$HYN_LIB/agent.sh"
cloud_heartbeat() { printf 'beat\n' >>"$WORK/beats"; return 1; }
agent_beat >/dev/null 2>&1 || true
agent_beat >/dev/null 2>&1 || true
check 'failed heartbeat backs off without repeated requests' '[[ $(wc -l <"$WORK/beats") -eq 1 && $AGENT_RETRY_AT -gt $EPOCHSECONDS ]]'

# Durable delivery: every test uses a private local state tree and a deterministic
# in-process transport. No external endpoint or real credential is involved.
HYN_VAR="$WORK/retry-state"; STATE_DIR=''
mkdir -p "$HYN_VAR"
CFG[cloud_storage]=cloud
CFG[cloud_node_id]=node-a
CFG[cloud_api_url]='http://127.0.0.1:9999/api/agent/v1'
CFG[cloud_url]=''; CFG[cloud_anon_key]=''; CLOUD_RESOLVED_URL=''
CFG[local_keep_days]=14; CFG[local_max_mb]=256
OUTBOX_TEST_MODE=down
_cloud_rpc() {
  printf '%s\t%s\n' "$1" "$2" >>"$WORK/replay-requests"
  CLOUD_LAST_BODY='{"status":"ok","node_status":"active"}'
  CLOUD_LAST_CODE=200; CLOUD_LAST_ERR=''
  case $OUTBOX_TEST_MODE in
    down) CLOUD_LAST_CODE=503; CLOUD_LAST_ERR='temporary transport failure'; return 1 ;;
    paused) CLOUD_LAST_BODY='{"node_status":"paused"}' ;;
    auth) CLOUD_LAST_CODE=401; CLOUD_LAST_ERR='HTTP 401: invalid node token'; return 1 ;;
    legacy_auth) CLOUD_LAST_CODE=400; CLOUD_LAST_ERR='HTTP 400: invalid node token'; return 1 ;;
    legacy_paused) CLOUD_LAST_CODE=400; CLOUD_LAST_ERR='HTTP 400: node paused'; return 1 ;;
    uncertain400) CLOUD_LAST_CODE=400; CLOUD_LAST_ERR="HTTP 400: $OUTBOX_TEST_ERROR"; return 1 ;;
    permanent400 | permanent413)
      if [[ $2 == *reject-me* ]]; then
        CLOUD_LAST_CODE=${OUTBOX_TEST_MODE#permanent}
        if [[ $CLOUD_LAST_CODE == 400 ]]; then
          CLOUD_LAST_ERR='HTTP 400: monitoring payload must be an object'
        else
          CLOUD_LAST_ERR='HTTP 413: agent request exceeds 1 MB'
        fi
        return 1
      fi ;;
    invalid) CLOUD_LAST_BODY='{}' ;;
    expired) CLOUD_LAST_BODY='{"status":"ok","discarded":"expired"}' ;;
  esac
  return 0
}
_outbox_count() { find "$HYN_VAR/local/outbox" -type f -name '*.json' | wc -l | tr -d ' '; }
for validation_error in \
  'request body must be valid JSON' \
  'request body must be a JSON object' \
  'monitoring payload must be an object' \
  'monitoring payload exceeds 64 KiB' \
  'stored monitoring payload exceeds 16 KiB' \
  'monitoring timestamp is in the future or invalid' \
  'invalid input syntax for type integer: "not-a-number"' \
  'invalid input syntax for type bigint: "not-a-number"' \
  'invalid input syntax for type numeric: "not-a-number"' \
  'invalid input syntax for type double precision: "not-a-number"' \
  'invalid input syntax for type timestamp with time zone: "not-a-date"' \
  'invalid input syntax for type json'; do
  check "known payload validation is permanent: $validation_error" '(CLOUD_LAST_CODE=400; CLOUD_LAST_ERR="HTTP 400: $validation_error"; _cloud_outbox_permanent_rejection)'
done
check 'HTTP 413 is a deterministic body size rejection' '(CLOUD_LAST_CODE=413; CLOUD_LAST_ERR="HTTP 413"; _cloud_outbox_permanent_rejection)'
check 'server failures are retryable even when their message resembles validation' '(CLOUD_LAST_CODE=503; CLOUD_LAST_ERR="monitoring payload exceeds 64 KiB"; ! _cloud_outbox_permanent_rejection)'
CLOUD_PAYLOAD='{"ts":"2026-09-12T00:00:00Z","sample":"offline-original"}'
check 'failed upload leaves durable payload and secondary local backup' '! cloud_ingest_collected 1 && [[ $(_outbox_count) == 1 && $(local_history) == "$CLOUD_PAYLOAD" && $CLOUD_INGESTED == 0 ]]'
check 'queued data contains no credential envelope or node secret' '! rg -q "p_node_token|test-private-node-token" "$HYN_VAR/local/outbox"'
queued_before=$(find "$HYN_VAR/local/outbox" -type f -name '*.json')
check 'retry record is private' '[[ $(find "$HYN_VAR/local/outbox" -type f -perm -077 | wc -l) -eq 0 ]]'
OUTBOX_TEST_MODE=invalid
check 'a 200 without a positive acknowledgement remains queued' '! cloud_outbox_flush && [[ -f $queued_before ]]'
OUTBOX_TEST_MODE=paused
check 'a paused response never acknowledges the retry record' '! cloud_outbox_flush && [[ -f $queued_before ]]'
OUTBOX_TEST_MODE=auth
check 'an authentication failure never acknowledges the retry record' '! cloud_outbox_flush && [[ -f $queued_before ]]'
OUTBOX_TEST_MODE=ok
: >"$WORK/replay-requests"
CLOUD_PAYLOAD='{"ts":"2026-09-12T00:01:00Z","sample":"current-reading"}'
check 'connection recovery delivers current state then drains the old record' 'cloud_ingest_collected 1 && [[ $(_outbox_count) == 0 && $CLOUD_INGESTED == 1 ]]'
check 'replay preserves the original timestamp after the fresh reading' '[[ $(head -1 "$WORK/replay-requests") == *current-reading* && $(tail -1 "$WORK/replay-requests") == *2026-09-12T00:00:00Z* ]]'
check 'cloud acknowledgement leaves both longer local backups' '[[ $(find "$HYN_VAR/local/snapshots" -type f -name "*.json" | wc -l) -eq 2 ]]'
for reject_code in 400 413; do
  CLOUD_PAYLOAD="{\"sample\":\"reject-me-$reject_code\"}"
  rejected_payload=$CLOUD_PAYLOAD
  rejected_epoch=$((EPOCHSECONDS - 2))
  rejected_queue=$(unset EPOCHSECONDS; EPOCHSECONDS=$rejected_epoch; local_outbox_enqueue)
  CLOUD_PAYLOAD="{\"sample\":\"valid-after-$reject_code\"}"
  local_outbox_enqueue >/dev/null
  OUTBOX_TEST_MODE=permanent$reject_code; : >"$WORK/replay-requests"
  check "a permanent $reject_code cannot starve the later valid reading" 'cloud_outbox_flush 2>/dev/null && [[ $(_outbox_count) == 0 && $(wc -l <"$WORK/replay-requests") -eq 2 && $(tail -1 "$WORK/replay-requests") == *"valid-after-$reject_code"* ]]'
  rejected_archive=$(find "$HYN_VAR/local/snapshots" -name "*-cloud-rejected-$reject_code-*.json" | head -1)
  check "a rejected $reject_code payload survives exactly in bounded local history" '[[ -s $rejected_archive && $(<"$rejected_archive") == "$rejected_payload" && ! -e $rejected_queue ]]'
  check "a quarantined $reject_code is not retried forever" 'cloud_outbox_flush && [[ $(wc -l <"$WORK/replay-requests") -eq 2 ]]'
done
CLOUD_PAYLOAD='{"sample":"reject-me-auth-fixture"}'
rejected_queue=$(local_outbox_enqueue)
OUTBOX_TEST_MODE=legacy_auth
check 'legacy 400 authentication errors preserve the retry instead of quarantining it' '! cloud_outbox_flush && [[ -s $rejected_queue ]]'
OUTBOX_TEST_MODE=legacy_paused
check 'legacy 400 administrative pauses preserve the retry instead of quarantining it' '! cloud_outbox_flush && [[ -s $rejected_queue ]]'
for OUTBOX_TEST_ERROR in \
  'agent request failed' \
  'invalid payload size or shape' \
  'permission denied for table metrics' \
  'deadlock detected' \
  'Could not find the function public.hyn_ingest in the schema cache' \
  'schema unavailable' \
  'permission denied for function monitoring payload exceeds 64 KiB'; do
  OUTBOX_TEST_MODE=uncertain400
  check "uncertain HTTP 400 is not classified as a payload rejection: $OUTBOX_TEST_ERROR" '(CLOUD_LAST_CODE=400; CLOUD_LAST_ERR="HTTP 400: $OUTBOX_TEST_ERROR"; ! _cloud_outbox_permanent_rejection)'
  check "uncertain HTTP 400 remains queued: $OUTBOX_TEST_ERROR" '! cloud_outbox_flush && [[ -s $rejected_queue && $(_outbox_count) == 1 ]]'
done
OUTBOX_TEST_MODE=permanent400
check 'a failed quarantine backup cannot retire the only retry copy' '(_local_store_publish() { return 1; }; ! cloud_outbox_flush && [[ -s $rejected_queue ]])'
OUTBOX_TEST_MODE=ok
cloud_outbox_flush || FAIL=$((FAIL + 1))
check 'early frozen clock timestamps remain padded and replayable' '(unset EPOCHSECONDS; EPOCHSECONDS=1000; CLOUD_PAYLOAD="{\"sample\":\"early-clock\"}"; path=$(local_outbox_enqueue) && [[ ${path##*/} == 000000001000_* ]] && cloud_outbox_flush && [[ ! -e $path ]])'
check 'legacy unpadded early timestamps still participate in retention' '(unset EPOCHSECONDS; EPOCHSECONDS=173800; printf "{}" >"$HYN_VAR/local/outbox/1000_node-a_2_1.json"; _local_outbox_prune_locked && [[ ! -e $HYN_VAR/local/outbox/1000_node-a_2_1.json ]])'
check 'numeric ordering handles legacy and padded timestamps together' '(unset EPOCHSECONDS; EPOCHSECONDS=1010; printf "{}" >"$HYN_VAR/local/outbox/999_node-a_2_1.json"; CLOUD_PAYLOAD="{\"sample\":\"padded-clock\"}"; path=$(local_outbox_enqueue) && [[ $(_local_outbox_paths | head -1) == */999_node-a_2_1.json ]] && cloud_outbox_flush && [[ ! -e $path && ! -e $HYN_VAR/local/outbox/999_node-a_2_1.json ]])'
check 'permanently rejected entries count against the six-attempt replay cap' '(
  HYN_VAR="$WORK/rejected-batch"; STATE_DIR=""; mkdir -p "$HYN_VAR"
  for i in {1..8}; do CLOUD_PAYLOAD="{\"sample\":\"reject-me-$i\"}"; local_outbox_enqueue >/dev/null || exit 1; done
  OUTBOX_TEST_MODE=permanent400; : >"$WORK/replay-requests"
  cloud_outbox_flush 2>/dev/null && [[ $(_outbox_count) == 2 && $(wc -l <"$WORK/replay-requests") -eq 6 ]]
)'
for i in {1..9}; do
  CLOUD_PAYLOAD="{\"sample\":\"batch-$i\"}"
  local_outbox_enqueue >/dev/null || FAIL=$((FAIL + 1))
done
: >"$WORK/replay-requests"
check 'one replay pass is capped at six records' 'cloud_outbox_flush && [[ $(wc -l <"$WORK/replay-requests") -eq 6 && $(_outbox_count) == 3 ]]'
CFG[cloud_node_id]=node-b
: >"$WORK/replay-requests"
check 'relinking cannot upload another node identitys queued readings' 'cloud_outbox_flush && [[ ! -s $WORK/replay-requests && $(_outbox_count) == 3 ]]'
CFG[cloud_node_id]=node-a
OUTBOX_TEST_MODE=expired
check 'server expiry acknowledgement retires the retry copy' 'cloud_outbox_flush && [[ $(_outbox_count) == 0 ]]'
expired_path="$HYN_VAR/local/outbox/$((EPOCHSECONDS - 172800))_node-a_2_123.json"
printf '{}\n' >"$expired_path"
snapshot_count=$(find "$HYN_VAR/local/snapshots" -name '*.json' | wc -l)
check '48-hour retry expiry preserves longer local snapshot history' 'cloud_outbox_flush && [[ ! -e $expired_path && $(find "$HYN_VAR/local/snapshots" -name "*.json" | wc -l) == "$snapshot_count" ]]'
OUTBOX_TEST_MODE=ok
printf -v CLOUD_PAYLOAD '%065537d' 0
CLOUD_PAYLOAD="{\"oversized\":\"$CLOUD_PAYLOAD\"}"
check 'oversized cloud reading is preserved locally without uploading' '! cloud_ingest_collected 1 && [[ $(_outbox_count) == 0 && $(local_history) == "$CLOUD_PAYLOAD" ]]'
printf -v quota_payload '%060000d' 0
for i in {1..565}; do
  printf '%s' "$quota_payload" >"$HYN_VAR/local/outbox/${EPOCHSECONDS}_node-a_60000_$i.json"
done
check 'outbox byte quota rotates published oldest records under 32 MiB' '_local_outbox_prune_locked && [[ $(_outbox_count) == 559 ]]'
for f in "$HYN_VAR"/local/outbox/*.json; do rm -f -- "$f"; done
for i in {1..2882}; do
  printf '{}' >"$HYN_VAR/local/outbox/${EPOCHSECONDS}_node-a_2_$i.json"
done
check 'small readings are also bounded by the 2880-entry limit' '_local_outbox_prune_locked && [[ $(_outbox_count) == 2880 ]]'
for f in "$HYN_VAR"/local/outbox/*.json; do rm -f -- "$f"; done
printf 'orphan' >"$HYN_VAR/local/outbox/.reading.orphan"
touch -t 202001010000 "$HYN_VAR/local/outbox/.reading.orphan"
printf 'recent' >"$HYN_VAR/local/outbox/.reading.recent"
check 'interrupted old temporary writes cannot accumulate forever' '_local_outbox_prune_locked && [[ ! -e $HYN_VAR/local/outbox/.reading.orphan && -e $HYN_VAR/local/outbox/.reading.recent ]]'
before_requests=$(wc -l <"$WORK/replay-requests")
check 'failed local durability prevents upload before any cloud request' '(_local_store_sync() { return 1; }; CLOUD_PAYLOAD="{\"sample\":\"cannot-persist\"}"; ! cloud_ingest_collected 1 && [[ $(wc -l <"$WORK/replay-requests") -eq $before_requests ]])'

# Existing installations may still have a five-minute settings interval. Once
# managed cloud policy is applied that must never suppress one-minute readings.
CFG[cloud_storage]=cloud; CFG[cloud_checkin_min]=5; CFG[cloud_push_min]=1
printf '%s\n' "$((EPOCHSECONDS - 65))" >"$HYN_VAR/cloud-checkin"
printf '%s\tok\n' "$((EPOCHSECONDS - 65))" >"$HYN_VAR/cloud-last-push"
cloud_configured() { return 0; }; cloud_linked() { return 0; }
cloud_config_pull() { CLOUD_CONFIG_CHANGED=0; return 1; }
cloud_command_poll() { CLOUD_COMMAND_CLAIMED=0; CLOUD_COMMAND_UPDATED=0; return 0; }
cloud_collect_full() { CLOUD_PAYLOAD='{"sample":"scheduled-current"}'; }
check 'legacy check-in cadence cannot block one-minute cloud sampling' 'cloud_push 1 1 && [[ $(tail -1 "$WORK/replay-requests") == *scheduled-current* ]]'

# Managed policy can intentionally transition legacy local-mode installations;
# clearing the managed key restores the explicitly configured local choice.
HYN_ETC="$WORK/migrate-etc"; HYN_CONFIG=''; XDG_CONFIG_HOME="$WORK/migrate-config"
mkdir -p "$HYN_ETC" "$XDG_CONFIG_HOME"
printf 'cloud_storage=local\n' >"$HYN_ETC/config"
printf 'cloud_storage=cloud\n' >"$HYN_VAR/cloud-config"
check 'explicit fleet policy transitions a legacy local-mode node' 'cfg_load && [[ ${CFG[cloud_storage]} == cloud ]]'
printf '# no managed storage override\n' >"$HYN_VAR/cloud-config"
check 'clearing fleet override restores explicit local mode' 'cfg_load && [[ ${CFG[cloud_storage]} == local ]]'

# WAN counters remain cumulative, so coalescing successful cloud reports does
# not discard bytes counted locally during skipped beats or failed requests.
HYN_VAR="$WORK/bandwidth-cadence"; STATE_DIR=''; HYN_PROC="$WORK/bandwidth-proc"
mkdir -p "$HYN_VAR" "$HYN_PROC/net" "$HYN_PROC/sys/kernel/random"
printf 'bandwidth-fixture-boot\n' >"$HYN_PROC/sys/kernel/random/boot_id"
net_find_wan() { NET_WAN=eth0; return 0; }
_bandwidth_fixture() { printf 'eth0: %s 0 0 0 0 0 0 0 %s 0 0 0 0 0 0 0\n' "$1" "$2" >"$HYN_PROC/net/dev"; }
OUTBOX_TEST_MODE=ok; : >"$WORK/replay-requests"
_bandwidth_fixture 10 20
cloud_record_bandwidth test-private-node-token
check 'first cumulative bandwidth report saves a success checkpoint' '[[ -s $HYN_VAR/cloud-bandwidth-sent && $(wc -l <"$WORK/replay-requests") -eq 1 ]]'
_bandwidth_fixture 15 26
cloud_record_bandwidth test-private-node-token
check 'a following beat records local bytes without another cloud write' '[[ $(wc -l <"$WORK/replay-requests") -eq 1 && $(tail -1 "$HYN_VAR/local/bandwidth-state") == *"\"observed_total_bytes\":\"11\""* ]]'
bandwidth_prior=$((EPOCHSECONDS - 61))
printf '%s\n' "$bandwidth_prior" >"$HYN_VAR/cloud-bandwidth-sent"
OUTBOX_TEST_MODE=down; _bandwidth_fixture 20 30
cloud_record_bandwidth test-private-node-token
check 'a failed WAN report does not advance its successful cadence checkpoint' '[[ $(<"$HYN_VAR/cloud-bandwidth-sent") == "$bandwidth_prior" && $(wc -l <"$WORK/replay-requests") -eq 2 ]]'
OUTBOX_TEST_MODE=ok; _bandwidth_fixture 25 38
cloud_record_bandwidth test-private-node-token
check 'WAN recovery retries next beat with cumulative counters and no local byte loss' '[[ $(wc -l <"$WORK/replay-requests") -eq 3 && $(tail -1 "$WORK/replay-requests") == *"\"p_rx\":25,\"p_tx\":38"* && $(tail -1 "$HYN_VAR/local/bandwidth-state") == *"\"observed_total_bytes\":\"33\""* ]]'

# Drive the real resolver/transport with an injected monotonic clock and curl
# fixture. Discovery and upload must spend the same15-second budget, including
# a failed first hostname; tests make no real network call or blocking sleep.
check 'discovery and upload share the remaining replay time budget' '(
  source "$HYN_LIB/cloud.sh"
  HYN_VAR="$WORK/deadline-shared"; STATE_DIR=""; mkdir -p "$HYN_VAR"
  CFG[cloud_api_url]="https://www.hyn-view.in/api/agent/v1"; CFG[cloud_url]=""; CFG[cloud_anon_key]=""
  CLOUD_RPC_DEADLINE_MS=16000
  printf "1000\n" >"$HYN_VAR/clock"
  sample_clock_ms_v() { read -r SAMPLE_CLOCK_MS <"$HYN_VAR/clock"; }
  curl() {
    local previous="" argument maximum=""
    for argument in "$@"; do [[ $previous != --max-time ]] || maximum=$argument; previous=$argument; done
    if [[ ${*: -1} == */health ]]; then
      printf "health:%s\n" "$maximum" >>"$HYN_VAR/timeouts"
      printf "13000\n" >"$HYN_VAR/clock"
      printf "{\"service\":\"hyn-agent-v1\"}"
    else
      printf "upload:%s\n" "$maximum" >>"$HYN_VAR/timeouts"
      printf "{\"status\":\"ok\"}\n200 2 15"
    fi
  }
  _cloud_rpc hyn_ingest "{}" && [[ $(<"$HYN_VAR/timeouts") == $'"'"'health:15.000\nupload:3.000'"'"' ]]
)'
check 'exhausted discovery cannot begin a second hostname or upload' '(
  source "$HYN_LIB/cloud.sh"
  HYN_VAR="$WORK/deadline-exhausted"; STATE_DIR=""; mkdir -p "$HYN_VAR"
  CFG[cloud_api_url]="https://www.hyn-view.in/api/agent/v1"; CFG[cloud_url]=""; CFG[cloud_anon_key]=""
  CLOUD_RPC_DEADLINE_MS=16000
  printf "1000\n" >"$HYN_VAR/clock"
  sample_clock_ms_v() { read -r SAMPLE_CLOCK_MS <"$HYN_VAR/clock"; }
  curl() { printf "request\n" >>"$HYN_VAR/requests"; printf "16000\n" >"$HYN_VAR/clock"; return 7; }
  ! _cloud_rpc hyn_ingest "{}" && [[ $(wc -l <"$HYN_VAR/requests") -eq 1 && $CLOUD_LAST_CODE == 0 && $CLOUD_LAST_ERR == *"time budget exhausted"* ]]
)'
check 'failed discovery cannot reuse an earlier payload rejection status' '(
  source "$HYN_LIB/cloud.sh"
  HYN_VAR="$WORK/deadline-unreachable"; STATE_DIR=""; mkdir -p "$HYN_VAR"
  CFG[cloud_api_url]="https://www.hyn-view.in/api/agent/v1"; CFG[cloud_url]=""; CFG[cloud_anon_key]=""
  CLOUD_LAST_CODE=400; CLOUD_LAST_ERR="invalid payload"
  curl() { return 7; }
  ! _cloud_rpc hyn_ingest "{}" && [[ $CLOUD_LAST_CODE == 0 ]] && ! _cloud_outbox_permanent_rejection
)'
printf '%s checks passed; %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
