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
  # The replacements MUST stay quoted. Bash 5.2 changed ${var//pat/repl} so that
  # an unquoted & in the replacement means "the text that matched" (as in sed).
  # Written bare, ${s//</&lt;} therefore produces "<lt;" instead of "&lt;", which
  # silently broke HTML escaping on Ubuntu 24.04 (bash 5.2.21) and every newer
  # bash -- letting a crafted hostname, journal line, unit name or mount path
  # inject markup into an operator's alert email. Quoting suppresses the special
  # meaning and behaves identically all the way back to bash 3.2.
  s=${s//&/"&amp;"}
  s=${s//</"&lt;"}
  s=${s//>/"&gt;"}
  s=${s//\"/"&quot;"}
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


# ---------------------------------------------------------------------------
# HTML email components
# ---------------------------------------------------------------------------
# Shared by the alert digest and the daily report so they look like one product.
#
# Email HTML is not web HTML. Gmail strips <style> blocks, Outlook renders through
# Word, and flexbox/grid are unreliable everywhere. So: inline styles only,
# tables for structure, background-colour on table cells for bars, no external
# images, and web-safe font stacks. Everything degrades to readable plain text if
# a client strips it all.

# Palette. One place, so a severity colour means the same thing in every message.
E_INK='#0f172a' E_MUTED='#64748b' E_HAIR='#e2e8f0' E_PANEL='#f8fafc'
E_OK='#15803d' E_WARN='#b45309' E_CRIT='#b91c1c' E_ACCENT='#0e7490'
E_FONT='-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif'
E_MONO='ui-monospace,SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace'

# Colour for a percentage: green below 70, amber to 90, red above.
e_level() {
  local p=${1:-0}
  [[ $p =~ ^[0-9]+$ ]] || { printf '%s' "$E_MUTED"; return; }
  if ((p >= 90)); then printf '%s' "$E_CRIT"
  elif ((p >= 70)); then printf '%s' "$E_WARN"
  else printf '%s' "$E_OK"; fi
}

e_sevcolor() {
  case $1 in
    crit) printf '%s' "$E_CRIT" ;;
    warn) printf '%s' "$E_WARN" ;;
    ok) printf '%s' "$E_OK" ;;
    *) printf '%s' "$E_ACCENT" ;;
  esac
}

# Hidden preheader: the grey snippet an inbox shows next to the subject. Without
# one, clients scrape whatever text comes first, which looks careless.
e_preheader() {
  printf '<div style="display:none;font-size:1px;color:#ffffff;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden">%s</div>' \
    "$(html_escape "$1")"
}

e_open() {
  printf '<div style="background:#eef2f7;padding:24px 12px;font-family:%s">' "$E_FONT"
  printf '<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="width:100%%;max-width:680px;background:#ffffff;border:1px solid %s;border-radius:12px;overflow:hidden"><tr><td style="padding:0">' "$E_HAIR"
}

e_close() {
  printf '</td></tr></table></div>'
}

# Coloured header strip: hostname, subtitle, and the verdict as a badge.
e_header() {
  local title=$1 sub=$2 badge=$3 sev=$4
  local col
  col=$(e_sevcolor "$sev")
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr>'
  printf '<td style="background:%s;height:4px;line-height:4px;font-size:0">&nbsp;</td></tr></table>' "$col"
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr>'
  printf '<td style="padding:22px 26px 8px 26px">'
  printf '<div style="font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:%s;font-weight:600">%s</div>' \
    "$E_MUTED" "$(html_escape "$sub")"
  printf '<div style="font-size:24px;font-weight:700;color:%s;padding-top:3px">%s</div>' \
    "$E_INK" "$(html_escape "$title")"
  if [[ -n $badge ]]; then
    printf '<div style="margin-top:12px"><span style="display:inline-block;background:%s;color:#ffffff;font-size:13px;font-weight:600;padding:6px 12px;border-radius:999px">%s</span></div>' \
      "$col" "$(html_escape "$badge")"
  fi
  printf '</td></tr></table>'
}

e_section() {
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:22px 26px 0 26px">'
  printf '<div style="font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:%s;font-weight:700;border-bottom:1px solid %s;padding-bottom:7px;margin-bottom:12px">%s</div>' \
    "$E_MUTED" "$E_HAIR" "$(html_escape "$1")"
  printf '</td></tr></table>'
}

# A row of headline numbers. Big value, small label, optional sub-line. This is
# the part that makes the message scannable in two seconds.
e_kpi_open() {
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr>'
}
e_kpi() {
  local label=$1 value=$2 sub=$3 col=${4:-$E_INK}
  printf '<td style="width:25%%;padding:12px 10px;background:%s;border:1px solid %s;border-radius:8px;text-align:center" valign="top">' \
    "$E_PANEL" "$E_HAIR"
  printf '<div style="font-size:10px;letter-spacing:.09em;text-transform:uppercase;color:%s;font-weight:600">%s</div>' \
    "$E_MUTED" "$(html_escape "$label")"
  printf '<div style="font-size:21px;font-weight:700;color:%s;padding:4px 0 1px">%s</div>' \
    "$col" "$(html_escape "$value")"
  printf '<div style="font-size:11px;color:%s">%s</div>' "$E_MUTED" "$(html_escape "$sub")"
  printf '</td><td style="width:8px;font-size:0">&nbsp;</td>'
}
e_kpi_close() { printf '</tr></table></td></tr></table>'; }

