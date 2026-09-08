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
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else printf 'FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); fi; }
is_root() { return 0; }
cfg_load
check 'default history is local' '[[ ${CFG[cloud_storage]} == local ]]'
check 'bad numeric property is refused without changing file' '! config_set cloud_checkin_min 0 2>/dev/null && [[ ! -f $HYN_ETC/config ]]'
BAD_SETTING=$'mono\ncloud_storage=cloud'
check 'multiline cannot inject a second property' '! config_set theme "$BAD_SETTING" 2>/dev/null'
check 'portal cannot enable cloud archive or notifications' '! _cfg_cloud_allowed cloud_storage && ! _cfg_cloud_allowed cloud_notifications'
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

secret() { printf 'test-private-node-token'; }
_cloud_rpc_once() {
  printf '%s\n' "$1" >>"$WORK/actions"
  CLOUD_LAST_BODY='{"status":"ok","node_status":"active"}'
  CLOUD_LAST_CODE=200; CLOUD_LAST_ERR=''
}
CFG[cloud_api_url]='http://127.0.0.1:9999/api/agent/v1'
CFG[cloud_url]=''; CFG[cloud_anon_key]=''
check 'manual reading uses transient action' 'cloud_ingest_collected 1 && [[ $(tail -1 "$WORK/actions") == hyn_transient_snapshot ]]'
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
printf '%s checks passed; %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
