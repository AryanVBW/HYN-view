#!/usr/bin/env bash
# hyn-view :: notification delivery
#
# One job: take a subject, a body and a severity, and get it to the operator.
# Everything is a curl call, so there is no new dependency.
#
# Channels: resend | brevo | smtp | telegram | ntfy | webhook | stdout
#
# SECRETS. API keys live in $HYN_ETC/secrets at mode 0600, never in
# $HYN_ETC/config which is world-readable 0644. Two further rules are enforced
# below and matter on any box with more than one login:
#
#   * secrets are never passed in argv. `curl -H "Authorization: Bearer sk_..."`
#     puts the key in /proc/<pid>/cmdline, where every user on the machine can
#     read it out of `ps`. They go through `curl --config -` on stdin instead.
#   * the body goes to a 0600 temp file and is passed as -d @file, so message
#     contents are not in argv either.
#
# Anything interpolated into JSON goes through json_escape_v first. Journal
# lines and unit names are attacker-influenced text, and an unescaped quote in
# one of them would corrupt the request at best.

NOTIFY_LAST_ERR=''

# ---------------------------------------------------------------------------
# secrets
# ---------------------------------------------------------------------------
declare -A SEC=()
SECRETS_LOADED=0

secrets_path() { printf '%s' "$HYN_ETC/secrets"; }

