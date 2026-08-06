#!/usr/bin/env bash
# hyn-view :: interactive setup
#
# Asks the questions instead of leaving an operator to reverse-engineer a config
# file. Design rules for the prompts:
#
#   * every question has a default that is safe to accept blindly
#   * inputs are validated at the prompt and re-asked, not accepted and then
#     silently ignored at 3am when an alert should have fired
#   * API keys are read with echo off and written only to the 0600 secrets file
#   * it ends by actually SENDING a test message, because a notification setup
#     you have not seen arrive is not configured, it is hoped for
#   * it is re-runnable; existing answers become the new defaults

W_TTY=0
[[ -t 0 && -t 1 ]] && W_TTY=1

_w_rule() { printf '%s\n' "────────────────────────────────────────────────────────────────"; }
_w_head() {
  printf '\n%s%s%s\n' "${C[accent]}${C[bold]}" "$1" "${C[reset]}"
  [[ -n ${2:-} ]] && printf '%s%s%s\n' "${C[dim]}" "$2" "${C[reset]}"
  printf '\n'
}
_w_note() { printf '  %s%s%s\n' "${C[dim]}" "$1" "${C[reset]}"; }
_w_ok() { printf '  %s%s %s%s\n' "${C[ok]}" "$G_DOT" "$1" "${C[reset]}"; }
_w_bad() { printf '  %s%s %s%s\n' "${C[crit]}" "$G_DOT" "$1" "${C[reset]}"; }

# ask <outvar> <prompt> <default> [validator-fn]
ask() {
  local __out=$1 prompt=$2 def=${3:-} val=${4:-} reply
  while :; do
    if [[ -n $def ]]; then
      printf '  %s %s[%s]%s ' "$prompt" "${C[dim]}" "$def" "${C[reset]}"
    else
      printf '  %s ' "$prompt"
    fi
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=$def
    if [[ -n $val ]] && ! "$val" "$reply"; then
      _w_bad "that does not look right, try again"
      continue
    fi
    printf -v "$__out" '%s' "$reply"
    return 0
  done
}

# Echo off. Shows only the length back, so a paste error is still visible.
ask_secret() {
  local __out=$1 prompt=$2 reply
  printf '  %s ' "$prompt"
  IFS= read -rs reply || return 1
  printf '\n'
  printf -v "$__out" '%s' "$reply"
  if [[ -n $reply ]]; then _w_note "received ${#reply} characters"; fi
  return 0
}

# ask_yn <prompt> <default y|n>
ask_yn() {
  local prompt=$1 def=${2:-y} reply hint='[Y/n]'
  [[ $def == n ]] && hint='[y/N]'
  while :; do
    printf '  %s %s%s%s ' "$prompt" "${C[dim]}" "$hint" "${C[reset]}"
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=$def
    case ${reply,,} in
      y | yes) return 0 ;;
      n | no) return 1 ;;
    esac
  done
}

