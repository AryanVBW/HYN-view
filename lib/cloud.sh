#!/usr/bin/env bash
# hyn-view :: cloud link (device pairing) and metric push
#
# This is how a headless box gets its telemetry into the web portal. The server
# has no browser, so pairing follows the same shape as `gh auth login`: the
# agent asks the backend for a short code, prints it, and polls; the human types
# that code into the portal from a phone or laptop that *does* have a browser.
#
# Trust model, which is the part worth reading:
#
#   * The agent holds only the PUBLIC anon key plus its own node token. It never
#     holds a service-role key. Everything privileged happens inside
#     SECURITY DEFINER SQL functions (see supabase/schema.sql), so a stolen
#     agent credential can write that one node's metrics and nothing else.
#
#   * The node token never appears in argv, because any local user can read
#     another process's command line out of /proc. It travels in a request body
#     written to a 0600 temp file, exactly like lib/notify.sh does with API keys.
#
#   * The anon key deliberately lives in the world-readable config, not in
#     secrets: it is published in every browser bundle that talks to Supabase,
#     so pretending it is a secret would be theatre. The node token is the real
#     credential and that goes in /etc/hyn-view/secrets at 0600.

# ---------------------------------------------------------------------------
# small JSON reader
# ---------------------------------------------------------------------------
# The RPCs all return a flat json_build_object, so a flat scalar extractor is
# sufficient and avoids adding a jq dependency to a zero-dependency tool.
# ponytail: flat keys only -- it does not descend into nested objects or arrays.
# If a future RPC returns a nested shape, this needs replacing rather than
# extending.
JSON_FIELD=''
json_field_v() {
  local body=$1 key=$2 m
  JSON_FIELD=''
  [[ $body == *"\"$key\""* ]] || return 1
  m=${body#*\"$key\"}
  m=${m#*:}
  while [[ $m == [[:space:]]* ]]; do m=${m#?}; done
  if [[ $m == \"* ]]; then
    m=${m#\"}
    # Stop at the first unescaped quote.
    local out='' c
    while [[ -n $m ]]; do
      c=${m:0:1}
      if [[ $c == '\' ]]; then
        out+=${m:0:2}
        m=${m:2}
        continue
      fi
      [[ $c == '"' ]] && break
      out+=$c
      m=${m:1}
    done
    # Undo the escapes we might plausibly receive.
    out=${out//\\n/$'\n'}
    out=${out//\\\"/\"}
    out=${out//\\\\/\\}
    JSON_FIELD=$out
  else
    m=${m%%,*}
    m=${m%%\}*}
    m=${m%"${m##*[![:space:]]}"}
    JSON_FIELD=$m
  fi
  return 0
}

# ---------------------------------------------------------------------------
# transport
# ---------------------------------------------------------------------------
CLOUD_LAST_CODE=0
CLOUD_LAST_BODY=''
CLOUD_LAST_ERR=''

cloud_url() {
  local u
  if [[ -n ${CFG[cloud_url]} && -n ${CFG[cloud_anon_key]} ]]; then
    u=${CFG[cloud_url]}
  else
    u=${CFG[cloud_api_url]:-}
  fi
  u=${u%/}
  printf '%s' "$u"
}

cloud_configured() {
  [[ -n ${CFG[cloud_api_url]:-} || ( -n ${CFG[cloud_url]} && -n ${CFG[cloud_anon_key]} ) ]]
}

cloud_linked() {
  [[ -n $(secret cloud_node_token) ]]
}

# _cloud_rpc <function-name> <json-body>
# POSTs to PostgREST's RPC endpoint. Body goes through a 0600 temp file so no
# token lands in argv; the anon key goes through curl --config on stdin for the
# same reason, even though it is a public value.
_cloud_rpc() {
  local fn=$1 body=$2 url key tmp out rc endpoint mode=hosted
  url=$(cloud_url)
  key=${CFG[cloud_anon_key]}
  CLOUD_LAST_ERR='' CLOUD_LAST_BODY='' CLOUD_LAST_CODE=0

  [[ -n $url ]] || { CLOUD_LAST_ERR='cloud API URL is not set'; return 1; }
  if [[ -n ${CFG[cloud_url]} && -n $key ]]; then
    mode=direct
    endpoint="$url/rest/v1/rpc/$fn"
  else
    endpoint="$url/$fn"
  fi
  # The node token travels in this request body. Over http it would cross every
  # hop in clear text, and a monitoring agent is exactly the kind of long-lived
  # unattended credential nobody notices leaking. Loopback is exempt because a
  # request that never leaves the machine cannot be intercepted on the wire --
  # that is also how the mock endpoint in test/cloud-integration.sh is reached.
  case $url in
    https://*) ;;
    http://127.0.0.1* | http://localhost* | 'http://[::1]'*) ;;
    *)
      CLOUD_LAST_ERR="cloud_url must be https (refusing to send the node token in clear text to ${url%%/*}//…)"
      return 1 ;;
  esac
  have curl || { CLOUD_LAST_ERR='curl is required for cloud sync'; return 1; }
  # A key with a quote or newline in it would inject a curl option. Hosted mode
  # has no per-customer key: the web API owns its database connection.
  if [[ $mode == direct ]]; then
    valid_token "$key" || { CLOUD_LAST_ERR='cloud_anon_key contains invalid characters'; return 1; }
  fi

  tmp=$(mktemp "${TMPDIR:-/tmp}/hyn-cloud.XXXXXX") || { CLOUD_LAST_ERR='mktemp failed'; return 1; }
  chmod 600 "$tmp" 2>/dev/null
  printf '%s' "$body" >"$tmp"

  # No -f: on a 4xx the body is where PostgREST explains itself, and throwing it
  # away turns "invalid node token" into a bare 400.
  if [[ $mode == direct ]]; then
    out=$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$key" "$key" |
      curl -sS --max-time "${CFG[cloud_timeout]:-20}" --config - \
        -X POST "$endpoint" \
        -H 'Content-Type: application/json' \
        -w $'\n%{http_code}' \
        --data-binary "@$tmp" 2>&1)
  else
    out=$(curl -sS --max-time "${CFG[cloud_timeout]:-20}" \
      -X POST "$endpoint" \
      -H 'Content-Type: application/json' \
      -H "User-Agent: hyn-view/$HYN_VERSION" \
      -w $'\n%{http_code}' \
      --data-binary "@$tmp" 2>&1)
  fi
  rc=$?
  rm -f "$tmp"

  local code=${out##*$'\n'}
  if [[ $code =~ ^[0-9]{3}$ ]]; then
    CLOUD_LAST_CODE=$code
    CLOUD_LAST_BODY=${out%$'\n'*}
  else
    CLOUD_LAST_CODE=0
    CLOUD_LAST_BODY=$out
  fi

  if ((rc != 0)); then
    CLOUD_LAST_ERR=$(redact "curl exit $rc: ${CLOUD_LAST_BODY:0:300}")
    return 1
  fi
  if ((CLOUD_LAST_CODE < 200 || CLOUD_LAST_CODE >= 300)); then
    _api_message_v "$CLOUD_LAST_BODY"
    CLOUD_LAST_ERR=$(redact "HTTP $CLOUD_LAST_CODE: $API_MSG")
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# payload
# ---------------------------------------------------------------------------
# Deliberately a separate serialiser from `hyn snapshot --json`: snapshot is a
# stable contract for humans and pipes, while this carries fields snapshot has
# no reason to (a timestamp, agent version, root-filesystem usage, and the
# currently firing alerts). Keeping them apart means changing the ingest shape
# cannot break someone's existing `hyn snapshot | jq` script.

# JSON number or null. Never emit an empty string where the schema wants a
# number -- an unreadable sensor must serialise as null, not as 0, or the
# dashboard would plot a fabricated reading.
_jnum() {
  local v=$1 d=${2:-null}
  [[ $v =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && printf '%s' "$v" || printf '%s' "$d"
}

_jstr() {
  json_escape_v "$1"
  printf '%s' "$JSON_OUT"
}

# Same as _jnum for values that come from systemd, which reports an unset
# MemoryCurrent as the 64-bit sentinel 18446744073709551615 (or literally
# "[not set]"). Bash arithmetic on that overflows to -1, so the test is on digit
# count rather than magnitude -- and a sentinel serialises as null, never as a
# machine that is somehow using 16 exbibytes of RAM.
_jbig() {
  local v=$1
  if [[ $v =~ ^[0-9]+$ ]] && ((${#v} <= 15)); then printf '%s' "$v"; else printf 'null'; fi
}

CLOUD_PAYLOAD=''
cloud_payload_v() {
  local iface=${NET_WAN:-none} ts
  printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  update_read >/dev/null 2>&1 || true

  # Root filesystem is the one mount worth promoting to a top-level number; the
  # rest ride along in the payload for the portal to grow into.
  local root_pct=${MP_PCT[/]:-}

  # A single latency figure for the headline chart: the best (lowest) of the
  # configured targets, which is the closest thing to "is the path healthy"
  # without picking a favourite resolver.
  local best_us='' k v
  for k in "${!LAT_MS[@]}"; do
    v=${LAT_MS[$k]}
    [[ $v =~ ^[0-9]+$ ]] || continue
    ((v == 0)) && continue
    [[ -z $best_us ]] && best_us=$v
    ((v < best_us)) && best_us=$v
  done
  local lat_ms='null'
  if [[ -n $best_us ]]; then
    printf -v lat_ms '%d.%02d' $((best_us / 1000)) $(((best_us % 1000) / 10))
  fi

  local p
  p='{'
  p+="\"ts\": \"$ts\""
  p+=", \"host\": \"$(_jstr "$HOSTNAME_S")\""
  p+=", \"agent_version\": \"$(_jstr "$HYN_VERSION")\""
  p+=", \"agent_update\": {\"latest\": \"$(_jstr "$UPD_LATEST")\""
  p+=", \"available\": $([[ $UPD_AVAILABLE == 1 ]] && printf true || printf false)"
  p+=", \"checked_at\": $(_jnum "$UPD_CHECKED")}"
  p+=", \"os\": \"$(_jstr "$DISTRO")\""
  p+=", \"kernel\": \"$(_jstr "$KERNEL")\""
  p+=", \"uptime_s\": $(_jnum "$UPTIME_S" 0)"
  p+=", \"load\": [$(_jnum "${LOAD1:-0}" 0), $(_jnum "${LOAD5:-0}" 0), $(_jnum "${LOAD15:-0}" 0)]"
  p+=", \"cpu\": {\"pct\": $(_jnum "$CPU_PCT" 0)"
  p+=", \"user\": $(_jnum "$CPU_USER" 0)"
  p+=", \"sys\": $(_jnum "$CPU_SYS" 0)"
  p+=", \"iowait\": $(_jnum "$CPU_IOWAIT" 0)"
  p+=", \"steal\": $(_jnum "$CPU_STEAL" 0)"
  p+=", \"cores\": $(_jnum "$CPU_COUNT" 0)"
  p+=", \"model\": \"$(_jstr "${CPU_MODEL:-}")\""
  p+=", \"mhz\": $(_jnum "$CPU_MHZ")"
  p+=", \"mhz_avg\": $(_jnum "${CPU_MHZ_AVG:-}")"
  p+=", \"mhz_min\": $(_jnum "${CPU_MHZ_MIN:-}")"
  p+=", \"mhz_max\": $(_jnum "${CPU_MHZ_MAX:-}")"
  p+=", \"governor\": \"$(_jstr "${CPU_GOVERNOR:-}")\""
  p+=', "cores_mhz": ['
  local ci cfirst=1
  for ci in "${CPU_CORE_MHZ[@]}"; do
    ((cfirst)) || p+=', '
    cfirst=0
    p+="$(_jnum "$ci" 0)"
  done
  p+=']'
  p+=", \"temp_c\": $(_jnum "$CPU_TEMP")}"
  p+=", \"memory\": {\"total\": $(_jnum "$MEM_TOTAL" 0)"
  p+=", \"used\": $(_jnum "$MEM_USED" 0)"
  p+=", \"pct\": $(_jnum "$MEM_PCT" 0)"
  p+=", \"swap_used\": $(_jnum "${SWAP_USED:-0}" 0)}"
  p+=", \"disk\": {\"pct\": $(_jnum "$root_pct"), \"mounts\": ["
  local first=1 mp
  for mp in "${MOUNTS[@]}"; do
    ((first)) || p+=', '
    first=0
    p+="{\"mount\": \"$(_jstr "$mp")\""
    p+=", \"pct\": $(_jnum "${MP_PCT[$mp]:-0}" 0)"
    p+=", \"used\": $(_jnum "${MP_USED[$mp]:-0}" 0)"
    p+=", \"size\": $(_jnum "${MP_SIZE[$mp]:-0}" 0)"
    p+=", \"avail\": $(_jnum "${MP_AVAIL[$mp]:-0}" 0)"
    p+=", \"fstype\": \"$(_jstr "${MP_FSTYPE[$mp]:-}")\"}"
  done
  p+=']}'
  p+=", \"network\": {\"iface\": \"$(_jstr "$iface")\""
  p+=", \"local_ip\": \"$(_jstr "${NET_LOCAL_IP:-}")\""
  p+=", \"ssid\": \"$(_jstr "${NET_SSID:-}")\""
  p+=", \"connection\": \"$(_jstr "${NET_CONN:-}")\""
  p+=", \"gateway\": \"$(_jstr "${NET_GW:-}")\""
  p+=", \"dns\": \"$(_jstr "${NET_DNS:-}")\""
  p+=", \"rx_bps\": $(_jnum "${NET_RXR[$iface]:-0}" 0)"
  p+=", \"tx_bps\": $(_jnum "${NET_TXR[$iface]:-0}" 0)"
  p+=", \"rx_total\": $(_jnum "${NET_RX[$iface]:-0}" 0)"
  p+=", \"tx_total\": $(_jnum "${NET_TX[$iface]:-0}" 0)"
  p+=", \"rx_err\": $(_jnum "${NET_RERR[$iface]:-0}" 0)"
  p+=", \"tx_err\": $(_jnum "${NET_TERR[$iface]:-0}" 0)"
  p+=", \"rx_drop\": $(_jnum "${NET_RDROP[$iface]:-0}" 0)"
  p+=", \"tx_drop\": $(_jnum "${NET_TDROP[$iface]:-0}" 0)"
  p+=", \"retrans_permille\": $(_jnum "${NET_RETRANS_PM:-0}" 0)"
  p+=", \"conntrack_pct\": $(_jnum "${CT_PCT:-0}" 0)"
  p+=", \"link_mbps\": $(_jnum "${LINK_SPEED:-}")"
  p+=", \"duplex\": \"$(_jstr "${LINK_DUPLEX:-}")\""
  p+=", \"mtu\": $(_jnum "${LINK_MTU:-}")"
  p+=", \"state\": \"$(_jstr "${LINK_STATE:-}")\""
  p+=", \"driver\": \"$(_jstr "${LINK_DRIVER:-}")\""
  p+=", \"tcp_estab\": $(_jnum "${TCPST[ESTAB]:-0}" 0)"
  p+=", \"tcp_timewait\": $(_jnum "${TCPST[TIME_WAIT]:-0}" 0)"
  p+=", \"listen_drops\": $(_jnum "${SNMPR[TcpExt.ListenDrops.raw]:-0}" 0)}"
  # Pressure stall information, as integer percent. PSI measures time actually
  # lost to contention, which load average cannot tell you.
  p+=", \"psi\": {\"cpu\": $(_jnum "${PSI[cpu.some]:-}")"
  p+=", \"memory\": $(_jnum "${PSI[memory.some]:-}")"
  p+=", \"io\": $(_jnum "${PSI[io.some]:-}")}"
  # Every temperature the platform exposes, not just the CPU package.
  p+=', "sensors": {'
  first=1
  for k in "${!SENSORS[@]}"; do
    ((first)) || p+=', '
    first=0
    p+="\"$(_jstr "$k")\": $(_jnum "${SENSORS[$k]}" 0)"
  done
  p+='}'
  # Top processes by the configured sort, so the portal can answer "what was
  # using the box at 3am" without a shell on it.
  p+=", \"processes\": {\"count\": $(_jnum "${PROC_TOTAL:-}")"
  p+=", \"running\": $(_jnum "${PROCS_RUN:-0}" 0)"
  p+=", \"blocked\": $(_jnum "${PROCS_BLK:-0}" 0)"
  p+=', "top": ['
  first=1
  local pi
  for ((pi = 0; pi < ${#P_PID[@]} && pi < 10; pi++)); do
    ((first)) || p+=', '
    first=0
    p+="{\"pid\": $(_jnum "${P_PID[pi]}" 0)"
    p+=", \"name\": \"$(_jstr "${P_NAME[pi]}")\""
    p+=", \"cpu_tenths\": $(_jnum "${P_CPU[pi]:-0}" 0)"
    p+=", \"rss\": $(_jnum "${P_RSS[pi]:-0}" 0)"
    p+=", \"threads\": $(_jnum "${P_THR[pi]:-0}" 0)}"
  done
  p+=']}'
  p+=", \"latency_ms\": $lat_ms"
  p+=', "latency_us": {'
  first=1
  for k in "${!LAT_MS[@]}"; do
    ((first)) || p+=', '
    first=0
    p+="\"$(_jstr "$k")\": $(_jnum "${LAT_MS[$k]}" 0)"
  done
  p+='}'
  p+=", \"speedtest\": {\"ts\": $(_jnum "${ST_LAST_TS:-0}" 0)"
  p+=", \"down_bps\": $(_jnum "${ST_LAST_DOWN:-0}" 0)"
  p+=", \"up_bps\": $(_jnum "${ST_LAST_UP:-0}" 0)"
  p+=", \"latency_us\": $(_jnum "${ST_LAST_LAT:-0}" 0)"
  p+=", \"note\": \"$(_jstr "${ST_LAST_NOTE:-}")\"}"
  # Highway node. Everything lib/highway.sh collects goes over the wire, because
  # the portal's node section is meant to be the terminal panel for someone who
  # is not at the terminal -- a summary verdict with no per-unit detail sends the
  # operator back to ssh, which is the thing the portal exists to avoid.
  #
  # The first six keys are the original shape and keep their names: an older
  # portal build reading `highway.present` must not break on an agent upgrade.
  p+=", \"highway\": {\"present\": $(_jnum "${HW_PRESENT:-0}" 0)"
  p+=", \"health\": \"$(_jstr "${HW_HEALTH:-}")\""
  p+=", \"version\": \"$(_jstr "${HW_VERSION:-}")\""
  p+=", \"units_active\": $(_jnum "${HW_ACTIVE:-0}" 0)"
  p+=", \"units_failed\": $(_jnum "${HW_FAILED:-0}" 0)"
  p+=", \"journal_err_1h\": $(_jnum "${HW_JOURNAL_ERR:-0}" 0)"
  p+=", \"tracked\": $(cfg_on highway_track && printf true || printf false)"
  p+=", \"health_why\": \"$(_jstr "${HW_HEALTH_WHY:-}")\""
  p+=", \"version_src\": \"$(_jstr "${HW_VERSION_SRC:-}")\""
  p+=", \"latest\": \"$(_jstr "${HW_LATEST:-}")\""
  p+=", \"update_available\": $(_jnum "${HW_UPDATE:-0}" 0)"
  p+=", \"bin_path\": \"$(_jstr "$HW_BIN")\""
  p+=", \"bin_size\": $(_jbig "${HW_SIZE:-}")"
  p+=", \"bin_mtime\": $(_jbig "${HW_MTIME:-}")"
  p+=", \"units_total\": $(_jnum "${HW_UNIT_COUNT:-0}" 0)"
  p+=", \"journal_warn_1h\": $(_jnum "${HW_JOURNAL_WARN:-0}" 0)"
  # pid 0 means "no process found", which is not a pid. Sent as null so the
  # portal shows "not running" rather than a process that cannot exist.
  p+=", \"pid\": $([[ ${HW_PID:-0} -gt 0 ]] && _jnum "$HW_PID" || printf null)"
  p+=", \"cpu_tenths\": $(_jnum "${HW_CPU:-}")"
  p+=", \"rss\": $(_jbig "${HW_RSS:-}")"
  p+=", \"threads\": $(_jnum "${HW_THR:-}")"
  # An unreadable /proc/<pid>/fd counts 0, and a running process always has at
  # least stdin, so 0 here means "could not read", not "no descriptors".
  p+=", \"fds\": $([[ ${HW_FDS:-0} -gt 0 ]] && _jnum "$HW_FDS" || printf null)"
  p+=", \"proc_uptime_s\": $(_jnum "${HW_UPTIME:-}")"
  p+=", \"mesh_iface\": \"$(_jstr "${HW_NEBULA:-}")\""
  if [[ -n ${HW_NEBULA:-} ]]; then
    p+=", \"mesh_rx_bps\": $(_jnum "${NET_RXR[$HW_NEBULA]:-0}" 0)"
    p+=", \"mesh_tx_bps\": $(_jnum "${NET_TXR[$HW_NEBULA]:-0}" 0)"
    p+=", \"mesh_rx_total\": $(_jbig "${NET_RX[$HW_NEBULA]:-}")"
    p+=", \"mesh_tx_total\": $(_jbig "${NET_TX[$HW_NEBULA]:-}")"
    p+=", \"mesh_drops\": $(_jnum $((${NET_RDROP_R[$HW_NEBULA]:-0} + ${NET_TDROP_R[$HW_NEBULA]:-0})) 0)"
  else
    p+=', "mesh_rx_bps": null, "mesh_tx_bps": null'
    p+=', "mesh_rx_total": null, "mesh_tx_total": null, "mesh_drops": null'
  fi
  p+=", \"qdisc\": \"$(_jstr "${HW_QDISC:-}")\""
  p+=", \"qdisc_drops\": $(_jnum "${HW_QDISC_DROPS:-}")"
  p+=", \"congestion\": \"$(_jstr "${TUNE[cc]:-}")\""
  p+=", \"nft_tables\": $(_jnum "${HW_NFT_TABLES:-}")"
  # The services themselves: one row per unit, in the order systemd listed them.
  p+=', "units": ['
  first=1
  local hu hs
  for hu in "${HW_UNITS[@]}"; do
    ((first)) || p+=', '
    first=0
    p+="{\"name\": \"$(_jstr "$hu")\""
    p+=", \"state\": \"$(_jstr "${HW_STATE[$hu]:-}")\""
    p+=", \"sub\": \"$(_jstr "${HW_SUB[$hu]:-}")\""
    p+=", \"restarts\": $(_jnum "${HW_RESTARTS[$hu]:-}")"
    p+=", \"memory\": $(_jbig "${HW_MEM[$hu]:-}")"
    # ExecMainStartTimestampMonotonic is microseconds since boot, which means
    # nothing off the box. Turned into "active for N seconds" against uptime,
    # which does travel.
    hs=${HW_SINCE[$hu]:-}
    if [[ $hs =~ ^[0-9]+$ ]] && ((${#hs} <= 15)) && ((hs > 0)) && ((${UPTIME_S:-0} > 0)); then
      p+=", \"active_s\": $((UPTIME_S - hs / 1000000))"
    else
      p+=', "active_s": null'
    fi
    p+='}'
  done
  p+=']'
  # Raw journal MESSAGE text is intentionally local-only. A service log can
  # contain peer-provided strings, tokens or customer identifiers; the portal
  # receives the warning/error counts above, which are sufficient for health
  # monitoring without copying arbitrary log content off the server.
  p+='}'

  # Currently firing alerts, so the portal's event log is the same truth the
  # email alerts are built from rather than a second, drifting judgement.
  p+=', "alerts": ['
  first=1
  local i
  for ((i = 0; i < ${#AL_ID[@]}; i++)); do
    ((first)) || p+=', '
    first=0
    p+="{\"rule\": \"$(_jstr "${AL_ID[i]}")\""
    p+=", \"severity\": \"$(_jstr "${AL_SEV[i]}")\""
    p+=", \"message\": \"$(_jstr "${AL_MSG[i]}")\""
    p+=", \"resolved\": $([[ ${AL_RESOLVED[i]:-0} == 1 ]] && printf true || printf false)}"
  done
  p+=']}'

  CLOUD_PAYLOAD=$p
  return 0
}

# ---------------------------------------------------------------------------
# push
# ---------------------------------------------------------------------------
_cloud_push_stamp() {
  state_dir_v
  printf '%s/cloud-last-push' "$STATE_DIR"
}

# The managed web channel sends only event content. Recipient, sender and
# provider credentials are resolved by the portal from the node owner.
cloud_web_notify() {
  local subject=${1:0:300} text=${2:0:10000} html=${3:0:20000}
  local severity=${4:-info} category=${5:-alert} token body checksum bucket material
  cloud_configured && cloud_linked || {
    CLOUD_LAST_ERR='the machine must be linked before using the web channel'
    return 1
  }
  case $severity in info | warn | crit) ;; *) severity=info ;; esac
  case $category in alert | report | test | other) ;; *) category=other ;; esac
  bucket=$((${EPOCHSECONDS:-0} / 600))
  material="$category|$severity|$subject|$text|$bucket"
  checksum=$(printf '%s' "$material" | cksum 2>/dev/null) || checksum='0'
  checksum=${checksum%% *}
  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\", \"p_event\": {"
  body+="\"fingerprint\": \"$(_jstr "$category:$severity:$bucket:$checksum")\""
  body+=", \"category\": \"$(_jstr "$category")\""
  body+=", \"severity\": \"$(_jstr "$severity")\""
  body+=", \"subject\": \"$(_jstr "$subject")\""
  body+=", \"text_body\": \"$(_jstr "$text")\""
  body+=", \"html_body\": \"$(_jstr "$html")\"}}"
  _cloud_rpc hyn_queue_web_notification "$body"
}

# Expensive collection is shared by scheduled pushes, first-link telemetry and
# one-off synchronization commands. Keeping one implementation prevents the
# dashboard sync button from returning a reduced snapshot.
cloud_collect_full() {
  alerts_collect
  alerts_evaluate
  net_link "${NET_WAN:-}" 2>/dev/null || true
  net_identity 1 2>/dev/null || true
  net_tuning 2>/dev/null || true
  local prows=${CFG[proc_rows]:-8} psort=${CFG[proc_sort]:-cpu}
  proc_sample 0 "$prows" "$psort" 2>/dev/null || true
  sleep 1
  proc_sample 1000 "$prows" "$psort" 2>/dev/null || true
  cloud_payload_v
}

cloud_ingest_collected() {
  local quiet=${1:-0} token body f
  CLOUD_INGESTED=0
  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\", \"p_payload\": $CLOUD_PAYLOAD}"
  f=$(_cloud_push_stamp)
  if _cloud_rpc hyn_ingest "$body"; then
    CLOUD_INGESTED=1
    printf '%s\tok\n' "${EPOCHSECONDS:-0}" >"$f" 2>/dev/null
    ((quiet)) || printf 'hyn: pushed to %s\n' "$(cloud_url)"
    cloud_notify_flush 1
    return 0
  fi
  case $CLOUD_LAST_ERR in
    *'node paused'*)
      printf '%s\tpaused\n' "${EPOCHSECONDS:-0}" >"$f" 2>/dev/null
      ((quiet)) || printf 'hyn: monitoring is paused for this node by an administrator\n'
      return 0 ;;
    *'node suspended'*)
      printf '%s\tsuspended\t%s\n' "${EPOCHSECONDS:-0}" "$CLOUD_LAST_ERR" >"$f" 2>/dev/null
      warn "this node is suspended: $CLOUD_LAST_ERR"
      return 1 ;;
  esac
  printf '%s\tfail\t%s\n' "${EPOCHSECONDS:-0}" "$CLOUD_LAST_ERR" >"$f" 2>/dev/null
  ((quiet)) || warn "push failed: $CLOUD_LAST_ERR"
  return 1
}

# ---------------------------------------------------------------------------
# portal-requested maintenance
# ---------------------------------------------------------------------------
CLOUD_COMMAND_CLAIMED=0
CLOUD_COMMAND_UPDATED=0
CLOUD_COMMAND_SYNCED=0
CLOUD_COMMAND_ID=''
CLOUD_COMMAND_TARGET=''
CLOUD_INGESTED=0

cloud_command_report() {
  local status=$1 stage=$2 message=$3 target=${4:-} result=${5:-}
  local token body
  [[ -n $CLOUD_COMMAND_ID ]] || return 1
  # Match the database contract even when curl/npm returns a very long error.
  # A progress report must never fail merely because its diagnostic text was
  # larger than the bounded command row can accept.
  message=${message:0:500}
  target=${target:0:64}
  result=${result:0:64}
  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\""
  body+=", \"p_command_id\": \"$(_jstr "$CLOUD_COMMAND_ID")\""
  body+=", \"p_status\": \"$(_jstr "$status")\""
  body+=", \"p_stage\": \"$(_jstr "$stage")\""
  body+=", \"p_message\": \"$(_jstr "$message")\""
  if [[ -n $target ]]; then body+=", \"p_target_version\": \"$(_jstr "$target")\""; else body+=', "p_target_version": null'; fi
  if [[ -n $result ]]; then body+=", \"p_result_version\": \"$(_jstr "$result")\""; else body+=', "p_result_version": null'; fi
  body+='}'
  _cloud_rpc hyn_report_node_command "$body"
}

cloud_update_progress() {
  local stage=$1 message=$2
  cloud_command_report running "$stage" "$message" "$CLOUD_COMMAND_TARGET" ''
}

# Claim at most one command per check-in. Update commands are idempotent: a
# lease-expired command may be reclaimed after a crash, and installing the same
# npm release twice still converges on the same package and systemd units.
cloud_command_poll() {
  local quiet=${1:-0} token body status action id
  CLOUD_COMMAND_CLAIMED=0
  CLOUD_COMMAND_UPDATED=0
  CLOUD_COMMAND_SYNCED=0
  CLOUD_COMMAND_ID=''
  CLOUD_COMMAND_TARGET=''

  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\"}"
  if ! _cloud_rpc hyn_claim_node_command "$body"; then
    ((quiet)) || warn "command check failed: $CLOUD_LAST_ERR"
    return 1
  fi
  json_field_v "$CLOUD_LAST_BODY" status && status=$JSON_FIELD
  [[ $status == command ]] || return 0
  json_field_v "$CLOUD_LAST_BODY" id && id=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" action && action=$JSON_FIELD
  if [[ ! $id =~ ^[0-9A-Fa-f-]{36}$ || ( $action != update && $action != sync ) ]]; then
    ((quiet)) || warn "portal returned an invalid maintenance command (id=${id:-missing}, action=${action:-missing})"
    return 1
  fi

  CLOUD_COMMAND_CLAIMED=1
  CLOUD_COMMAND_ID=$id
  if [[ $action == sync ]]; then
    cloud_command_report running collecting 'Collecting a complete system snapshot' '' '' || true
    cloud_collect_full
    cloud_command_report running uploading 'Uploading current telemetry to HYN-view' '' '' || true
    if ! cloud_ingest_collected 1 || ((CLOUD_INGESTED == 0)); then
      cloud_command_report failed failed \
        "${CLOUD_LAST_ERR:-synchronization could not upload; run sudo hyn doctor on the machine}" \
        '' '' || true
      return 1
    fi
    cloud_command_report running verifying 'Confirming the new reading reached the portal' '' '' || true
    cloud_command_report succeeded completed \
      'Synchronization completed and the portal accepted the current reading' '' "$HYN_VERSION" || true
    CLOUD_COMMAND_SYNCED=1
    return 0
  fi

  if ! cloud_command_report running checking 'Checking the npm registry for the newest hyn-view release' '' ''; then
    ((quiet)) || warn "could not report command progress: $CLOUD_LAST_ERR"
  fi
  if ! update_check_now; then
    local check_error=${UPD_LAST_ERR:-could not reach the npm registry}
    cloud_command_report failed failed "$check_error" '' "$HYN_VERSION" || true
    return 1
  fi

  CLOUD_COMMAND_TARGET=$UPD_LATEST
  # Force the install even when the package is already current. This makes the
  # portal button a repair path too: setup is reapplied and every enabled HYN
  # timer is restarted and verified after an interrupted earlier update.
  UPD_PROGRESS_HOOK=cloud_update_progress
  if update_apply 1; then
    UPD_PROGRESS_HOOK=''
    CLOUD_COMMAND_UPDATED=1
    # Do not declare the portal operation complete until a full snapshot using
    # the newly installed version has been accepted. Otherwise the modal and
    # completion email can say "updated" while every chart and the fleet
    # version still show the pre-update reading until the next interval.
    cloud_command_report running verifying \
      "Synchronizing fresh telemetry from hyn-view $HYN_VERSION" \
      "$CLOUD_COMMAND_TARGET" "$HYN_VERSION" || true
    cloud_collect_full
    if ! cloud_ingest_collected 1 || ((CLOUD_INGESTED == 0)); then
      cloud_command_report failed failed \
        "hyn-view $HYN_VERSION was installed and its services restarted, but fresh telemetry did not reach the portal: ${CLOUD_LAST_ERR:-upload failed; run sudo hyn doctor}" \
        "$CLOUD_COMMAND_TARGET" "$HYN_VERSION" || true
      return 1
    fi
    CLOUD_COMMAND_SYNCED=1
    cloud_command_report succeeded completed \
      "Updated to hyn-view $HYN_VERSION; managed services restarted, verified, and current telemetry synchronized" \
      "$CLOUD_COMMAND_TARGET" "$HYN_VERSION" || true
    return 0
  fi
  UPD_PROGRESS_HOOK=''
  cloud_command_report failed failed \
    "${UPD_LAST_ERR:-the package update failed; run sudo hyn doctor on the machine}" \
    "$CLOUD_COMMAND_TARGET" "$HYN_VERSION" || true
  return 1
}

cloud_push() {
  local quiet=${1:-0} respect_interval=${2:-0}
  CLOUD_COMMAND_SYNCED=0
  cloud_configured || {
    ((quiet)) || warn 'not configured for cloud sync; run: sudo hyn link'
    return 1
  }
  cloud_linked || {
    ((quiet)) || warn 'this node is not linked yet; run: sudo hyn link'
    return 1
  }

  # A check-in is also the node's opportunity to receive dashboard-managed
  # settings and email presentation. Reload CFG after a successful pull so the
  # new values affect this same cycle. Only the narrow portal allowlist wins;
  # endpoints, credentials, privacy choices and all other local settings remain
  # controlled by the root-owned files.
  if cloud_config_pull 1; then
    cfg_load
    # A portal command is explicit and therefore takes priority over the
    # detached automatic updater. With no command, a policy change to
    # auto_update still takes effect in this same check-in.
    cloud_command_poll 1 || true
    # Sync performs its own complete collection and ingest. Do not immediately
    # send a duplicate snapshot from the ordinary scheduled path.
    ((CLOUD_COMMAND_SYNCED)) && return 0
    ((CLOUD_COMMAND_CLAIMED)) || update_startup
  fi

  # The timer wakes every minute so a dashboard change is picked up quickly.
  # Expensive collection and ingestion still happen only at cloud_push_min.
  if ((respect_interval && CLOUD_COMMAND_UPDATED == 0)); then
    local prior_ts='' prior_status='' prior_error='' interval=${CFG[cloud_push_min]:-10}
    [[ $interval =~ ^[1-9][0-9]*$ ]] || interval=10
    local prior_stamp
    prior_stamp=$(_cloud_push_stamp)
    [[ -r $prior_stamp ]] && IFS=$'\t' read -r prior_ts prior_status prior_error <"$prior_stamp"
    if [[ $prior_ts =~ ^[0-9]+$ && $prior_status == ok ]] &&
       ((${EPOCHSECONDS:-0} - prior_ts < interval * 60)); then
      ((quiet)) || printf 'hyn: configuration checked; next reading is not due yet\n'
      return 0
    fi
  fi

  cloud_collect_full
  cloud_ingest_collected "$quiet"
}

# ---------------------------------------------------------------------------
# link
# ---------------------------------------------------------------------------
cloud_install_schedule() {
  # A linked monitor that only pushes once is a successful demo and a failed
  # installation. Finish the systemd integration while we already have root.
  # Non-systemd environments can still use `hyn push` from their own scheduler.
  have systemctl || return 0
  source "$HYN_LIB/setup.sh" || { warn 'could not load the systemd setup helpers'; return 1; }
  setup_run --no-wizard
}

cloud_link() {
  local a api='' url='' anon='' portal='' name=''
  while (($#)); do
    case $1 in
      --api) api=$2; shift 2 ;;
      --api=*) api=${1#*=}; shift ;;
      --url) url=$2; shift 2 ;;
      --url=*) url=${1#*=}; shift ;;
      --anon-key) anon=$2; shift 2 ;;
      --anon-key=*) anon=${1#*=}; shift ;;
      --portal) portal=$2; shift 2 ;;
      --portal=*) portal=${1#*=}; shift ;;
      --name) name=$2; shift 2 ;;
      --name=*) name=${1#*=}; shift ;;
      -h | --help)
        printf 'usage: sudo hyn link [--name <node-name>] [--api <hosted-api-url>]\n'
        printf '       sudo hyn link --url <supabase-url> --anon-key <key> [--portal <url>]\n'
        return 0 ;;
      *) warn "unknown option: $1"; return 1 ;;
    esac
  done

  is_root || die 'hyn link must run as root: it writes the node token to /etc/hyn-view/secrets (try: sudo hyn link)'

  [[ -n $api ]] && { config_set cloud_api_url "${api%/}" || return 1; }
  [[ -n $url ]] && { config_set cloud_url "${url%/}" || return 1; }
  [[ -n $anon ]] && { config_set cloud_anon_key "$anon" || return 1; }
  [[ -n $portal ]] && { config_set cloud_portal_url "${portal%/}" || return 1; }

  # Hosted pairing has product defaults and asks for no infrastructure values.
  # Prompt for the public key only when an operator explicitly selected the
  # backwards-compatible direct-Supabase mode with cloud_url/--url.
  if [[ -n ${CFG[cloud_url]} && -z ${CFG[cloud_anon_key]} ]]; then
    printf 'Supabase anon key (public; safe to paste): '
    read -r anon || return 1
    [[ -n $anon ]] || die 'an anon key is required'
    config_set cloud_anon_key "$anon" || return 1
  fi

  if cloud_linked; then
    printf 'hyn: this node is already linked (node %s).\n' "${CFG[cloud_node_id]:-unknown}"
    printf '     Run `sudo hyn unlink` first to pair it somewhere else.\n'
    return 1
  fi

  local body
  body="{\"p_hostname\": \"$(_jstr "$HOSTNAME_S")\", \"p_os\": \"$(_jstr "$DISTRO")\", \"p_agent_version\": \"$(_jstr "$HYN_VERSION")\"}"
  _cloud_rpc hyn_device_start "$body" || die "could not start pairing: $CLOUD_LAST_ERR"

  local user_code device_code interval
  json_field_v "$CLOUD_LAST_BODY" user_code && user_code=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" device_code && device_code=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" interval && interval=$JSON_FIELD
  [[ $interval =~ ^[0-9]+$ ]] || interval=5
  [[ -n $user_code && -n $device_code ]] || die 'pairing response was malformed'

  local link_url=${CFG[cloud_portal_url]}
  link_url=${link_url%/}
  [[ -n $link_url ]] && link_url="$link_url/link"

  printf '\n'
  printf '  Your one-time pairing code:  %s\n' "$user_code"
  printf '\n'
  if [[ -n $link_url ]]; then
    printf '  On a device with a browser, open:\n'
    printf '    %s\n' "$link_url"
  else
    printf '  On a device with a browser, open your portal and go to /link\n'
    printf '  (set cloud_portal_url in the config to print the full URL here).\n'
  fi
  printf '\n'
  printf '  Sign in, enter the code above, and approve this machine (%s).\n' "$HOSTNAME_S"
  printf '  The code expires in 15 minutes. Waiting'
  printf '\n\n'

  # Poll. The backend tells us the interval; we cap total wait at the code's
  # lifetime so an abandoned pairing exits instead of spinning forever.
  local waited=0 max=900 status='' dbody
  dbody="{\"p_device_code\": \"$(_jstr "$device_code")\"}"
  while ((waited < max)); do
    sleep "$interval"
    waited=$((waited + interval))
    if ! _cloud_rpc hyn_device_poll "$dbody"; then
      warn "poll failed: $CLOUD_LAST_ERR"
      continue
    fi
    json_field_v "$CLOUD_LAST_BODY" status && status=$JSON_FIELD
    case $status in
      pending)
        printf '\r  still waiting for approval (%ss)…   ' "$waited" ;;
      approved) break ;;
      expired) printf '\n'; die 'the pairing code expired before it was approved' ;;
      claimed) printf '\n'; die 'that pairing code was already used' ;;
      not_found) printf '\n'; die 'the backend does not recognise this pairing request' ;;
      *) printf '\n'; die "unexpected pairing status: ${status:-none}" ;;
    esac
  done
  printf '\n'
  [[ $status == approved ]] || die 'timed out waiting for approval'

  local node_id node_token node_name
  json_field_v "$CLOUD_LAST_BODY" node_id && node_id=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" node_token && node_token=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" node_name && node_name=$JSON_FIELD
  [[ -n $node_token && -n $node_id ]] || die 'approval response was missing the node token'

  secret_set cloud_node_token "$node_token" || die 'could not write the node token to secrets'
  config_set cloud_node_id "$node_id" || return 1
  config_set cloud_enabled on || return 1
  # The portal is the managed delivery plane. Fresh installs need no local
  # provider setup, while an operator's explicit smtp/resend/webhook choice is
  # never overwritten.
  if [[ -z ${CFG[notify_channels]:-} ]]; then
    config_set notify_channels web || return 1
  fi

  printf '\n'
  printf '  Linked. This node is "%s" (%s).\n' "${node_name:-$HOSTNAME_S}" "$node_id"
  printf '  Token stored in %s (mode 0600).\n' "$(secrets_path)"
  printf '\n'

  # Prove the credential and the full collection path now. The initial bounded
  # speed test is best-effort; a missing provider must not block core telemetry.
  printf '  Measuring the connection and sending the first full report… '
  if cloud_first_sync; then
    printf 'ok\n'
    printf '\n  Background monitoring is configured. Settings are checked every minute; full readings follow the Account interval.\n\n'
  else
    printf 'failed\n'
    warn "the node is linked but the first synchronization failed: $CLOUD_LAST_ERR"
    return 1
  fi
  return 0
}

# First-link orchestration is kept separate so the package can prove the order:
# bounded speed measurement, full telemetry, then recurring schedule.
cloud_first_sync() {
  st_run 0 >/dev/null 2>&1 || true
  cloud_push 1 || return 1
  cloud_install_schedule || {
    warn 'linked successfully, but the background schedule could not be installed; run: sudo hyn setup --no-wizard'
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# pull configuration from the portal
# ---------------------------------------------------------------------------
# The dashboard is the source of truth for settings, so the box does not need a
# hand-edited file to be correct. What stays local is only what is needed to
# reach the API at all: the project URL, the public anon key and the node token.
#
# Pulled settings land in a cache file that cfg_load applies after local files,
# but only for the narrow `_cfg_cloud_allowed` set. This makes Account the source
# of truth for managed thresholds and schedules without allowing the portal to
# touch endpoints, credentials, privacy choices or other local-only settings.
cloud_config_cache() {
  state_dir_v
  printf '%s/cloud-config' "$STATE_DIR"
}

# Legacy path used only to remove credential copies written by versions that
# accepted portal-managed notification channels. Provider credentials now live
# exclusively in /etc/hyn-view/secrets.
cloud_channels_cache() {
  state_dir_v
  printf '%s/cloud-channels' "$STATE_DIR"
}

cloud_template_write() {
  local category=$1 encoded=$2 path tmp
  path=$(notification_template_path "$category")
  tmp="$path.tmp.$$"
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1

  if [[ -z $encoded ]]; then
    rm -f -- "$path"
    return 0
  fi
  if printf '%s' "$encoded" | base64 -d >"$tmp" 2>/dev/null ||
     printf '%s' "$encoded" | base64 -D >"$tmp" 2>/dev/null; then
    if [[ $(wc -c <"$tmp" 2>/dev/null) -le 100000 ]] && grep -Fq '{{content}}' "$tmp"; then
      chmod 600 "$tmp" 2>/dev/null
      mv -f "$tmp" "$path"
      return 0
    fi
  fi
  rm -f -- "$tmp"
  return 1
}

CLOUD_NODE_STATUS=''
cloud_config_pull() {
  local quiet=${1:-0}
  cloud_configured || { ((quiet)) || warn 'not configured; run: sudo hyn link'; return 1; }
  cloud_linked || { ((quiet)) || warn 'not linked; run: sudo hyn link'; return 1; }

  local legacy_channels
  legacy_channels=$(cloud_channels_cache)
  if [[ -e $legacy_channels ]] && ! rm -f -- "$legacy_channels"; then
    ((quiet)) || warn "cannot remove legacy channel credential cache: $legacy_channels"
    return 1
  fi

  local token body
  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\"}"
  _cloud_rpc hyn_fetch_config "$body" || {
    ((quiet)) || warn "config pull failed: $CLOUD_LAST_ERR"
    return 1
  }

  local status reason
  json_field_v "$CLOUD_LAST_BODY" node_status && status=$JSON_FIELD
  json_field_v "$CLOUD_LAST_BODY" status_reason && reason=$JSON_FIELD
  CLOUD_NODE_STATUS=$status

  local encoded
  if json_field_v "$CLOUD_LAST_BODY" alert_template_b64; then
    encoded=$JSON_FIELD
    cloud_template_write alert "$encoded" || {
      ((quiet)) || warn 'portal returned an invalid alert email template; keeping the generated email'
    }
  fi
  if json_field_v "$CLOUD_LAST_BODY" report_template_b64; then
    encoded=$JSON_FIELD
    cloud_template_write report "$encoded" || {
      ((quiet)) || warn 'portal returned an invalid report email template; keeping the generated email'
    }
  fi

  # The config object is nested, and json_field_v is deliberately flat-only, so
  # slice the object out by brace matching rather than pretending to parse it.
  local cfgobj=''
  if [[ $CLOUD_LAST_BODY == *'"config"'* ]]; then
    local rest=${CLOUD_LAST_BODY#*\"config\"}
    rest=${rest#*:}
    while [[ $rest == [[:space:]]* ]]; do rest=${rest#?}; done
    if [[ $rest == \{* ]]; then
      local depth=0 i c
      for ((i = 0; i < ${#rest}; i++)); do
        c=${rest:i:1}
        [[ $c == '{' ]] && depth=$((depth + 1))
        [[ $c == '}' ]] && depth=$((depth - 1))
        cfgobj+=$c
        ((depth == 0)) && break
      done
    fi
  fi

  # Flatten "key": value pairs into the key=value form cfg_load already parses,
  # so no new config format enters the codebase.
  local -a lines=()
  if [[ -n $cfgobj && $cfgobj != '{}' ]]; then
    local inner=${cfgobj#\{}
    inner=${inner%\}}
    local IFS=,
    local pair k v
    for pair in $inner; do
      k=${pair%%:*}
      v=${pair#*:}
      k=${k//\"/}
      k=${k// /}
      v=${v#"${v%%[![:space:]]*}"}
      v=${v%"${v##*[![:space:]]}"}
      v=${v//\"/}
      [[ -n $k ]] || continue
      # Only settings exposed by the portal's NodeSettings form cross this
      # boundary. `_cfg_allowed` is deliberately not enough: it includes local
      # destinations, endpoints and credentials that a direct API caller must
      # never be able to deliver to a node.
      if _cfg_cloud_allowed "$k" && _cfg_cloud_value_allowed "$k" "$v"; then
        lines+=("$k=$v")
      else
        ((quiet)) || warn "portal sent a local-only, unknown or unsafe setting, ignoring: $k"
      fi
    done
    unset IFS
  fi

  local f tmp
  f=$(cloud_config_cache)
  tmp="$f.tmp"
  {
    printf '# Written by `hyn config pull`. Do not edit: it is overwritten.\n'
    printf '# Edit these settings in the web portal instead.\n'
    ((${#lines[@]})) && printf '%s\n' "${lines[@]}"
  } >"$tmp" && mv -f "$tmp" "$f" || { warn "cannot write $f"; return 1; }

  if ((quiet == 0)); then
    printf 'hyn: pulled %d setting(s) from the portal\n' "${#lines[@]}"
    [[ -n $status && $status != active ]] &&
      printf 'hyn: this node is %s%s\n' "$status" "${reason:+ ($reason)}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# report notification deliveries
# ---------------------------------------------------------------------------
# The portal shows how many alerts went out and which failed, which it can only
# know if the box tells it. Appended locally by the notify layer, drained here.
cloud_notify_queue() {
  state_dir_v
  printf '%s/cloud-notify-queue' "$STATE_DIR"
}

# cloud_notify_record <kind> <target> <severity> <subject> <status> <error> <category>
# Appends one delivery attempt as a JSON object, one per line. Called from the
# notify path, so it must never fail loudly enough to break sending an alert.
cloud_notify_record() {
  cloud_linked || return 0
  local q ts
  q=$(cloud_notify_queue)
  printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  {
    printf '{"ts": "%s"' "$ts"
    printf ', "kind": "%s"' "$(_jstr "${1:-unknown}")"
    printf ', "target": "%s"' "$(_jstr "${2:-}")"
    printf ', "severity": "%s"' "$(_jstr "${3:-info}")"
    printf ', "subject": "%s"' "$(_jstr "${4:-}")"
    printf ', "status": "%s"' "$(_jstr "${5:-failed}")"
    printf ', "error": "%s"' "$(_jstr "${6:-}")"
    printf ', "category": "%s"}\n' "$(_jstr "${7:-other}")"
  } >>"$q" 2>/dev/null || true
  return 0
}

cloud_notify_flush() {
  local quiet=${1:-0} q
  q=$(cloud_notify_queue)
  [[ -s $q ]] || return 0
  cloud_configured && cloud_linked || return 1

  # Rotate first: if the POST fails we put the file back, but a delivery that
  # arrives twice is better than one that vanishes because a new alert was
  # appended mid-flight.
  local work="$q.sending"
  mv -f "$q" "$work" 2>/dev/null || return 1

  local events='' line first=1
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    ((first)) || events+=', '
    first=0
    events+=$line
  done <"$work"

  [[ -n $events ]] || { rm -f "$work"; return 0; }

  local token body
  token=$(secret cloud_node_token)
  body="{\"p_node_token\": \"$(_jstr "$token")\", \"p_events\": [$events]}"
  if _cloud_rpc hyn_report_notification "$body"; then
    rm -f "$work"
    ((quiet)) || printf 'hyn: reported notification deliveries\n'
    return 0
  fi
  # Put them back at the front of the queue for the next run.
  if [[ -s $q ]]; then
    cat "$q" >>"$work" 2>/dev/null
  fi
  mv -f "$work" "$q" 2>/dev/null
  ((quiet)) || warn "could not report deliveries: $CLOUD_LAST_ERR"
  return 1
}

cloud_unlink() {
  is_root || die 'hyn unlink must run as root (try: sudo hyn unlink)'
  cloud_linked || { printf 'hyn: this node is not linked.\n'; return 0; }
  # Clearing the local token is all the agent can do. It cannot revoke itself
  # server-side, because a compromised agent revoking its own node would be a
  # denial-of-service primitive; revoke from the portal for that.
  secret_set cloud_node_token '' || return 1
  config_set cloud_enabled off || return 1
  printf 'hyn: unlinked locally. The node still exists in the portal — remove or revoke it there to be sure.\n'
  return 0
}

cloud_status() {
  local url token stamp ts st err
  url=$(cloud_url)
  token=$(secret cloud_node_token)
  printf 'cloud    %s\n' "$(cfg_on cloud_enabled && printf enabled || printf disabled)"
  printf 'url      %s\n' "${url:-(not set)}"
  printf 'anon key %s\n' "$([[ -n ${CFG[cloud_anon_key]} ]] && printf 'set' || printf '(not set)')"
  printf 'portal   %s\n' "${CFG[cloud_portal_url]:-(not set)}"
  printf 'node id  %s\n' "${CFG[cloud_node_id]:-(not linked)}"
  printf 'token    %s\n' "$([[ -n $token ]] && printf 'present (0600)' || printf '(not linked)')"
  stamp=$(_cloud_push_stamp)
  if [[ -r $stamp ]]; then
    IFS=$'\t' read -r ts st err <"$stamp"
    case $st in
      ok) printf 'last push %s ago\n' "$(fmt_dur $((${EPOCHSECONDS:-0} - ts)))" ;;
      paused)
        printf 'last push %s ago — monitoring is paused by an administrator\n' \
          "$(fmt_dur $((${EPOCHSECONDS:-0} - ts)))" ;;
      suspended)
        printf 'last push %s ago — this node is suspended: %s\n' \
          "$(fmt_dur $((${EPOCHSECONDS:-0} - ts)))" "$err" ;;
      *) printf 'last push failed %s ago: %s\n' "$(fmt_dur $((${EPOCHSECONDS:-0} - ts)))" "$err" ;;
    esac
  else
    printf 'last push never\n'
  fi
  local cc
  cc=$(cloud_config_cache)
  if [[ -r $cc ]]; then
    local n
    n=$(grep -cv '^[[:space:]]*\(#\|$\)' "$cc" 2>/dev/null) || n=0
    printf 'config   %s setting(s) pulled from the portal\n' "$n"
  else
    printf 'config   none pulled yet (run: hyn config pull)\n'
  fi
  local q
  q=$(cloud_notify_queue)
  if [[ -s $q ]]; then
    printf 'queued   %s notification(s) waiting to be reported\n' "$(wc -l <"$q" | tr -d ' ')"
  fi
  return 0
}
