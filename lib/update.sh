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
#   * auto_update defaults to `check`, not `install`. See the comment on the
#     config key: unattended `npm i -g` as root on a production relay node is a
#     real risk, not a convenience. Opting in is a decision the operator makes.

UPD_LATEST='' UPD_AVAILABLE=0 UPD_CHECKED=0 UPD_STATE=''
UPD_REGISTRY='https://registry.npmjs.org'

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
    body=$(curl -fsSL --max-time 8 --proto '=https' \
      -H 'Accept: application/vnd.npm.install-v1+json' \
      "$UPD_REGISTRY/$HYN_PKG" 2>/dev/null) || body=''
    # Pull dist-tags.latest out of a flat, machine-generated document. Taking a
    # JSON parser dependency for one field would be absurd for a tool whose
    # entire selling point is having none.
    if [[ $body == *'"latest"'* ]]; then
      ver=${body#*\"latest\":\"}
      ver=${ver%%\"*}
      if [[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]]; then
        printf '%s\n%s\n' "${EPOCHSECONDS:-0}" "$ver" >"$f.tmp2" && mv -f "$f.tmp2" "$f"
      fi
    fi
  } &
  _UPD_PID=$!
  return 0
}

# Blocking check, for `hyn update` and doctor where waiting is the point.
update_check_now() {
  have curl || { warn 'curl is required to check for updates'; return 1; }
  local body ver f
  body=$(curl -fsSL --max-time 12 --proto '=https' \
    -H 'Accept: application/vnd.npm.install-v1+json' \
    "$UPD_REGISTRY/$HYN_PKG" 2>/dev/null) || {
    warn "could not reach $UPD_REGISTRY"
    return 1
  }
  [[ $body == *'"latest"'* ]] || { warn 'unexpected registry response'; return 1; }
  ver=${body#*\"latest\":\"}
  ver=${ver%%\"*}
  [[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || { warn "bad version from registry: $ver"; return 1; }
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

# update_apply -- performs the upgrade. Returns 0 only if something changed.
update_apply() {
  local force=${1:-0}
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
      if npm install -g "$HYN_PKG@${UPD_LATEST:-latest}" >/dev/null 2>&1; then
        if is_root && [[ -x $HYN_ROOT/bin/hyn ]]; then
          if "$HYN_ROOT/bin/hyn" setup --no-wizard >/dev/null 2>&1; then
            printf 'hyn: updated and background services refreshed. Restart `hyn` to use the new code.\n'
          else
            warn 'package updated, but background services could not be refreshed; run: sudo hyn setup --no-wizard'
          fi
        else
          printf 'hyn: updated. Restart `hyn` to use the new code.\n'
        fi
        return 0
      fi
      warn 'npm install failed; nothing was changed'
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
        # Detached: a launch must not wait on a package install, and the running
        # process keeps using the code it already loaded either way.
        { update_apply 0 >/dev/null 2>&1; } &
        UPD_STATE='installing'
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
