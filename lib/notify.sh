#!/usr/bin/env bash
# hyn-view :: notification delivery
#
# One job, and exactly one destination: take a subject, a body and a severity, and
# queue it with the web portal.
#
# There is no provider configuration on this machine. No API key, no SMTP host, no
# sender address, no recipient list, no ping URL. Those all used to be here -- six
# channels' worth -- and every one of them was in the wrong place: an API key on a
# relay node is a credential to rotate on N boxes, a recipient is a thing that
# changes when someone leaves, and neither can be inspected or corrected by the
# person actually looking at the dashboard. The portal owns the provider account,
# the recipients, the schedules, the templates and the delivery log.
#
# What is left on the box is the node token, in $HYN_ETC/secrets at mode 0600,
# never in the world-readable config. Two rules still apply to it and matter on
# any host with more than one login:
#
#   * it is never passed in argv. A token in `curl -H "Authorization: ..."` lands
#     in /proc/<pid>/cmdline where every local user can read it out of `ps`. It
#     goes in a request body written to a 0600 temp file instead (see cloud.sh).
#   * message bodies go the same way, so their contents are not in argv either.
#
# Anything interpolated into JSON goes through json_escape_v first. Journal lines
# and unit names are attacker-influenced text, and an unescaped quote in one of
# them would corrupt the request at best.

NOTIFY_LAST_ERR=''
# The HTTP status and response body of the last API call, kept so a failure can
# report what the provider actually said rather than just that it said no.
NOTIFY_LAST_CODE=0
NOTIFY_LAST_BODY=''

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
# the one channel
# ---------------------------------------------------------------------------
# Delivery is the portal's job, not this agent's.
#
# There used to be six local providers here -- Resend, Brevo, SMTP, Telegram, ntfy
# and a generic webhook -- each with its own credential in /etc/hyn-view/secrets,
# its own recipient and sender keys in the config, its own failure modes and its
# own wizard page. That put a provider account, an API key and a mailing decision
# on every monitored box, which is the wrong place for all three: the key is a
# credential to rotate on N servers, the recipient is a thing that changes when
# someone leaves, and none of it can be seen or fixed by the person watching the
# dashboard.
#
# So the agent now hands an event to the portal and stops caring. The portal owns
# the provider account, the recipients, the schedule, the templates and the
# delivery log, and it is the only place any of that is configured. What the CLI
# holds is the node token, which is what it needs to be allowed to speak at all.
# Each returns 0 on success and sets NOTIFY_LAST_ERR on failure. Arguments are
# always: <subject> <text-body> <html-body> <severity>


