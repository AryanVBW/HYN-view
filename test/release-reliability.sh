#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HYN_ROOT="$ROOT" HYN_LIB="$ROOT/lib" HYN_ETC="$WORK/etc" HYN_VAR="$WORK/state"
export HYN_PROC="$WORK/proc" XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/user-state" HYN_CONFIG=''
mkdir -p "$HYN_ETC" "$HYN_VAR" "$HYN_PROC"
source "$HYN_LIB/core.sh"
source "$HYN_LIB/notify.sh"
source "$HYN_LIB/cloud.sh"
cfg_load
PASS=0 FAIL=0
check() { if eval "$2"; then ((PASS+=1)); else printf 'FAIL %s\n' "$1"; ((FAIL+=1)); fi; }

check 'stable release supersedes prerelease' 'ver_gt 1.11.0 1.11.0-rc.2'
check 'prerelease cannot downgrade stable' '! ver_gt 1.11.0-rc.9 1.11.0'
check 'prerelease numeric ordering is exact' 'ver_gt 1.11.0-rc.11 1.11.0-rc.2'
check 'build metadata does not change precedence' '! ver_gt 1.11.0+build.9 1.11.0+build.1'
check 'invalid padded versions are rejected' '! ver_valid 1.08.0 && ! ver_valid 1.0.0-rc.01'
check 'large version components do not overflow' 'ver_gt 999999999999999999999.0.0 999999999999999999998.0.0'

printf '100.25 999.99\n' >"$HYN_PROC/uptime"
sample_clock_ms_v
check 'sampling clock uses uptime in exact milliseconds' '[[ $SAMPLE_CLOCK_MS == 100250 ]]'

cloud_configured() { return 0; }
cloud_linked() { return 0; }
secret() { printf fixture-token; }
_cloud_rpc() { CLOUD_LAST_BODY=$MOCK_BODY; return 0; }
MOCK_BODY='{"node_status":"active","config":{"report_at":"07:30"}}'
check 'valid portal setting persists' 'cloud_config_pull 1 && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{}'
check 'incomplete response retains known settings' '! cloud_config_pull 1 && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"node_status":"active","config":{}'
check 'missing outer envelope cannot erase settings' '! cloud_config_pull 1 && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"node_status":"active","config":{"report_at":"bad"}}'
check 'invalid replacement retains the previous valid schedule' 'cloud_config_pull 1 && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY=$'{"node_status":"active","config":{\n\t"report_at": "08:30"\n}}'
check 'formatted JSON keys apply their intended settings' 'cloud_config_pull 1 && grep -q "report_at=08:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"node_status":"active","config":{"report_at":"07:30"}}'
cloud_config_pull 1
(
  _local_store_sync() { return 1; }
  MOCK_BODY='{"node_status":"active","config":{}}'
  cloud_config_pull 1 2>/dev/null
)
flush_rc=$?
check 'failed settings flush preserves committed configuration' '((flush_rc != 0)) && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"node_status":"active","config":{"report_at":"09:30"'
check 'truncated response retains known settings' '! cloud_config_pull 1 && grep -q "report_at=07:30" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"node_status":"active","config":{}}'
check 'empty managed settings releases overrides successfully' 'cloud_config_pull 1 && ! grep -q "report_at=" "$HYN_VAR/cloud-config"'
MOCK_BODY='{"status":"command"}'
check 'missing command fields fail without crashing the caller' '! cloud_command_poll 1'
check 'settings cache is private' '[[ $(find "$HYN_VAR" -name cloud-config -perm -004 | wc -l) -eq 0 ]]'
printf -v padding '%100000s' ''
large_body="{\"node_status\":\"active\",\"template\":\"$padding\",\"config\":{}}"
now_ms_v; scan_started=$NOW_MS
check 'large template envelope and value survive validation' '_cloud_complete_object "$large_body" && json_field_v "$large_body" template && [[ $JSON_FIELD == "$padding" ]]'
now_ms_v
check 'large settings validation avoids per-character string copying' '((NOW_MS - scan_started < 3000))'
escaped_body='{"config":{},"reason":"brace } and quote \" accepted"}'
check 'escaped quotes and braces are nonstructural' '_cloud_complete_object "$escaped_body"'

alerts_collect() { :; }
alerts_evaluate() { :; }
net_link() { :; }
net_identity() { :; }
net_tuning() { :; }
proc_sample() { printf '%s\n' "$1" >>"$WORK/process-intervals"; }
sleep() { printf '102.00 999.99\n' >"$HYN_PROC/uptime"; }
cloud_payload_v() { CLOUD_PAYLOAD='{}'; }
local_store_snapshot() { :; }
cloud_collect_full
check 'process rates use actual elapsed time including scheduling delay' '[[ $(tail -1 "$WORK/process-intervals") == 1750 ]]'

mkdir -p "$WORK/installed/bin"
cat >"$WORK/installed/bin/hyn" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$HYN_VAR/verification-argv"
SH
chmod +x "$WORK/installed/bin/hyn"
CLOUD_COMMAND_TARGET=$HYN_VERSION
CLOUD_COMMAND_ID=11111111-1111-4111-8111-111111111111
printf -v expected_argv 'cloud\nverify-update\n%s\n%s' "$HYN_VERSION" "$CLOUD_COMMAND_ID"
(
  HYN_ROOT="$WORK/installed"
  cloud_verify_installed_update
)
check 'verification invokes installed executable with expected version and command' '[[ $(cat "$HYN_VAR/verification-argv") == "$expected_argv" ]]'
version_output=$(bash "$ROOT/bin/hyn" --version)
check 'original 1.8.0 updater can parse new CLI version' '[[ ${version_output##* } == "$HYN_VERSION" && $version_output != *$'"'\n'"'* ]]'

cloud_command_report() { printf '%s\n' "$1" >>"$WORK/progress"; [[ $1 != succeeded || ${REPORT_FAIL:-0} == 0 ]]; }
cloud_collect_full() { printf collected >>"$WORK/collected"; return "${COLLECT_FAIL:-0}"; }
cloud_ingest_collected() { CLOUD_INGESTED=${INGEST_OK:-1}; return 0; }
check 'different installed version refuses verification before collection' '! cloud_finish_update 0.0.0 "$CLOUD_COMMAND_ID" && [[ ! -e $WORK/collected ]]'
check 'fresh collector and accepted snapshot complete the command' 'cloud_finish_update "$HYN_VERSION" "$CLOUD_COMMAND_ID" && [[ $(tail -1 "$WORK/progress") == succeeded ]]'
INGEST_OK=0
check 'paused or unaccepted snapshot cannot count as verified update' '! cloud_finish_update "$HYN_VERSION" "$CLOUD_COMMAND_ID"'
INGEST_OK=1 REPORT_FAIL=1
check 'lost completion receipt propagates failure' '! cloud_finish_update "$HYN_VERSION" "$CLOUD_COMMAND_ID"'
printf '\n%s release reliability checks passed; %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
