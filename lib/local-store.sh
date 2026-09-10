#!/usr/bin/env bash
# Private, bounded local history. No request bodies or credentials in usage logs.

local_store_dir_v() {
  state_dir_v
  LOCAL_STORE="$STATE_DIR/local"
  (umask 077; mkdir -p "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage") || return 1
  chmod 700 "$LOCAL_STORE" "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" || return 1
}

local_store_prune() {
  local days=${CFG[local_keep_days]:-14} mb=${CFG[local_max_mb]:-256} kb file size
  [[ $days =~ ^[1-9][0-9]{0,2}$ ]] || days=14
  [[ $mb =~ ^[1-9][0-9]{0,4}$ ]] || mb=256
  # Only agent-owned history is rotated. Secrets, settings and existing report
  # files never enter this traversal. Keep at most days complete 24h periods.
  find "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" -type f -mtime +"$((days - 1))" -delete
  kb=$(du -sk "$LOCAL_STORE" 2>/dev/null); kb=${kb%%[[:space:]]*}
  [[ $kb =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r file; do
    ((kb <= mb * 1024)) && break
    size=$(du -k "$file" 2>/dev/null); size=${size%%[[:space:]]*}
    [[ $size =~ ^[0-9]+$ ]] || continue
    rm -f -- "$file" || return 1
    kb=$((kb - size))
  done < <(find "$LOCAL_STORE/snapshots" "$LOCAL_STORE/usage" -type f ! -name '.*' |
    while IFS= read -r path; do printf '%s\t%s\n' "${path##*/}" "$path"; done |
    LC_ALL=C sort | cut -f2-)
}

local_store_snapshot() {
  local_store_dir_v || return 1
  local tmp name date
  # mktemp + rename permits simultaneous record/push/update processes without
  # interleaved JSON or a shared .tmp file. Do not persist the token envelope.
  tmp=$(mktemp "$LOCAL_STORE/snapshots/.snapshot.XXXXXX") || return 1
  if ! printf '%s\n' "$CLOUD_PAYLOAD" >"$tmp"; then rm -f "$tmp"; return 1; fi
  printf -v date '%(%Y-%m-%d-%H%M%S)T' -1
  name="$LOCAL_STORE/snapshots/$date-${tmp##*.}.json"
  mv "$tmp" "$name" || return 1
  local_store_prune
}

local_store_report() {
  local_store_dir_v || return 1
  local tmp date
  tmp=$(mktemp "$LOCAL_STORE/snapshots/.report.XXXXXX") || return 1
  if ! printf '%s\n' "$1" >"$tmp"; then rm -f "$tmp"; return 1; fi
  printf -v date '%(%Y-%m-%d-%H%M%S)T' -1
  mv "$tmp" "$LOCAL_STORE/snapshots/$date-report-${tmp##*.}.txt" || return 1
  local_store_prune
}

local_usage_record() {
  local action=$1 code=$2 sent=$3 received=$4 rc=$5 day f last=0
  local_store_dir_v || return 1
  [[ $action =~ ^[a-z_]+$ && $code =~ ^[0-9]+$ && $sent =~ ^[0-9]+$ && $received =~ ^[0-9]+$ && $rc =~ ^[0-9]+$ ]] || return 1
  printf -v day '%(%Y-%m-%d)T' -1
  f="$LOCAL_STORE/usage/$day.tsv"
  # One short append per request; O_APPEND avoids shared counter update races.
  (umask 077; printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${EPOCHSECONDS:-0}" "$action" "$code" "$sent" "$received" "$rc" >>"$f")
  [[ -r $LOCAL_STORE/pruned ]] && read -r last <"$LOCAL_STORE/pruned"
  [[ $last =~ ^[0-9]+$ ]] || last=0
  if ((${EPOCHSECONDS:-0} - last >= 3600)); then
    local_store_prune || return 1
    (umask 077; printf '%s\n' "${EPOCHSECONDS:-0}" >"$LOCAL_STORE/pruned")
  fi
  return 0
}

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
  local nodes=${1:-1} beat=${CFG[heartbeat_sec]:-60} checkin=${CFG[cloud_checkin_min]:-5} monthly
  [[ $nodes =~ ^[1-9][0-9]{0,4}$ ]] || { warn 'usage: hyn cloud usage [1..99999 nodes]'; return 1; }
  [[ $beat =~ ^[1-9][0-9]{0,3}$ ]] && ((beat >= 5 && beat <= 3600)) || beat=60
  [[ $checkin =~ ^[1-9][0-9]{0,2}$ ]] && ((checkin <= 60)) || checkin=5
  monthly=$(((2592000 / beat + 2 * 43200 / checkin) * nodes))
  local_store_dir_v || return 1
  local ts action code sent received rc total=0 failed=0 tx=0 rx=0 f since
  since=$((${EPOCHSECONDS:-0} - 86400))
  for f in "$LOCAL_STORE"/usage/*.tsv; do
    [[ -r $f ]] || continue
    while IFS=$'\t' read -r ts action code sent received rc; do
      [[ $ts =~ ^[0-9]+$ && $sent =~ ^[0-9]+$ && $received =~ ^[0-9]+$ && $code =~ ^[0-9]+$ && $rc =~ ^[0-9]+$ ]] || continue
      ((ts >= since)) || continue
      total=$((total + 1)); tx=$((tx + sent)); rx=$((rx + received))
      ((rc != 0 || 10#$code < 200 || 10#$code >= 300)) && failed=$((failed + 1))
    done <"$f"
  done
  printf 'Storage mode: %s\nLocal history: %s\n' "${CFG[cloud_storage]:-local}" "$LOCAL_STORE"
  printf 'Last 24h: %s requests, %s failures, %s body bytes sent, %s body bytes received\n' "$total" "$failed" "$tx" "$rx"
  printf '30-day projection at this measured rate: %s requests, %s received bytes\n' "$((total * 30))" "$((rx * 30))"
  printf 'Configured baseline for %s node(s): about %s control POSTs per 30 days (excludes pairing, commands and retries)\n' "$nodes" "$monthly"
  printf 'Retention: %s days, at most %s MiB (oldest local history rotates first)\n' "${CFG[local_keep_days]:-14}" "${CFG[local_max_mb]:-256}"
  printf 'These are this CLI\x27s HTTP body totals, not Supabase egress or account billing.\n'
  printf 'Verify project database/egress in Supabase Usage and credits/dyno hours in Heroku Billing.\n'
  printf 'Supabase Free reference: 500 MB database, 5 GB uncached egress, 1 GB storage.\n'
  printf 'Heroku reference: Basic web dyno up to $7/month; student credits up to $13/month while eligible.\n'
  printf 'Regular heartbeats keep a dyno awake. Basic does not sleep; Eco has 1000 shared hours/month.\n'
}