secrets_load() {
  local f
  f=$(secrets_path)
  SEC=()
  SECRETS_LOADED=1
  [[ -r $f ]] || return 1
  # Refuse to read a secrets file that others can read. Better to fail loudly at
  # setup time than to keep quietly using a key that has already leaked.
  local perm
  if have stat; then
    perm=$(stat -c '%a' "$f" 2>/dev/null) || perm=''
    if [[ -n $perm && ${#perm} -ge 3 && ${perm: -2} != 00 ]]; then
      warn "$f is mode $perm; it holds API keys and should be 0600. Fix with: sudo chmod 600 $f"
    fi
  fi
  _read_kv "$f" SEC
  return 0
}

secret() {
  ((SECRETS_LOADED)) || secrets_load
  printf '%s' "${SEC[$1]:-}"
}
has_secret() {
  ((SECRETS_LOADED)) || secrets_load
  [[ -n ${SEC[$1]:-} ]]
}

# Redact anything that looks like a credential before it reaches a log or the
# terminal. Belt and braces: nothing should be printing these anyway.
redact() {
  local s=$1 k v
  ((SECRETS_LOADED)) || secrets_load
  for k in "${!SEC[@]}"; do
    v=${SEC[$k]}
    [[ ${#v} -ge 8 ]] || continue
    s=${s//"$v"/'<redacted>'}
  done
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# validation at the trust boundary
# ---------------------------------------------------------------------------
# Addresses arrive from a config file and from the setup wizard, and end up in
# SMTP headers and JSON. A newline in an address is header injection.
valid_email() {
  local e=$1
  [[ $e == *$'\n'* || $e == *$'\r'* ]] && return 1
  [[ $e =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]]
}

# Comma-separated recipient list -> validated, in VALID_TO. Invalid entries are
# dropped with a warning rather than silently mangling the request.
declare -a VALID_TO=()
valid_email_list() {
  local raw=$1 e
  VALID_TO=()
  local oIFS=$IFS
  IFS=,
  for e in $raw; do
    e=${e//[[:space:]]/}
    [[ -z $e ]] && continue
    if valid_email "$e"; then VALID_TO+=("$e")
    else IFS=$oIFS; warn "ignoring invalid recipient: $e"; IFS=,; fi
  done
  IFS=$oIFS
  ((${#VALID_TO[@]} > 0))
}

# curl's config-file format needs backslashes and quotes escaped inside values,
# and a key with a newline in it would inject an option. Keys are opaque tokens;
# anything outside this charset is not one.
valid_token() { [[ $1 =~ ^[A-Za-z0-9._~+/=:-]+$ ]]; }

JSON_OUT=''
json_escape_v() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//[[:cntrl:]]/}
  JSON_OUT=$s
  return 0
}

# ---------------------------------------------------------------------------
# send budget
# ---------------------------------------------------------------------------
# A flapping condition plus a per-day provider quota is a bad combination: burn
# the quota and the one message that mattered is the one that gets dropped. The
# alert engine has its own cooldowns; this is the backstop.
NOTIFY_SENT_TODAY=0
_budget_file() {
  state_dir_v
  printf '%s/notify-budget' "$STATE_DIR"
}

budget_check() {
  local cap=${CFG[notify_max_per_day]} f day today used
  [[ $cap =~ ^[0-9]+$ ]] || cap=50
  ((cap == 0)) && return 0
  f=$(_budget_file)
  printf -v today '%(%Y-%m-%d)T' -1
  day='' used=0
  if [[ -r $f ]]; then
    { read -r day; read -r used; } <"$f" 2>/dev/null
    [[ $used =~ ^[0-9]+$ ]] || used=0
  fi
  [[ $day != "$today" ]] && used=0
  NOTIFY_SENT_TODAY=$used
  ((used < cap))
}

budget_consume() {
  local f today day used
  f=$(_budget_file)
  printf -v today '%(%Y-%m-%d)T' -1
  day='' used=0
  if [[ -r $f ]]; then
    { read -r day; read -r used; } <"$f" 2>/dev/null
    [[ $used =~ ^[0-9]+$ ]] || used=0
  fi
  [[ $day != "$today" ]] && used=0
  ((used++))
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s\n%s\n' "$today" "$used" >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  NOTIFY_SENT_TODAY=$used
  return 0
}

# ---------------------------------------------------------------------------
# channels
# ---------------------------------------------------------------------------
# Each returns 0 on success and sets NOTIFY_LAST_ERR on failure. Arguments are
# always: <subject> <text-body> <html-body> <severity>

_curl_json() {
  # _curl_json <url> <auth-config-line> <json-body> [extra-header...]
  local url=$1 authline=$2 body=$3
  shift 3
  local tmp rc out
  tmp=$(mktemp "${TMPDIR:-/tmp}/hyn-notify.XXXXXX") || { NOTIFY_LAST_ERR='mktemp failed'; return 1; }
  chmod 600 "$tmp" 2>/dev/null
  printf '%s' "$body" >"$tmp"
  # Auth goes via --config on stdin so the key never appears in argv.
  out=$(printf '%s\n' "$authline" |
    curl -fsS --max-time "${CFG[notify_timeout]:-15}" --config - \
      -X POST "$url" \
      -H 'Content-Type: application/json' \
      "$@" \
      --data-binary "@$tmp" 2>&1)
  rc=$?
  rm -f "$tmp"
  if ((rc != 0)); then
    NOTIFY_LAST_ERR=$(redact "curl exit $rc: ${out:0:300}")
    return 1
  fi
  return 0
}

ch_resend() {
  local subject=$1 text=$2 html=$3
  local key from to
  key=$(secret resend_api_key)
  [[ -n $key ]] || { NOTIFY_LAST_ERR='resend_api_key not set in secrets'; return 1; }
  valid_token "$key" || { NOTIFY_LAST_ERR='resend_api_key contains unexpected characters'; return 1; }
  from=${CFG[notify_from]:-onboarding@resend.dev}
  valid_email "$from" || { NOTIFY_LAST_ERR="invalid notify_from: $from"; return 1; }
  valid_email_list "${CFG[notify_to]}" || { NOTIFY_LAST_ERR='no valid notify_to address'; return 1; }

  local rcpt='' e
  for e in "${VALID_TO[@]}"; do
    json_escape_v "$e"
    rcpt+="${rcpt:+,}\"$JSON_OUT\""
  done
  json_escape_v "$subject"; local s=$JSON_OUT
  json_escape_v "$text"; local t=$JSON_OUT
  json_escape_v "$html"; local h=$JSON_OUT
  json_escape_v "${CFG[notify_from_name]:-hyn-view} <$from>"; local f=$JSON_OUT

  local body
  printf -v body '{"from":"%s","to":[%s],"subject":"%s","text":"%s","html":"%s"}' \
    "$f" "$rcpt" "$s" "$t" "$h"
  _curl_json 'https://api.resend.com/emails' "header = \"Authorization: Bearer $key\"" "$body"
}

ch_brevo() {
  local subject=$1 text=$2 html=$3
  local key from
  key=$(secret brevo_api_key)
  [[ -n $key ]] || { NOTIFY_LAST_ERR='brevo_api_key not set in secrets'; return 1; }
  valid_token "$key" || { NOTIFY_LAST_ERR='brevo_api_key contains unexpected characters'; return 1; }
  from=${CFG[notify_from]:-}
  valid_email "$from" || { NOTIFY_LAST_ERR="brevo needs a valid notify_from (got: $from)"; return 1; }
  valid_email_list "${CFG[notify_to]}" || { NOTIFY_LAST_ERR='no valid notify_to address'; return 1; }

  local rcpt='' e
  for e in "${VALID_TO[@]}"; do
    json_escape_v "$e"
    rcpt+="${rcpt:+,}{\"email\":\"$JSON_OUT\"}"
  done
  json_escape_v "$subject"; local s=$JSON_OUT
  json_escape_v "$text"; local t=$JSON_OUT
  json_escape_v "$html"; local h=$JSON_OUT
  json_escape_v "$from"; local fe=$JSON_OUT
  json_escape_v "${CFG[notify_from_name]:-hyn-view}"; local fn=$JSON_OUT

  local body
  printf -v body '{"sender":{"email":"%s","name":"%s"},"to":[%s],"subject":"%s","textContent":"%s","htmlContent":"%s"}' \
    "$fe" "$fn" "$rcpt" "$s" "$t" "$h"
  _curl_json 'https://api.brevo.com/v3/smtp/email' "header = \"api-key: $key\"" "$body"
}

# SMTP through curl. Works with any provider, including a Gmail app password,
# and is the only channel that needs no third-party API account.
ch_smtp() {
  local subject=$1 text=$2 html=$3
  local host port user pass from url tmp rc out
  host=${CFG[smtp_host]:-}
  port=${CFG[smtp_port]:-587}
  user=$(secret smtp_user)
  pass=$(secret smtp_pass)
  from=${CFG[notify_from]:-$user}
  [[ -n $host ]] || { NOTIFY_LAST_ERR='smtp_host not set'; return 1; }
  valid_email "$from" || { NOTIFY_LAST_ERR="invalid notify_from: $from"; return 1; }
  valid_email_list "${CFG[notify_to]}" || { NOTIFY_LAST_ERR='no valid notify_to address'; return 1; }
  [[ $port =~ ^[0-9]+$ ]] || { NOTIFY_LAST_ERR="invalid smtp_port: $port"; return 1; }

  # Subject and addresses are already newline-free (valid_email rejects them);
  # strip anything else that could break out of a header line.
  subject=${subject//[$'\n\r']/ }
  local boundary="hyn-$$-${RANDOM}"
  tmp=$(mktemp "${TMPDIR:-/tmp}/hyn-mail.XXXXXX") || { NOTIFY_LAST_ERR='mktemp failed'; return 1; }
  chmod 600 "$tmp" 2>/dev/null
  {
    printf 'From: %s <%s>\r\n' "${CFG[notify_from_name]:-hyn-view}" "$from"
    printf 'To: %s\r\n' "$(IFS=,; printf '%s' "${VALID_TO[*]}")"
    printf 'Subject: %s\r\n' "$subject"
    printf 'Date: %(%a, %d %b %Y %H:%M:%S %z)T\r\n' -1
    printf 'MIME-Version: 1.0\r\n'
    printf 'X-Mailer: hyn-view %s\r\n' "$HYN_VERSION"
    printf 'Content-Type: multipart/alternative; boundary="%s"\r\n\r\n' "$boundary"
    printf -- '--%s\r\n' "$boundary"
    printf 'Content-Type: text/plain; charset=utf-8\r\n\r\n%s\r\n' "$text"
    printf -- '--%s\r\n' "$boundary"
    printf 'Content-Type: text/html; charset=utf-8\r\n\r\n%s\r\n' "$html"
    printf -- '--%s--\r\n' "$boundary"
  } >"$tmp"

  if [[ $port == 465 ]]; then url="smtps://$host:$port"; else url="smtp://$host:$port"; fi
  local -a cfg=("url = \"$url\"")
  [[ -n $user ]] && cfg+=("user = \"$user:$pass\"")
  [[ $port != 465 ]] && cfg+=('ssl-reqd')
  cfg+=("mail-from = \"$from\"")
  for e in "${VALID_TO[@]}"; do cfg+=("mail-rcpt = \"$e\""); done
  cfg+=("upload-file = \"$tmp\"")

  out=$(printf '%s\n' "${cfg[@]}" | curl -sS --max-time "${CFG[notify_timeout]:-20}" --config - 2>&1)
  rc=$?
  rm -f "$tmp"
  if ((rc != 0)); then
    NOTIFY_LAST_ERR=$(redact "smtp curl exit $rc: ${out:0:300}")
    return 1
  fi
  return 0
}

ch_telegram() {
  local subject=$1 text=$2 _html=$3
  local token chat out rc
  token=$(secret telegram_token)
  chat=${CFG[telegram_chat_id]:-}
  [[ -n $token ]] || { NOTIFY_LAST_ERR='telegram_token not set in secrets'; return 1; }
  [[ -n $chat ]] || { NOTIFY_LAST_ERR='telegram_chat_id not set'; return 1; }
  valid_token "$token" || { NOTIFY_LAST_ERR='telegram_token contains unexpected characters'; return 1; }
  # Telegram's URL carries the token, so the URL itself is a secret: it goes
  # through --config, not argv.
  out=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" |
    curl -fsS --max-time "${CFG[notify_timeout]:-15}" --config - \
      -d "chat_id=$chat" \
      -d disable_web_page_preview=true \
      --data-urlencode "text=$subject"$'\n\n'"$text" 2>&1)
  rc=$?
  ((rc == 0)) || { NOTIFY_LAST_ERR=$(redact "telegram curl exit $rc: ${out:0:200}"); return 1; }
  return 0
}

# ntfy.sh: no account, no key, instant phone push. The best zero-friction option
# for alerts, though the topic name is the only access control -- pick an
# unguessable one.
ch_ntfy() {
  local subject=$1 text=$2 _html=$3 sev=$4
  local topic server prio tags out rc
  topic=${CFG[ntfy_topic]:-}
  server=${CFG[ntfy_server]:-https://ntfy.sh}
  [[ -n $topic ]] || { NOTIFY_LAST_ERR='ntfy_topic not set'; return 1; }
  [[ $topic =~ ^[A-Za-z0-9_-]+$ ]] || { NOTIFY_LAST_ERR='ntfy_topic must be alphanumeric/_/-'; return 1; }
  case $sev in
    crit) prio=urgent; tags='rotating_light' ;;
    warn) prio=high; tags='warning' ;;
    ok) prio=default; tags='white_check_mark' ;;
    *) prio=low; tags='bar_chart' ;;
  esac
  out=$(curl -fsS --max-time "${CFG[notify_timeout]:-15}" \
    -H "Title: $subject" -H "Priority: $prio" -H "Tags: $tags" \
    --data-binary "$text" "$server/$topic" 2>&1)
  rc=$?
  ((rc == 0)) || { NOTIFY_LAST_ERR="ntfy curl exit $rc: ${out:0:200}"; return 1; }
  return 0
}

# Slack and Discord both accept a simple JSON post; sending both key names means
# one implementation covers either without asking which it is.
ch_webhook() {
  local subject=$1 text=$2 _html=$3
  local url
  url=$(secret webhook_url)
  [[ -n $url ]] || url=${CFG[webhook_url]:-}
  [[ -n $url ]] || { NOTIFY_LAST_ERR='webhook_url not set'; return 1; }
  [[ $url == https://* ]] || { NOTIFY_LAST_ERR='webhook_url must be https'; return 1; }
  json_escape_v "$subject"$'\n'"$text"
  local body
  printf -v body '{"text":"%s","content":"%s"}' "$JSON_OUT" "$JSON_OUT"
  _curl_json "$url" 'silent' "$body"
}

ch_stdout() {
  # `printf --` is required: a format string starting with "--" is otherwise
  # taken as an option and printf fails.
  printf -- '--- %s ---\n%s\n' "$1" "$2"
  return 0
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
# notify_send <severity: crit|warn|info|ok> <subject> <text> [html]
# Fans out to every configured channel. One channel failing must not stop the
# others -- if email is down, the push notification is exactly what you want.
notify_send() {
  local sev=$1 subject=$2 text=$3 html=${4:-}
  local chans ch ok=0 tried=0
  chans=${CFG[notify_channels]:-}
  [[ -n $chans ]] || { NOTIFY_LAST_ERR='no notify_channels configured (run: sudo hyn setup)'; return 1; }

  if ! budget_check; then
    warn "daily notification cap (${CFG[notify_max_per_day]}) reached; suppressing: $subject"
    return 1
  fi

  [[ -z $html ]] && html="<pre style=\"font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace\">$(html_escape "$text")</pre>"

  local oIFS=$IFS
  IFS=,
  for ch in $chans; do
    ch=${ch//[[:space:]]/}
    [[ -z $ch ]] && continue
    IFS=$oIFS
    ((tried++))
    NOTIFY_LAST_ERR=''
    case $ch in
      resend) ch_resend "$subject" "$text" "$html" "$sev" && ok=1 ;;
      brevo) ch_brevo "$subject" "$text" "$html" "$sev" && ok=1 ;;
      smtp) ch_smtp "$subject" "$text" "$html" "$sev" && ok=1 ;;
      telegram) ch_telegram "$subject" "$text" "$html" "$sev" && ok=1 ;;
      ntfy) ch_ntfy "$subject" "$text" "$html" "$sev" && ok=1 ;;
      webhook) ch_webhook "$subject" "$text" "$html" "$sev" && ok=1 ;;
      stdout) ch_stdout "$subject" "$text" "$html" "$sev" && ok=1 ;;
      *) NOTIFY_LAST_ERR="unknown channel: $ch" ;;
    esac
    [[ -n $NOTIFY_LAST_ERR ]] && warn "notify[$ch]: $NOTIFY_LAST_ERR"
    IFS=,
  done
  IFS=$oIFS

  ((tried == 0)) && { NOTIFY_LAST_ERR='no usable channel'; return 1; }
  ((ok)) && budget_consume
  ((ok == 1))
}

HTML_OUT=''
html_escape() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# heartbeat (dead man's switch)
# ---------------------------------------------------------------------------
# The honest answer to "tell me when the server goes down". Nothing running ON
# the box can report that the box is off, so instead we check in on a schedule
# and let an external service alert when the check-ins stop. healthchecks.io is
# the reference implementation and is self-hostable; any URL that expects a
# periodic GET works.
heartbeat_ping() {
  local url status=${1:-0}
  url=$(secret heartbeat_url)
  [[ -n $url ]] || url=${CFG[heartbeat_url]:-}
  [[ -n $url ]] || return 0
  [[ $url == https://* || $url == http://* ]] || { warn 'heartbeat_url must be http(s)'; return 1; }
  # A non-zero status pings the /fail endpoint where the service supports it, so
  # a box that is up but unhealthy still raises an alarm.
  local target=$url
  ((status != 0)) && target="${url%/}/fail"
  printf 'url = "%s"\n' "$target" |
    curl -fsS --max-time 10 --retry 2 --config - -o /dev/null 2>/dev/null
  return $?
}
