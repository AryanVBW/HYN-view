#!/usr/bin/env bash
# Private, bounded local history. No request bodies or credentials in usage logs.

# shellcheck source=lib/decimal.sh
source "${HYN_LIB:-${BASH_SOURCE[0]%/*}}/decimal.sh"

local_store_dir_v() {
  state_dir_v
  LOCAL_STORE="$STATE_DIR/local"
  local fresh=0
  [[ -d $LOCAL_STORE/snapshots && -d $LOCAL_STORE/usage && -d $LOCAL_STORE/bandwidth && -d $LOCAL_STORE/outbox ]] || fresh=1
  (umask 077; mkdir -p "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" "$LOCAL_STORE/bandwidth" "$LOCAL_STORE/outbox") || return 1
  chmod 700 "$LOCAL_STORE" "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" "$LOCAL_STORE/bandwidth" "$LOCAL_STORE/outbox" || return 1
  if ((fresh)); then
    _local_store_sync "$LOCAL_STORE" && _local_store_sync "$STATE_DIR" && _local_store_sync "${STATE_DIR%/*}" || return 1
  fi
}

# Ubuntu's GNU sync with a file operand calls fsync for only that file/directory.
# Never use sync -f or global sync, which can stall on unrelated writes. macOS is
# only a development/test host; the published package explicitly targets Linux.
_local_store_sync() {
  [[ ${OSTYPE:-} == linux* ]] || return 0
  sync -- "$1"
}

# Atomic replacement with durable contents and rename on supported Linux hosts.
_local_store_publish() {
  local tmp=$1 dest=$2
  _local_store_sync "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$dest" || { rm -f -- "$tmp"; return 1; }
  _local_store_sync "${dest%/*}"
}