# ask_choice <outvar> <prompt> <value:label> ...
ask_choice() {
  local __out=$1 prompt=$2
  shift 2
  local -a vals=() labels=()
  local spec i reply
  for spec in "$@"; do
    vals+=("${spec%%:*}")
    labels+=("${spec#*:}")
  done
  printf '  %s\n' "$prompt"
  for i in "${!vals[@]}"; do
    printf '    %s%s)%s %s\n' "${C[accent]}" "$((i + 1))" "${C[reset]}" "${labels[i]}"
  done
  while :; do
    printf '  choice %s[1]%s ' "${C[dim]}" "${C[reset]}"
    IFS= read -r reply || return 1
    [[ -z $reply ]] && reply=1
    if [[ $reply =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#vals[@]})); then
      printf -v "$__out" '%s' "${vals[reply - 1]}"
      return 0
    fi
    _w_bad "enter a number between 1 and ${#vals[@]}"
  done
}

_v_email() { valid_email "$1"; }
_v_emails() { valid_email_list "$1"; }
_v_int() { [[ $1 =~ ^[0-9]+$ ]]; }
_v_hhmm() { [[ $1 =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; }
_v_topic() { [[ $1 =~ ^[A-Za-z0-9_-]{8,}$ ]]; }
_v_url() { [[ $1 == https://* || $1 == http://* ]]; }
_v_host() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; }
_v_any() { return 0; }

# ---------------------------------------------------------------------------
# the wizard
# ---------------------------------------------------------------------------
wizard_run() {
  ((W_TTY)) || die 'the setup wizard needs an interactive terminal. Use `hyn config set <key> <value>` in scripts, or run `sudo hyn setup --no-wizard`.'
  is_root || warn 'not running as root: answers will be saved to your user config, and the systemd timers will be skipped.'

  secrets_load
  printf '\n'
  _w_rule
  printf '%s hyn-view setup%s  —  notifications, alerts and the daily report\n' "${C[bold]}" "${C[reset]}"
  _w_rule
  _w_note "Enter accepts the value in brackets. Ctrl-C aborts without saving."

  # ---------------------------------------------------------------- channel
  _w_head 'Where should alerts go?' \
    'Email suits daily reports. Push (ntfy/Telegram) is better for 3am alerts. You can pick both later.'
  local chan
  ask_choice chan 'Delivery method:' \
    'resend:Email via Resend            — free 100/day, API key, quickest to set up' \
    'brevo:Email via Brevo              — free 300/day, API key, needs a verified sender' \
    'smtp:Email via SMTP                — any provider, or a Gmail app password' \
    'ntfy:Push via ntfy.sh              — no account at all, instant to your phone' \
    'telegram:Telegram bot              — no account cost, instant, needs a bot token' \
    'webhook:Slack / Discord webhook    — posts into a channel' \
    'none:Nothing for now               — configure it later'

  if [[ $chan == none ]]; then
    _w_note 'skipping notifications. Re-run `sudo hyn setup` when you want them.'
    config_set notify_channels ''
  else
    _wiz_channel "$chan" || return 1
  fi

  # ---------------------------------------------------------------- visuals
  _w_head 'Look and feel' \
    'Two presets. You can switch live with the p key, so this is only the default.'
  local prof
  ask_choice prof 'Visual profile:' \
    'best:Best looking   — gradient braille graphs, time axis, 1s refresh (~5% of one core)' \
    'performance:Best performing — block graphs, 2s refresh (~3% of one core)'
  local k
  for k in graph graph_gradient graph_axis graph_stats interval proc_rows net_history_detail; do
    unset "CFG_EXPLICIT[$k]"
  done
  config_set profile "$prof"
  profile_apply
  _w_ok "profile $prof: graph=${CFG[graph]}, refresh ${CFG[interval]}s, ${CFG[proc_rows]} process rows"
  local th
  ask_choice th 'Theme:' \
    'hiway:hiway    — cool slate, cyan signal colour (default)' \
    'nord:nord     — low contrast, easy all day' \
    'gruvbox:gruvbox  — warm, high contrast, survives a laggy ssh' \
    'dracula:dracula  — vivid on near-black' \
    'solar:solar    — Solarized Dark' \
    'mono:mono     — greyscale, colour only for warnings'
  config_set theme "$th"

  # ---------------------------------------------------------------- alerts
  _w_head 'What should trigger an alert?' \
    'Defaults are tuned for a 24/7 relay node. Accept them unless you know you want different.'
  local sev
  ask_choice sev 'Notify me about:' \
    'warn:Warnings and critical  — recommended' \
    'crit:Critical only          — quieter, you will miss slow-building problems' \
    'info:Everything             — includes update notices, chatty'
  config_set alert_min_severity "$sev"

  if ask_yn 'Review the thresholds?' n; then
    local v
    ask v 'Memory used % that is a problem' "${CFG[alert_mem_pct]}" _v_int && config_set alert_mem_pct "$v"
    ask v 'Disk used % that is a problem' "${CFG[alert_disk_pct]}" _v_int && config_set alert_disk_pct "$v"
    ask v 'CPU steal % that is a problem' "${CFG[alert_steal_pct]}" _v_int && config_set alert_steal_pct "$v"
    ask v 'Internet latency ms that is a problem' "${CFG[alert_latency_ms]}" _v_int && config_set alert_latency_ms "$v"
    ask v 'Packet loss % that is a problem' "${CFG[alert_loss_pct]}" _v_int && config_set alert_loss_pct "$v"
    ask v 'Highway restarts before warning' "${CFG[alert_hw_restarts]}" _v_int && config_set alert_hw_restarts "$v"
    _w_note 'every other threshold is in `hyn config show` (keys starting alert_)'
  else
    _w_ok "using defaults: memory ${CFG[alert_mem_pct]}%, disk ${CFG[alert_disk_pct]}%, steal ${CFG[alert_steal_pct]}%, latency ${CFG[alert_latency_ms]}ms"
  fi

  local v
  ask v 'How often to check, in minutes' "${CFG[alert_interval_min]}" _v_int && config_set alert_interval_min "$v"
  ask v 'If a problem persists, remind me every N hours' "${CFG[alert_repeat_hours]}" _v_int && config_set alert_repeat_hours "$v"
  if ask_yn 'Also tell me when a problem clears?' y; then
    config_set alert_notify_resolved on
  else
    config_set alert_notify_resolved off
  fi
  ask v 'Never send more than N notifications per day' "${CFG[notify_max_per_day]}" _v_int && config_set notify_max_per_day "$v"

  # ---------------------------------------------------------------- report
  _w_head 'Daily report' \
    'One message a day: performance, throughput, storage trend, node status, and what fired.'
  if ask_yn 'Send a daily report?' y; then
    config_set report_enabled on
    ask v 'What time (24h HH:MM, server local time)' "${CFG[report_at]}" _v_hhmm && config_set report_at "$v"
    _w_ok "daily report at ${CFG[report_at]} — timezone is $(_wiz_tz)"
  else
    config_set report_enabled off
  fi

  # ---------------------------------------------------------------- speedtest
  _w_head 'Throughput tests' \
    'Measured against the same endpoint over time so the trend is meaningful. Skipped automatically when the link is already busy.'
  ask v 'Tests per day' "${CFG[speedtest_per_day]}" _v_int && config_set speedtest_per_day "$v"
  ask v 'Skip a test if the link is busier than N% of capacity' "${CFG[speedtest_guard_pct]}" _v_int && config_set speedtest_guard_pct "$v"

  # ---------------------------------------------------------------- heartbeat
  _w_head 'Detecting a dead server' \
    'This matters and is easy to get wrong. If the box is off, hyn is off too and cannot email you.'
  _w_note 'The fix is a dead man'"'"'s switch: this host checks in on a schedule, and an'
  _w_note 'outside service alerts YOU when the check-ins stop. healthchecks.io is free'
  _w_note 'and self-hostable; create a check and paste its ping URL here.'
  printf '\n'
  if ask_yn 'Set up a heartbeat URL now?' n; then
    local hb
    if ask hb 'Ping URL' "$(secret heartbeat_url)" _v_url; then
      secret_set heartbeat_url "$hb"
      if heartbeat_ping 0; then _w_ok 'heartbeat accepted'; else _w_bad 'could not reach that URL — saved anyway, check it later'; fi
    fi
  else
    _w_note 'without this, nothing will tell you the machine went offline.'
  fi

  # ---------------------------------------------------------------- updates
  _w_head 'Updates' 'hyn can watch npm for new releases.'
  _w_note 'Checking is free and never blocks: it caches for 12h and runs detached.'
  _w_note 'Installing automatically means this tool runs `npm i -g` as root,'
  _w_note 'unattended, on a production node. A bad release then lands on the box'
  _w_note 'by itself, so it is off unless you ask for it.'
  printf '\n'
  local au
  ask_choice au 'On launch:' \
    'check:Tell me when an update exists   — recommended' \
    'install:Install updates automatically   — unattended npm i -g as root' \
    'off:Do not check at all'
  config_set auto_update "$au"
  if [[ $au == install ]]; then
    _w_note 'noted. `hyn update --check` still works, and the version in use is'
    _w_note 'whatever was loaded at launch until you restart.'
  fi

  # ---------------------------------------------------------------- test
  if [[ $chan != none ]]; then
    _w_head 'Test' 'Sending one real message now.'
    if ask_yn 'Send a test notification?' y; then
      _wiz_test
    else
      _w_note 'run `hyn notify test` whenever you want to verify it.'
    fi
  fi

  printf '\n'
  _w_rule
  _w_ok "configuration written to $(config_file_rw)"
  [[ -r $HYN_ETC/secrets ]] && _w_ok "credentials written to $HYN_ETC/secrets (mode 0600)"
  _w_rule
  return 0
}

_wiz_tz() {
  local tz
  if have timedatectl; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null) && [[ -n $tz ]] && { printf '%s' "$tz"; return; }
  fi
  [[ -L /etc/localtime ]] && { tz=$(readlink /etc/localtime); printf '%s' "${tz#*zoneinfo/}"; return; }
  printf 'UTC'
}

_wiz_channel() {
  local chan=$1 v key
  case $chan in
    resend)
      _w_head 'Resend' 'Free plan: 100 emails/day, 3,000/month.'
      _w_note '1. sign up at https://resend.com and confirm your email'
      _w_note '2. open API Keys, create one with Sending access'
      _w_note '3. paste it below (it starts re_ and is not shown as you type)'
      printf '\n'
      ask_secret key 'API key:'
      [[ -n $key ]] || { _w_bad 'no key entered; skipping'; return 1; }
      valid_token "$key" || { _w_bad 'that key has unexpected characters in it'; return 1; }
      secret_set resend_api_key "$key"
      printf '\n'
      _w_note 'Without a verified domain, Resend only lets you send FROM onboarding@resend.dev'
      _w_note 'and only TO the email address on your Resend account. That is fine for'
      _w_note 'alerting yourself. Add a domain in Resend if you want another recipient.'
      printf '\n'
      ask v 'Send alerts to (your Resend account email)' "${CFG[notify_to]}" _v_emails
      config_set notify_to "$v"
      ask v 'Send from' "${CFG[notify_from]:-onboarding@resend.dev}" _v_email
      config_set notify_from "$v"
      config_set notify_channels resend
      ;;
    brevo)
      _w_head 'Brevo' 'Free plan: 300 emails/day.'
      _w_note '1. sign up at https://www.brevo.com'
      _w_note '2. SMTP & API -> API Keys -> generate a v3 key'
      _w_note '3. add and verify the sender address you want to send from'
      printf '\n'
      ask_secret key 'API key:'
      [[ -n $key ]] || { _w_bad 'no key entered; skipping'; return 1; }
      valid_token "$key" || { _w_bad 'that key has unexpected characters in it'; return 1; }
      secret_set brevo_api_key "$key"
      ask v 'Send alerts to' "${CFG[notify_to]}" _v_emails && config_set notify_to "$v"
      ask v 'Send from (must be verified in Brevo)' "${CFG[notify_from]}" _v_email && config_set notify_from "$v"
      config_set notify_channels brevo
      ;;
    smtp)
      _w_head 'SMTP' 'Works with any provider. For Gmail, use an App Password, not your login password.'
      ask v 'SMTP host' "${CFG[smtp_host]:-smtp.gmail.com}" _v_host && config_set smtp_host "$v"
      ask v 'Port (587 for STARTTLS, 465 for TLS)' "${CFG[smtp_port]:-587}" _v_int && config_set smtp_port "$v"
      ask v 'Username' "$(secret smtp_user)" _v_any && secret_set smtp_user "$v"
      ask_secret key 'Password or app password:'
      [[ -n $key ]] && secret_set smtp_pass "$key"
      ask v 'Send from' "${CFG[notify_from]:-$(secret smtp_user)}" _v_email && config_set notify_from "$v"
      ask v 'Send alerts to' "${CFG[notify_to]}" _v_emails && config_set notify_to "$v"
      config_set notify_channels smtp
      ;;
    ntfy)
      _w_head 'ntfy.sh' 'No account. Install the ntfy app, subscribe to a topic, done.'
      _w_note 'The topic name is the only thing protecting it, so make it long and random.'
      local suggested
      suggested="hyn-${HOSTNAME_S//[^A-Za-z0-9]/}-${RANDOM}${RANDOM}"
      printf '\n'
      ask v 'Topic' "${CFG[ntfy_topic]:-$suggested}" _v_topic && config_set ntfy_topic "$v"
      ask v 'Server' "${CFG[ntfy_server]:-https://ntfy.sh}" _v_url && config_set ntfy_server "$v"
      config_set notify_channels ntfy
      _w_ok "subscribe in the ntfy app to: ${CFG[ntfy_topic]}"
      ;;
    telegram)
      _w_head 'Telegram'
      _w_note '1. message @BotFather, send /newbot, follow the prompts'
      _w_note '2. it gives you a token like 123456:ABC-DEF...'
      _w_note '3. message your new bot once, then open'
      _w_note '   https://api.telegram.org/bot<TOKEN>/getUpdates to find your chat id'
      printf '\n'
      ask_secret key 'Bot token:'
      [[ -n $key ]] || { _w_bad 'no token entered; skipping'; return 1; }
      valid_token "$key" || { _w_bad 'that token has unexpected characters in it'; return 1; }
      secret_set telegram_token "$key"
      ask v 'Chat id' "${CFG[telegram_chat_id]}" _v_any && config_set telegram_chat_id "$v"
      config_set notify_channels telegram
      ;;
    webhook)
      _w_head 'Webhook' 'Slack or Discord incoming webhook URL.'
      ask_secret key 'Webhook URL:'
      [[ -n $key ]] || { _w_bad 'nothing entered; skipping'; return 1; }
      [[ $key == https://* ]] || { _w_bad 'must be an https URL'; return 1; }
      secret_set webhook_url "$key"
      config_set notify_channels webhook
      ;;
  esac

  # A second channel is genuinely useful: email for the report, push for alerts.
  printf '\n'
  if ask_yn 'Add a second channel as a backup?' n; then
    local extra
    ask_choice extra 'Second method:' \
      'ntfy:Push via ntfy.sh' \
      'telegram:Telegram bot' \
      'webhook:Slack / Discord webhook' \
      'smtp:Email via SMTP' \
      'skip:Never mind'
    if [[ $extra != skip && $extra != "$chan" ]]; then
      local primary=${CFG[notify_channels]}
      _wiz_channel "$extra"
      config_set notify_channels "$primary,${CFG[notify_channels]}"
      _w_ok "channels: ${CFG[notify_channels]}"
    fi
  fi
  return 0
}

_wiz_test() {
  local subject body
  subject="[hyn] Test from $HOSTNAME_S"
  body="This is the test message from hyn-view setup.

If you are reading it, alerts and the daily report will reach you here.

  host      $HOSTNAME_S
  distro    ${DISTRO:-unknown}
  kernel    ${KERNEL:-unknown}
  profile   ${CFG[profile]} (graph ${CFG[graph]}, ${CFG[interval]}s)
  channels  ${CFG[notify_channels]}
  alerts    every ${CFG[alert_interval_min]} min, severity ${CFG[alert_min_severity]} and above
  report    $( cfg_on report_enabled && printf 'daily at %s' "${CFG[report_at]}" || printf 'disabled' )

Nothing is wrong. You asked for a test.

--
hyn-view $HYN_VERSION -- $HYN_COPYRIGHT
$HYN_AUTHOR  <$HYN_AUTHOR_URL>"
  printf '\n'
  if notify_send info "$subject" "$body"; then
    _w_ok 'sent — check your inbox or phone now'
    _w_note 'if it does not arrive within a minute or two, check spam, then run: hyn notify test'
  else
    _w_bad "failed: ${NOTIFY_LAST_ERR:-unknown error}"
    _w_note 'the configuration was still saved. Fix the credential and run: hyn notify test'
    return 1
  fi
  return 0
}