# Pull the human sentence out of a JSON error body without jq. Deliberately
# crude -- we want the message, not a parse tree.
API_MSG=''
_api_message_v() {
  local b=$1 k m=''
  for k in message error_description error detail Message; do
    [[ $b == *"\"$k\""* ]] || continue
    m=${b#*\"$k\"}
    m=${m#*:}
    while [[ $m == [[:space:]]* ]]; do m=${m#?}; done
    if [[ $m == \"* ]]; then
      m=${m#\"}
      m=${m%%\"*}
    else
      m=${m%%,*}
      m=${m%%\}*}
    fi
    [[ -n $m ]] && break
  done
  [[ -z $m ]] && m=${b:0:240}
  # Unescape the few sequences that actually show up in these messages.
  m=${m//\\n/ }
  m=${m//\\\"/\"}
  API_MSG=$m
  return 0
}


ch_web() {
  local subject=$1 text=$2 html=$3 sev=$4
  if ! declare -F cloud_web_notify >/dev/null 2>&1; then
    NOTIFY_LAST_ERR='web delivery needs the cloud module'
    return 1
  fi
  if cloud_web_notify "$subject" "$text" "$html" "$sev" "${NOTIFY_CATEGORY:-alert}"; then
    return 0
  fi
  NOTIFY_LAST_ERR=${CLOUD_LAST_ERR:-portal rejected the web notification}
  return 1
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
# notify_send <severity: crit|warn|info|ok> <subject> <text> [html]
# Fans out to every configured channel. One channel failing must not stop the
# others -- if email is down, the push notification is exactly what you want.

# What kind of message this is, for the portal's delivery log. Callers override
# it around a send; 'alert' is the common case so it is the default.
NOTIFY_CATEGORY=alert

notification_template_path() {
  local category=${1:-alert}
  state_dir_v
  printf '%s/email-template-%s.html' "$STATE_DIR" "$category"
}

# Apply the admin-managed presentation wrapper immediately before delivery.
# The generated incident/report markup is the trusted {{content}} insertion;
# scalar placeholders are escaped because hostnames and subjects can contain
# text that must never become active HTML.
notify_apply_template() {
  local category=$1 sev=$2 subject=$3 html=$4 path template
  path=$(notification_template_path "$category")
  [[ -r $path ]] || { HTML_OUT=$html; return 0; }
  template=$(<"$path")
  [[ $template == *'{{content}}'* ]] || { HTML_OUT=$html; return 0; }

  template=${template//"{{hostname}}"/"$(html_escape "${HOSTNAME_S:-unknown}")"}
  template=${template//"{{version}}"/"$(html_escape "${HYN_VERSION:-unknown}")"}
  template=${template//"{{severity}}"/"$(html_escape "$sev")"}
  template=${template//"{{subject}}"/"$(html_escape "$subject")"}
  template=${template//"{{content}}"/"$html"}
  HTML_OUT=$template
  return 0
}

# Is there anywhere to deliver to at all?
#
# Exactly one question now: is this machine paired with the portal. There is no
# local channel list to be empty, no provider to be half-configured, and no way
# for the two to disagree.
#
# Kept distinct from "delivery failed" because the difference decides whether a
# systemd unit goes red. Not being paired is a state, not a fault -- the report
# timer runs from the moment the package is installed, which is before pairing is
# possible, and must exit 0. A queue attempt that IS made and then fails is a real
# failure worth surfacing in `systemctl status`.
notify_configured() {
  declare -F cloud_configured >/dev/null 2>&1 || return 1
  cloud_configured && cloud_linked
}

# notify_send <severity> <subject> <text> [html]
#
# Queues one event with the portal and stops caring. The portal resolves the
# recipient from the node's owner, applies the account's template, sends through
# the deployment's provider account and records the outcome -- none of which this
# process can see, and none of which it needs to.
notify_send() {
  local sev=$1 subject=$2 text=$3 html=${4:-}

  if ! notify_configured; then
    NOTIFY_LAST_ERR='this machine is not paired with the portal (sudo hyn link)'
    return 1
  fi

  # A local backstop, still worth having: it is the portal's provider quota a
  # flapping rule would burn, and the cheapest place to stop that is before the
  # request goes out. The cap itself is set from the portal.
  if ! budget_check; then
    warn "daily notification cap (${CFG[notify_max_per_day]}) reached; suppressing: $subject"
    return 1
  fi

  [[ -z $html ]] && html="<pre style=\"font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace\">$(html_escape "$text")</pre>"
  # The wrapper comes from the portal too, pulled on the last check-in.
  notify_apply_template "${NOTIFY_CATEGORY:-alert}" "$sev" "$subject" "$html"
  html=$HTML_OUT

  NOTIFY_LAST_ERR=''
  if ch_web "$subject" "$text" "$html" "$sev"; then
    budget_consume
    return 0
  fi
  warn "notify: ${NOTIFY_LAST_ERR:-the portal rejected the event}"
  # Deliberately not recorded as a delivery attempt here. The portal writes the
  # notification log when its own worker has actually tried to send, so recording
  # an outcome now would make the dashboard claim a message was handled during a
  # provider failure.
  return 1
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