# The checkpoint contains a validated TSV baseline followed by the complete JSON
# calculation that produced it. Archive that committed calculation BEFORE the
# next checkpoint replaces it: a crash can duplicate an archive, never double
# count bytes or leave the only copy of the last calculation in a temporary file.
# The checkpoint is exempt from history retention. JSON integers are strings so
# JS viewers cannot round exact uint64 inputs or long-lived cumulative totals.
local_bandwidth_record() (
  local iface=$1 boot=$2 rx=$3 tx=$4 wall=${5:-} mono=${6:-}
  local lock_fd state version seq=0 pw=0 pm=0 pb='' pi='' pr=0 pt=0
  local total_rx=0 total_tx=0 started=0 gaps=0 reason=baseline old_json=''
  local dr=0 dt=0 delta_ms=0 json tmp date archived incomplete=true
  local generation='-' previous_generation='-'
  [[ $iface =~ ^[A-Za-z0-9_.:-]{1,64}$ && $boot =~ ^[A-Za-z0-9-]{1,64}$ ]] || return 1
  if [[ -r ${HYN_SYS:-/sys}/class/net/$iface/ifindex ]]; then
    read -r generation <"${HYN_SYS:-/sys}/class/net/$iface/ifindex" || return 1
    [[ $generation =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  fi
  uint_normalize_v "$rx" || return 1; rx=$UINT_VALUE
  uint_normalize_v "$tx" || return 1; tx=$UINT_VALUE
  uint_compare_v "$rx" 18446744073709551615; ((UINT_COMPARE <= 0)) || return 1
  uint_compare_v "$tx" 18446744073709551615; ((UINT_COMPARE <= 0)) || return 1
  if [[ -z $wall ]]; then now_ms_v; wall=$NOW_MS; fi
  if [[ -z $mono ]]; then
    if declare -F sample_clock_ms_v >/dev/null; then sample_clock_ms_v; mono=$SAMPLE_CLOCK_MS
    else mono=$wall; fi
  fi
  [[ $wall =~ ^[1-9][0-9]{0,14}$ && $mono =~ ^[0-9]{1,15}$ ]] || return 1
  local_store_dir_v || return 1
  # Fail closed if a minimal non-Ubuntu host lacks locking. Lock lifetime belongs
  # to the open descriptor, so crashes/reboots never leave a stale lock owner.
  have flock || return 1
  umask 077
  exec {lock_fd}>"$LOCAL_STORE/bandwidth.lock" || return 1
  flock -w 10 "$lock_fd" || return 1
  state="$LOCAL_STORE/bandwidth-state"
  if [[ -e $state ]]; then
    {
      IFS=$'\t' read -r version seq pw pm pb pi pr pt total_rx total_tx started gaps reason previous_generation || return 1
      IFS= read -r old_json || return 1
    } <"$state"
    previous_generation=${previous_generation:--}
    [[ $version == 1 && $seq =~ ^[1-9][0-9]{0,11}$ && $pw =~ ^[1-9][0-9]{0,14}$ &&
       $pm =~ ^[0-9]{1,15}$ && $pb =~ ^[A-Za-z0-9-]{1,64}$ && $pi =~ ^[A-Za-z0-9_.:-]{1,64}$ &&
       $started =~ ^[1-9][0-9]{0,14}$ && $gaps =~ ^[0-9]{1,12}$ &&
       $previous_generation =~ ^(-|[1-9][0-9]{0,9})$ &&
       $old_json == '{"schema":1,'* && $old_json == *'}' ]] || return 1
    local number
    for number in "$pr" "$pt" "$total_rx" "$total_tx"; do
      uint_normalize_v "$number" && [[ $UINT_VALUE == "$number" ]] || return 1
    done
    if [[ $boot == "$pb" ]] && ((mono < pm)); then
      # A slower overlapping collector completed after a newer heartbeat. It
      # must not move the counter baseline backwards and count bytes twice.
      return 0
    fi
    if [[ $boot == "$pb" && $iface == "$pi" && $generation == "$previous_generation" ]]; then
      if [[ $rx == "$pr" && $tx == "$pt" ]] && ((mono == pm)); then return 0; fi
      uint_compare_v "$rx" "$pr"; local rx_compare=$UINT_COMPARE
      uint_compare_v "$tx" "$pt"; local tx_compare=$UINT_COMPARE
      # /proc/uptime can have 10ms resolution. Two overlapping reads in the
      # same clock tick can finish in reverse order; never reseed backwards.
      if ((mono == pm && (rx_compare < 0 || tx_compare < 0))); then return 0; fi
      if ((rx_compare >= 0 && tx_compare >= 0)); then
        uint_subtract_v "$rx" "$pr"; dr=$UINT_VALUE
        uint_subtract_v "$tx" "$pt"; dt=$UINT_VALUE
        reason=observed incomplete=false
        delta_ms=$((mono - pm))
      else
        reason=counter_reset gaps=$((gaps + 1))
      fi
    elif [[ $boot != "$pb" ]]; then reason=reboot gaps=$((gaps + 1))
    elif [[ $iface == "$pi" ]]; then reason=interface_recreated gaps=$((gaps + 1))
    else reason=interface_change gaps=$((gaps + 1)); fi
  else started=$wall; fi
  uint_add_v "$total_rx" "$dr"; total_rx=$UINT_VALUE
  uint_add_v "$total_tx" "$dt"; total_tx=$UINT_VALUE
  uint_add_v "$total_rx" "$total_tx"; local total=$UINT_VALUE
  seq=$((seq + 1))
  json="{\"schema\":1,\"sequence\":$seq,\"sampled_at_ms\":\"$wall\",\"monotonic_ms\":\"$mono\",\"boot_id\":\"$boot\",\"iface\":\"$iface\",\"ifindex\":\"$generation\",\"rx_bytes\":\"$rx\",\"tx_bytes\":\"$tx\",\"previous_sampled_at_ms\":\"$pw\",\"previous_monotonic_ms\":\"$pm\",\"previous_boot_id\":\"$pb\",\"previous_iface\":\"$pi\",\"previous_ifindex\":\"$previous_generation\",\"previous_rx_bytes\":\"$pr\",\"previous_tx_bytes\":\"$pt\",\"elapsed_ms\":\"$delta_ms\",\"delta_rx_bytes\":\"$dr\",\"delta_tx_bytes\":\"$dt\",\"observed_rx_bytes\":\"$total_rx\",\"observed_tx_bytes\":\"$total_tx\",\"observed_total_bytes\":\"$total\",\"started_at_ms\":\"$started\",\"discontinuities\":$gaps,\"incomplete\":$incomplete,\"reason\":\"$reason\"}"
  if [[ -n $old_json ]]; then
    printf -v date '%(%Y-%m-%d-%H%M%S)T' "$((pw / 1000))"
    archived="$LOCAL_STORE/bandwidth/$date-$((seq - 1)).json"
    tmp=$(mktemp "$LOCAL_STORE/bandwidth/.calculation.XXXXXX") || return 1
    printf '%s\n' "$old_json" >"$tmp" || { rm -f -- "$tmp"; return 1; }
    _local_store_publish "$tmp" "$archived" || return 1
  fi
  tmp=$(mktemp "$LOCAL_STORE/.bandwidth-state.XXXXXX") || return 1
  printf '1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n%s\n' \
    "$seq" "$wall" "$mono" "$boot" "$iface" "$rx" "$tx" "$total_rx" "$total_tx" "$started" "$gaps" "$reason" "$generation" "$json" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  _local_store_publish "$tmp" "$state"
)

local_bandwidth_snapshot() {
  local iface=${NET_WAN:-} boot
  # An arbitrary caller-provided JSON document is still a valid snapshot; only
  # real collector samples have the metadata needed for counter accounting.
  [[ -n $iface && ${NET_LAST_MS:-0} -gt 0 ]] || return 0
  [[ -v NET_RX[$iface] && -v NET_TX[$iface] && -r $HYN_PROC/sys/kernel/random/boot_id ]] || return 0
  read -r boot <"$HYN_PROC/sys/kernel/random/boot_id" || return 1
  local_bandwidth_record "$iface" "$boot" "${NET_RX[$iface]}" "${NET_TX[$iface]}" "$NET_LAST_MS" "${NET_SAMPLE_MONO_MS:-$NET_LAST_MS}"
}

local_store_prune() (
  local days=${CFG[local_keep_days]:-14} mb=${CFG[local_max_mb]:-256} kb file size lock_fd
  if have flock; then
    (umask 077; touch "$LOCAL_STORE/history.lock") || return 1
    exec {lock_fd}>"$LOCAL_STORE/history.lock" || return 1
    flock -w 10 "$lock_fd" || return 1
  fi
  [[ $days =~ ^[1-9][0-9]{0,2}$ ]] || days=14
  [[ $mb =~ ^[1-9][0-9]{0,4}$ ]] || mb=256
  # Only agent-owned history is rotated. Secrets, settings and existing report
  # files never enter this traversal. Keep at most days complete 24h periods.
  find "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" "$LOCAL_STORE/bandwidth" -type f ! -name '.*' -mtime +"$((days - 1))" -delete || return 1
  # The separately bounded retry queue must not evict the long-term backup.
  kb=$(du -sk "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" "$LOCAL_STORE/bandwidth" 2>/dev/null |
    awk '{total += $1} END {printf "%.0f", total}')
  [[ $kb =~ ^[0-9]+$ ]] || return 1
  ((kb > mb * 1024)) || return 0
  while IFS= read -r file; do
    ((kb <= mb * 1024)) && break
    size=$(du -k "$file" 2>/dev/null); size=${size%%[[:space:]]*}
    [[ $size =~ ^[0-9]+$ ]] || continue
    rm -f -- "$file" || return 1
    kb=$((kb - size))
  done < <(find "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" "$LOCAL_STORE/bandwidth" -type f ! -name '.*' |
    while IFS= read -r path; do printf '%s\t%s\n' "${path##*/}" "$path"; done |
    LC_ALL=C sort | cut -f2-)
)

local_store_snapshot() {
  local_store_dir_v || return 1
  local_bandwidth_snapshot || return 1
  local tmp name date fraction
  # mktemp + rename permits simultaneous record/push/update processes without
  # interleaved JSON or a shared .tmp file. Do not persist the token envelope.
  tmp=$(mktemp "$LOCAL_STORE/snapshots/.snapshot.XXXXXX") || return 1
  if ! printf '%s\n' "$CLOUD_PAYLOAD" >"$tmp"; then rm -f "$tmp"; return 1; fi
  printf -v date '%(%Y-%m-%d-%H%M%S)T' -1
  fraction=${EPOCHREALTIME#*[.,]}
  name="$LOCAL_STORE/snapshots/$date-$fraction-${tmp##*.}.json"
  _local_store_publish "$tmp" "$name" || return 1
  CLOUD_LOCAL_SNAPSHOT=$name
  local_store_prune || return 1
  CLOUD_LOCAL_PAYLOAD=$CLOUD_PAYLOAD
}

# Retry records contain only an immutable telemetry payload. The node identity
# in each filename prevents an unlink/relink from replaying one owner's history
# to another owner. The credential envelope is reconstructed only in memory.
# Limits are intentionally independent of the longer local history: 48 hours,
# 2880 readings and 32 MiB. Every evicted reading still has its local backup,
# subject to that backup's separately configured age and disk limits.
_local_outbox_paths() {
  local f name epoch
  # Sort the normalized numeric timestamp, including retry files written by a
  # previous version without padding. A corrected/very early host clock must
  # not leave entries invisible to replay or to the queue's resource limits.
  for f in "$LOCAL_STORE"/outbox/*.json; do
    [[ -f $f && ! -L $f ]] || continue
    name=${f##*/}
    [[ $name =~ ^([0-9]{1,12})_([A-Za-z0-9-]{1,64})_([0-9]{1,5})_([0-9]+)\.json$ ]] || continue
    epoch=$((10#${BASH_REMATCH[1]}))
    printf '%012d\t%s\n' "$epoch" "$f"
  done | LC_ALL=C sort | cut -f2-
}

_local_outbox_prune_locked() {
  local now=${EPOCHSECONDS:-0} f name epoch node bytes checksum total=0 count=0
  [[ $now =~ ^[0-9]{1,12}$ ]] || return 1
  now=$((10#$now))
  local -a kept=()
  # An interrupted atomic write may leave a private temporary file. Pruning
  # owns the writer lock, so old temp files cannot belong to an active writer.
  find "$LOCAL_STORE/outbox" -type f -name '.reading.*' -mmin +10 -delete || return 1
  find "$LOCAL_STORE/snapshots" -type f -name '.rejected.*' -mmin +10 -delete || return 1
  while IFS= read -r f; do
    [[ -f $f && ! -L $f ]] || continue
    name=${f##*/}
    [[ $name =~ ^([0-9]{1,12})_([A-Za-z0-9-]{1,64})_([0-9]{1,5})_([0-9]+)\.json$ ]] || continue
    epoch=$((10#${BASH_REMATCH[1]})) node=${BASH_REMATCH[2]} bytes=$((10#${BASH_REMATCH[3]})) checksum=${BASH_REMATCH[4]}
    if ((now - epoch >= 172800)); then rm -f -- "$f" || return 1; continue; fi
    kept+=("$f")
    total=$((total + bytes)); count=$((count + 1))
  done < <(_local_outbox_paths)
  for f in "${kept[@]}"; do
    ((count > 2880 || total > 33554432)) || break
    name=${f##*/}; name=${name#*_}; name=${name#*_}; bytes=${name%%_*}; bytes=$((10#$bytes))
    rm -f -- "$f" || return 1
    count=$((count - 1)); total=$((total - bytes))
  done
  _local_store_sync "$LOCAL_STORE/outbox"
}

local_outbox_enqueue() (
  local node=${CFG[cloud_node_id]:-} tmp dest fingerprint bytes lock_fd epoch=${EPOCHSECONDS:-0}
  [[ $node =~ ^[A-Za-z0-9-]{1,64}$ ]] || return 1
  [[ $epoch =~ ^[0-9]{1,12}$ ]] || return 1
  printf -v epoch '%012d' "$((10#$epoch))"
  [[ ${CLOUD_PAYLOAD:-} == '{'* && $CLOUD_PAYLOAD == *'}' ]] || return 1
  # This limit matches the hosted wire contract; oversized readings stay local.
  bytes=$(LC_ALL=C printf '%s' "$CLOUD_PAYLOAD" | wc -c); bytes=${bytes//[[:space:]]/}
  ((bytes > 0 && bytes <= 60000)) || return 1
  local_store_dir_v || return 1
  have flock || return 1
  umask 077
  exec {lock_fd}>"$LOCAL_STORE/outbox.lock" || return 1
  flock -w 2 "$lock_fd" || return 1
  _local_outbox_prune_locked || return 1
  fingerprint=$(printf '%s' "$CLOUD_PAYLOAD" | cksum) || return 1
  fingerprint=${fingerprint%% *}
  dest="$LOCAL_STORE/outbox/${epoch}_${node}_${bytes}_${fingerprint}.json"
  tmp=$(mktemp "$LOCAL_STORE/outbox/.reading.XXXXXX") || return 1
  printf '%s\n' "$CLOUD_PAYLOAD" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  _local_store_publish "$tmp" "$dest" || return 1
  _local_outbox_prune_locked || return 1
  printf '%s' "$dest"
)

# A permanently rejected retry must not starve valid later records. Preserve
# its exact payload in the ordinary bounded local history BEFORE retiring its
# queue copy. A disk/flush failure leaves the retry in place for recovery.
local_outbox_quarantine() {
  local queued=$1 payload=$2 code=$3 tmp date name
  [[ $queued == "$LOCAL_STORE/outbox/"* && -f $queued && ! -L $queued ]] || return 1
  [[ $code == 400 || $code == 413 ]] || return 1
  printf -v date '%(%Y-%m-%d-%H%M%S)T' -1
  name="$LOCAL_STORE/snapshots/$date-cloud-rejected-$code-${queued##*/}"
  tmp=$(mktemp "$LOCAL_STORE/snapshots/.rejected.XXXXXX") || return 1
  printf '%s\n' "$payload" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  _local_store_publish "$tmp" "$name" || return 1
  local_store_prune || return 1
  # Retention must actually have preserved this backup before its retry copy
  # can be retired (e.g. a clock correction can change filename ordering).
  [[ -s $name ]] || return 1
  rm -f -- "$queued" || return 1
  _local_store_sync "$LOCAL_STORE/outbox"
}

local_store_report() {
  local_store_dir_v || return 1
  local tmp date
  tmp=$(mktemp "$LOCAL_STORE/snapshots/.report.XXXXXX") || return 1
  if ! printf '%s\n' "$1" >"$tmp"; then rm -f "$tmp"; return 1; fi
  printf -v date '%(%Y-%m-%d-%H%M%S)T' -1
  _local_store_publish "$tmp" "$LOCAL_STORE/snapshots/$date-report-${tmp##*.}.txt" || return 1
  local_store_prune
}

local_usage_record() (
  local action=$1 code=$2 sent=$3 received=$4 rc=$5 day f last=0 lock_fd fresh=0
  local_store_dir_v || return 1
  [[ $action =~ ^[a-z_]+$ && $code =~ ^[0-9]{1,3}$ && $rc =~ ^[0-9]{1,3}$ ]] || return 1
  uint_normalize_v "$sent" || return 1; sent=$UINT_VALUE
  uint_normalize_v "$received" || return 1; received=$UINT_VALUE
  printf -v day '%(%Y-%m-%d)T' -1
  f="$LOCAL_STORE/usage/$day.tsv"
  if have flock; then
    (umask 077; touch "$LOCAL_STORE/history.lock") || return 1
    exec {lock_fd}>"$LOCAL_STORE/history.lock" || return 1
    flock -w 10 "$lock_fd" || return 1
  fi
  [[ -e $f ]] || fresh=1
  # One short append per request; O_APPEND avoids shared counter update races.
  # The lock also prevents retention from unlinking an actively written log.
  (umask 077; printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${EPOCHSECONDS:-0}" "$action" "$code" "$sent" "$received" "$rc" >>"$f") || return 1
  _local_store_sync "$f" || return 1
  ((fresh == 0)) || _local_store_sync "$LOCAL_STORE/usage" || return 1
  [[ -z ${lock_fd:-} ]] || exec {lock_fd}>&-
  [[ -r $LOCAL_STORE/pruned ]] && read -r last <"$LOCAL_STORE/pruned"
  [[ $last =~ ^[0-9]+$ ]] || last=0
  if ((${EPOCHSECONDS:-0} < last || ${EPOCHSECONDS:-0} - last >= 3600)); then
    local_store_prune || return 1
    (umask 077; printf '%s\n' "${EPOCHSECONDS:-0}" >"$LOCAL_STORE/pruned") || return 1
  fi
  return 0
)

local_history() {
  local n=${1:-1} f
  [[ $n =~ ^[1-9][0-9]{0,3}$ ]] || { warn 'history count must be 1..9999'; return 1; }
  local_store_dir_v || return 1
  while IFS= read -r f; do cat "$f" || return 1; done < <(
    find "$LOCAL_STORE/snapshots" -type f -name '*.json' | LC_ALL=C sort | tail -n "$n"
  )
}

local_logs() {
  local n=${1:-50} f
  [[ $n =~ ^[1-9][0-9]{0,3}$ ]] || { warn 'log count must be 1..9999'; return 1; }
  state_dir_v
  for f in "$STATE_DIR/alert-log" "$STATE_DIR/notify-log"; do
    [[ -r $f ]] && { printf '\n%s\n' "$f"; tail -n "$n" "$f"; }
  done
  if have journalctl; then
    journalctl --no-pager -n "$n" -u hyn-agent.service -u hyn-push.service -u hyn-update.service -u hyn-awake.service
  fi
  return 0
}

cloud_usage() {
  local nodes=${1:-1} beat=${CFG[heartbeat_sec]:-300} checkin=${CFG[cloud_checkin_min]:-5} push=${CFG[cloud_push_min]:-5} monthly snapshots=0
  [[ $nodes =~ ^[1-9][0-9]{0,4}$ ]] || { warn 'usage: hyn cloud usage [1..99999 nodes]'; return 1; }
  [[ $beat =~ ^[1-9][0-9]{0,3}$ ]] && ((beat >= 5 && beat <= 3600)) || beat=300
  [[ $checkin =~ ^[1-9][0-9]{0,2}$ ]] && ((checkin <= 60)) || checkin=5
  [[ $push =~ ^[1-9][0-9]{0,3}$ ]] && ((push <= 1440)) || push=5
  if [[ ${CFG[cloud_storage]:-cloud} == cloud ]]; then
    ((checkin <= push)) || checkin=$push
    snapshots=$((43200 / push))
  fi
  # Approximate the actual timer cadence for successful cumulative WAN posts.
  local bandwidth_interval=$((((60 + beat - 1) / beat) * beat))
  monthly=$(((2592000 / beat + 2592000 / bandwidth_interval + 2 * 43200 / checkin + snapshots) * nodes))
  local_store_dir_v || return 1
  local ts action code sent received rc total=0 failed=0 tx=0 rx=0 f since projected_rx
  since=$((${EPOCHSECONDS:-0} - 86400))
  for f in "$LOCAL_STORE"/usage/*.tsv; do
    [[ -r $f ]] || continue
    while IFS=$'\t' read -r ts action code sent received rc; do
      [[ $ts =~ ^[1-9][0-9]{0,11}$ && $code =~ ^[0-9]{1,3}$ && $rc =~ ^[0-9]{1,3}$ ]] || continue
      ((ts >= since && ts <= ${EPOCHSECONDS:-0})) || continue
      uint_normalize_v "$sent" || continue; sent=$UINT_VALUE
      uint_normalize_v "$received" || continue; received=$UINT_VALUE
      total=$((total + 1))
      uint_add_v "$tx" "$sent"; tx=$UINT_VALUE
      uint_add_v "$rx" "$received"; rx=$UINT_VALUE
      ((10#$rc != 0 || 10#$code < 200 || 10#$code >= 300)) && failed=$((failed + 1))
    done <"$f"
  done
  printf 'Storage mode: %s\nLocal history: %s\n' "${CFG[cloud_storage]:-cloud}" "$LOCAL_STORE"
  printf 'Cloud history: rolling 48 hours; retry queue: at most 2880 readings / 32 MiB.\n'
  printf 'Last 24h: %s requests, %s failures, %s body bytes sent, %s body bytes received\n' "$total" "$failed" "$tx" "$rx"
  uint_add_v "$rx" "$rx"; uint_add_v "$UINT_VALUE" "$rx"; uint_normalize_v "${UINT_VALUE}0"; projected_rx=$UINT_VALUE
  printf '30-day projection at this measured rate: %s requests, %s received bytes\n' "$((total * 30))" "$projected_rx"
  printf 'Configured baseline for %s node(s): about %s POSTs per 30 days (heartbeats, WAN counters, config, polling and readings; excludes command execution and retries)\n' "$nodes" "$monthly"
  printf 'Retention: %s days, at most %s MiB (oldest local history rotates first)\n' "${CFG[local_keep_days]:-14}" "${CFG[local_max_mb]:-256}"
  printf 'These are this CLI\x27s HTTP body totals, not Supabase egress or account billing.\n'
  printf 'Verify project database/egress in Supabase Usage and credits/dyno hours in Heroku Billing.\n'
  printf 'Supabase Free reference: 500 MB database, 5 GB uncached egress, 1 GB storage.\n'
  printf 'Heroku reference: Basic web dyno up to $7/month; student credits up to $13/month while eligible.\n'
  printf 'Regular heartbeats keep a dyno awake. Basic does not sleep; Eco has 1000 shared hours/month.\n'
}
