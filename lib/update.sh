#!/usr/bin/env bash
# hyn-view :: self update
#
# Checks the npm registry for a newer release and, if asked to, installs it.
#
# The check hits the registry directly with curl rather than shelling out to
# `npm view`: it is one HTTPS GET against a static JSON document, so it needs no
# npm on PATH and takes milliseconds instead of a second or two of npm start-up.
# npm is only required for the actual install.
#
# Three deliberate design points:
#
#   * The check NEVER blocks a frame. It runs detached, writes a cache file, and
#     the UI reads the cache. A registry outage must not delay startup of a
#     monitoring tool.
#   * The result is cached for update_check_hours, so launching `hyn` in a loop
#     does not hammer the registry.
#   * Hosted installs default to managed updates so the CLI and portal contract
#     cannot drift. Operators can still choose `check` or `off` in Account or in
#     the root-owned local config.

UPD_LATEST='' UPD_AVAILABLE=0 UPD_CHECKED=0 UPD_STATE='' UPD_LAST_ERR=''
UPD_REGISTRY='https://registry.npmjs.org'

# The registry must be reached over TLS: this document decides which package
# version a root process is about to install, so a plaintext answer is an
# invitation to install someone else's build. Loopback is the one exception, for
# the same reason lib/cloud.sh makes it -- a request that never leaves the machine
# cannot be intercepted on the wire, and it is how test/update-workflow.sh drives
# the real checker against a mock registry.
_upd_proto() {
  case $UPD_REGISTRY in
    http://127.0.0.1* | http://localhost* | 'http://[::1]'*) printf '=http' ;;
    *) printf '=https' ;;
  esac
}
UPD_PROGRESS_HOOK=''

# A portal-triggered update installs through the same path as an unattended
# update. The optional hook lets the cloud command report each durable stage;
# local/manual updates simply print their normal terminal output.
update_emit_progress() {
  local stage=$1 message=$2
  if [[ -n $UPD_PROGRESS_HOOK ]] && declare -F "$UPD_PROGRESS_HOOK" >/dev/null 2>&1; then
    "$UPD_PROGRESS_HOOK" "$stage" "$message" || true
  fi
}