# A labelled bar. Two table cells with background colours: the only bar that
# renders the same in Gmail, Outlook and Apple Mail.
e_bar() {
  local label=$1 pct=$2 right=$3
  local col p=$pct
  [[ $p =~ ^[0-9]+$ ]] || p=0
  ((p > 100)) && p=100
  col=$(e_level "$p")
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:9px"><tr>'
  printf '<td style="font-size:13px;color:%s;width:34%%;padding-right:10px" valign="middle">%s</td>' \
    "$E_INK" "$(html_escape "$label")"
  printf '<td valign="middle"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="background:%s;border-radius:4px"><tr>' "$E_HAIR"
  if ((p > 0)); then
    printf '<td style="width:%s%%;background:%s;height:8px;line-height:8px;font-size:0;border-radius:4px">&nbsp;</td>' "$p" "$col"
  fi
  if ((p < 100)); then
    printf '<td style="width:%s%%;height:8px;line-height:8px;font-size:0">&nbsp;</td>' $((100 - p))
  fi
  printf '</tr></table></td>'
  printf '<td style="font-size:13px;font-weight:600;color:%s;width:26%%;padding-left:10px;text-align:right;white-space:nowrap" valign="middle">%s</td>' \
    "$col" "$(html_escape "$right")"
  printf '</tr></table>'
}

# Label/value rows inside a section.
e_kv_open() {
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px"><table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px">'
}
e_kv() {
  local hl=${3:-}
  printf '<tr><td style="padding:4px 14px 4px 0;color:%s;white-space:nowrap;vertical-align:top;width:38%%">%s</td>' \
    "$E_MUTED" "$(html_escape "$1")"
  if [[ -n $hl ]]; then
    printf '<td style="padding:4px 0;color:%s;font-weight:600">%s</td></tr>' "$hl" "$(html_escape "$2")"
  else
    printf '<td style="padding:4px 0;color:%s">%s</td></tr>' "$E_INK" "$(html_escape "$2")"
  fi
}
e_kv_close() { printf '</table></td></tr></table>'; }

# Severity pill for an alert line.
e_pill() {
  local sev=$1 col
  col=$(e_sevcolor "$sev")
  printf '<span style="display:inline-block;background:%s;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;padding:2px 7px;border-radius:4px">%s</span>' \
    "$col" "$(html_escape "$sev")"
}

# Monospace block for raw output. Pre-wrap so long lines do not force a
# horizontal scrollbar on a phone.
e_pre() {
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 26px">'
  printf '<div style="background:%s;border:1px solid %s;border-radius:8px;padding:13px;font-family:%s;font-size:12px;line-height:1.55;color:%s;white-space:pre-wrap;word-break:break-word">%s</div>' \
    "$E_PANEL" "$E_HAIR" "$E_MONO" "$E_INK" "$(html_escape "$1")"
  printf '</td></tr></table>'
}

# A block-glyph sparkline in a monospace span. Renders in every client that has
# a monospace font, and degrades to nothing worse than odd characters.
e_spark() {
  local -n _ea=$1
  local label=$2 col=${3:-$E_ACCENT}
  local n=${#_ea[@]} i max=1 v out=''
  ((n == 0)) && return 0
  for v in "${_ea[@]}"; do [[ $v =~ ^[0-9]+$ ]] && ((v > max)) && max=$v; done
  local -a g=(' ' $'\u2581' $'\u2582' $'\u2583' $'\u2584' $'\u2585' $'\u2586' $'\u2587' $'\u2588')
  for ((i = 0; i < n; i++)); do
    v=${_ea[i]:-0}
    [[ $v =~ ^[0-9]+$ ]] || v=0
    local s=$((v * 8 / max))
    ((s > 8)) && s=8
    out+=${g[s]}
  done
  printf '<tr><td style="padding:4px 14px 4px 0;color:%s;white-space:nowrap;vertical-align:top;width:38%%">%s</td>' \
    "$E_MUTED" "$(html_escape "$label")"
  printf '<td style="padding:4px 0"><span style="font-family:%s;font-size:15px;letter-spacing:1px;color:%s">%s</span></td></tr>' \
    "$E_MONO" "$col" "$out"
  return 0
}

e_footer() {
  printf '<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:24px 26px 22px 26px">'
  printf '<div style="border-top:1px solid %s;padding-top:14px;font-size:11px;line-height:1.7;color:%s">' "$E_HAIR" "$E_MUTED"
  printf '<strong style="color:%s">hyn-view %s</strong> on %s<br>' "$E_INK" "$HYN_VERSION" "$(html_escape "$HOSTNAME_S")"
  printf '%s &middot; %s cores &middot; uptime %s<br>' \
    "$(html_escape "${DISTRO:-Linux}")" "$CPU_COUNT" "$(fmt_dur "$UPTIME_S")"
  printf '%s &middot; built by <a href="%s" style="color:%s;text-decoration:none"><strong>%s</strong></a>' \
    "$HYN_COPYRIGHT" "$HYN_AUTHOR_URL" "$E_ACCENT" "$(html_escape "$HYN_AUTHOR")"
  printf '</div></td></tr></table>'
}