# dist-tags.latest out of the abbreviated registry document, into UPD_PARSED.
#
# Taking a JSON parser dependency for one field would be absurd for a tool whose
# selling point is having none, but the hand-rolled version has to be more careful
# than it first looks. The obvious `${body#*\"latest\":\"}` assumes the registry
# emits no space after the colon. That is true of npm today and is not a promise
# anyone made: the day it serialises `"latest": "1.9.0"` instead, every installed
# agent stops seeing releases, for ever, and the fix cannot be delivered because
# delivering it needs the thing that broke. So whitespace is skipped explicitly.
UPD_PARSED=''
_upd_parse_latest() {
  local body=$1 m
  UPD_PARSED=''
  [[ $body == *'"latest"'* ]] || return 1
  m=${body#*\"latest\"}
  while [[ $m == [[:space:]]* ]]; do m=${m#?}; done
  [[ $m == :* ]] || return 1
  m=${m#:}
  while [[ $m == [[:space:]]* ]]; do m=${m#?}; done
  [[ $m == \"* ]] || return 1
  m=${m#\"}
  m=${m%%\"*}
  [[ $m =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || { UPD_PARSED=$m; return 1; }
  UPD_PARSED=$m
  return 0
}

update_cache_file() {
  state_dir_v
  printf '%s/update-check' "$STATE_DIR"
}

# Reads the cache into UPD_LATEST / UPD_AVAILABLE. Cheap, no network.
update_read() {
  local f ts v
  f=$(update_cache_file)
  UPD_LATEST='' UPD_AVAILABLE=0 UPD_CHECKED=0
  [[ -r $f ]] || return 1
  { read -r ts; read -r v; } <"$f" 2>/dev/null
  [[ $ts =~ ^[0-9]+$ ]] || return 1
  UPD_CHECKED=$ts
  UPD_LATEST=$v
  [[ -n $v ]] || return 1
  ver_gt "$v" "$HYN_VERSION" && UPD_AVAILABLE=1
  return 0
}

# Spawns the check if the cache is stale. Returns immediately either way.
_UPD_PID=0
update_check_async() {
  [[ ${CFG[auto_update]} == off ]] && return 0
  have curl || return 0
  local f now hours
  f=$(update_cache_file)
  now=${EPOCHSECONDS:-0}
  hours=${CFG[update_check_hours]:-12}
  [[ $hours =~ ^[0-9]+$ ]] || hours=12
  update_read
  ((UPD_CHECKED > 0 && now - UPD_CHECKED < hours * 3600)) && return 0
  # Never two at once, and never a fresh attempt on every launch when the
  # registry is unreachable: the timestamp is written before the fetch.
  if ((_UPD_PID > 0)) && kill -0 "$_UPD_PID" 2>/dev/null; then return 0; fi
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  printf '%s\n%s\n' "$now" "$UPD_LATEST" >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  {
    local body ver
    body=$(curl -fsSL --max-time 8 --proto "$(_upd_proto)" \
      -H 'Accept: application/vnd.npm.install-v1+json' \
      "$UPD_REGISTRY/$HYN_PKG" 2>/dev/null) || body=''
    if _upd_parse_latest "$body"; then
      ver=$UPD_PARSED
      printf '%s\n%s\n' "${EPOCHSECONDS:-0}" "$ver" >"$f.tmp2" && mv -f "$f.tmp2" "$f"
    fi
  } &
  _UPD_PID=$!
  return 0
}

# Blocking check, for `hyn update` and doctor where waiting is the point.
update_check_now() {
  UPD_LAST_ERR=''
  have curl || {
    UPD_LAST_ERR='curl is required to check for updates'
    warn "$UPD_LAST_ERR"
    return 1
  }
  local body ver f
  body=$(curl -fsSL --max-time 12 --proto "$(_upd_proto)" \
    -H 'Accept: application/vnd.npm.install-v1+json' \
    "$UPD_REGISTRY/$HYN_PKG" 2>/dev/null) || {
    UPD_LAST_ERR="could not reach $UPD_REGISTRY"
    warn "$UPD_LAST_ERR"
    return 1
  }
  if ! _upd_parse_latest "$body"; then
    if [[ -n $UPD_PARSED ]]; then
      UPD_LAST_ERR="bad version from registry: ${UPD_PARSED:0:40}"
    else
      UPD_LAST_ERR='unexpected registry response'
    fi
    warn "$UPD_LAST_ERR"
    return 1
  fi
  ver=$UPD_PARSED
  UPD_LATEST=$ver
  UPD_CHECKED=${EPOCHSECONDS:-0}
  UPD_AVAILABLE=0
  ver_gt "$ver" "$HYN_VERSION" && UPD_AVAILABLE=1
  f=$(update_cache_file)
  state_dir_v
  [[ -d $STATE_DIR ]] || mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s\n%s\n' "$UPD_CHECKED" "$ver" >"$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  return 0
}

# How the package was installed decides how to upgrade it. Guessing wrong here
# would either fail or, worse, install a second copy that shadows the first.
UPD_METHOD=''
update_detect_method() {
  UPD_METHOD=''
  # A git checkout being run in place: `git pull` is the correct upgrade, and
  # npm would not know about it at all.
  if [[ -d $HYN_ROOT/.git ]]; then UPD_METHOD=git; return 0; fi
  # Inside a global node_modules tree.
  case $HYN_ROOT in
    */node_modules/*) UPD_METHOD=npm; return 0 ;;
  esac
  UPD_METHOD=unknown
  return 0
}

# Reload and restart only hyn-view's managed timers. Restarting a timer reloads
# its schedule without firing daily reports or alert jobs out of band. The
# current hyn-push one-shot is deliberately not restarted from inside itself;
# this invocation sends a fresh reading after the update finishes.
update_refresh_services() {
  is_root || return 0
  have systemctl || return 0
  systemctl daemon-reload >/dev/null 2>&1 || {
    UPD_LAST_ERR='systemd daemon reload failed'
    return 1
  }

  local unit state
  for unit in hyn-speedtest.timer hyn-record.timer hyn-alerts.timer hyn-report.timer hyn-push.timer; do
    systemctl is-enabled --quiet "$unit" >/dev/null 2>&1 || continue
    if ! systemctl restart "$unit" >/dev/null 2>&1; then
      UPD_LAST_ERR="could not restart $unit"
      return 1
    fi
    state=$(systemctl is-active "$unit" 2>/dev/null)
    if [[ $state != active ]]; then
      UPD_LAST_ERR="$unit is $state after restart"
      return 1
    fi
  done

  # The resident agent last, and only when this process is not living inside it.
  #
  # A restart here replaces a loop that is still executing the previous release's
  # code -- for a long-lived process that is not cosmetic, it is the only thing
  # that makes an update take effect. It is safe because every unattended install
  # runs in hyn-update.service, a separate cgroup, so restarting the agent cannot
  # kill the npm install doing it. HYN_IN_AGENT is the guard for the one case that
  # is not true: an operator running `hyn update --yes` inside a debugging
  # `hyn agent`, where the loop exits by itself on the version change instead.
  if [[ ${HYN_IN_AGENT:-0} != 1 ]] && systemctl is-enabled --quiet hyn-agent.service >/dev/null 2>&1; then
    if ! systemctl restart hyn-agent.service >/dev/null 2>&1; then
      UPD_LAST_ERR='could not restart hyn-agent.service'
      return 1
    fi
    state=$(systemctl is-active hyn-agent.service 2>/dev/null)
    # `activating` is a pass: Type=simple reports it for the instant between fork
    # and the first loop iteration, and failing an otherwise good update on that
    # race would be a self-inflicted rollback.
    if [[ $state != active && $state != activating ]]; then
      UPD_LAST_ERR="hyn-agent.service is $state after restart"
      return 1
    fi
  fi
  return 0
}

# update_apply -- performs the upgrade. Returns 0 only when the package,
# systemd integration and installed version all verify successfully.
update_apply() {
  local force=${1:-0} installed=''
  UPD_LAST_ERR=''
  update_detect_method
  if ((UPD_AVAILABLE == 0 && force == 0)); then
    printf 'hyn: already on the newest published version (%s)\n' "$HYN_VERSION"
    return 1
  fi
  case $UPD_METHOD in
    npm)
      have npm || { warn 'npm is not on PATH, cannot self-update'; return 1; }
      # A global install lives in a root-owned tree on a normal Ubuntu box.
      if [[ ! -w $HYN_ROOT ]] && ! is_root; then
        warn "cannot write $HYN_ROOT — re-run as: sudo hyn update"
        return 1
      fi
      printf 'hyn: updating %s -> %s via npm\n' "$HYN_VERSION" "${UPD_LATEST:-latest}"
      update_emit_progress installing "Downloading and installing hyn-view ${UPD_LATEST:-latest}"
      if npm install -g "$HYN_PKG@${UPD_LATEST:-latest}" >/dev/null 2>&1; then
        if is_root && [[ -x $HYN_ROOT/bin/hyn ]]; then
          update_emit_progress restarting 'Refreshing configuration and restarting hyn-view timers'
          if "$HYN_ROOT/bin/hyn" setup --no-wizard >/dev/null 2>&1; then
            if ! update_refresh_services; then
              warn "package updated, but managed services did not restart cleanly: $UPD_LAST_ERR"
              return 1
            fi
          else
            UPD_LAST_ERR='background services could not be refreshed'
            warn 'package updated, but background services could not be refreshed; run: sudo hyn setup --no-wizard'
            return 1
          fi
        fi

        update_emit_progress verifying 'Verifying the installed CLI and managed timers'
        if [[ -x $HYN_ROOT/bin/hyn ]]; then
          installed=$("$HYN_ROOT/bin/hyn" --version 2>/dev/null)
          installed=${installed##* }
        fi
        if [[ -z $installed || ! $installed =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
          UPD_LAST_ERR='the installed CLI version could not be verified'
          warn "$UPD_LAST_ERR"
          return 1
        fi
        if [[ -n $UPD_LATEST && $installed != "$UPD_LATEST" ]]; then
          UPD_LAST_ERR="expected $UPD_LATEST but found $installed after installation"
          warn "$UPD_LAST_ERR"
          return 1
        fi

        HYN_VERSION=$installed
        UPD_AVAILABLE=0
        printf 'hyn: updated to %s; managed services restarted and verified.\n' "$installed"
        return 0
      fi
      UPD_LAST_ERR='npm install failed; nothing was changed'
      warn "$UPD_LAST_ERR"
      return 1
      ;;
    git)
      have git || { warn 'git is not on PATH'; return 1; }
      printf 'hyn: %s is a git checkout; update with:\n  git -C %s pull\n' "$HYN_ROOT" "$HYN_ROOT"
      return 1
      ;;
    *)
      warn "cannot tell how $HYN_ROOT was installed; update it the way you installed it"
      return 1
      ;;
  esac
}

# Called once at launch. Honours auto_update and never blocks.
update_startup() {
  case ${CFG[auto_update]} in
    off) return 0 ;;
    install)
      update_read
      if ((UPD_AVAILABLE)); then
        # From a scheduled unit, hand the install to hyn-update.service: that
        # unit has the memory headroom node needs and the long timeout an npm
        # install needs, and delegating keeps the sixty-second check-in short.
        if declare -F cloud_should_handoff >/dev/null 2>&1 && cloud_should_handoff &&
           declare -F cloud_handoff_command >/dev/null 2>&1 &&
           cloud_handoff_command '' update; then
          UPD_STATE='installing'
        elif [[ ${HYN_IN_AGENT:-0} == 1 ]]; then
          # The resident loop never installs in its own cgroup. Its child would
          # be killed the moment the loop restarts -- and the loop restarts
          # *because of* the install, either from update_refresh_services or by
          # exiting on the version change -- so a half-written /usr is the likely
          # outcome. Without the maintenance unit it simply waits; hyn doctor
          # already reports that unit missing as the fault it is.
          UPD_STATE='available'
        else
          # Detached: a launch must not wait on a package install, and the
          # running process keeps using the code it already loaded either way.
          { update_apply 0 >/dev/null 2>&1; } &
          UPD_STATE='installing'
        fi
      fi
      update_check_async
      ;;
    *)
      update_check_async
      update_read
      ((UPD_AVAILABLE)) && UPD_STATE='available'
      ;;
  esac
  return 0
}

cmd_update() {
  local a apply=0 check_only=0
  for a in "$@"; do
    case $a in
      --check) check_only=1 ;;
      --yes | -y | --apply) apply=1 ;;
    esac
  done
  update_detect_method
  printf 'installed   %s\n' "$HYN_VERSION"
  printf 'location    %s (%s)\n' "$HYN_ROOT" "$UPD_METHOD"
  if ! update_check_now; then
    printf 'latest      unknown (registry unreachable)\n'
    return 1
  fi
  printf 'latest      %s\n' "$UPD_LATEST"
  if ((UPD_AVAILABLE == 0)); then
    printf '\nhyn: up to date.\n'
    return 0
  fi
  printf '\nhyn: %s is available.\n' "$UPD_LATEST"
  ((check_only)) && return 0
  if ((apply == 0)); then
    printf 'run `sudo hyn update --yes` to install it, or set auto_update=install in\n'
    printf '%s to have it applied on launch.\n' "$HYN_ETC/config"
    return 0
  fi
  update_apply 1
  return $?
}
