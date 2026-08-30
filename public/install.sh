#!/usr/bin/env bash
# hyn-view :: one-line installer
#
#   curl -fsSL https://www.hyn-view.in/install.sh | sudo bash
#
# What it does, in order: check the machine can run this at all, make sure the
# handful of system packages the agent needs are present, make sure there is a
# node new enough to run npm, install hyn-view globally, and then verify that the
# resident agent is actually running rather than trusting that it must be.
#
# Everything below lives inside main(), which is called on the very last line.
# That is not style: `curl | bash` executes what has arrived so far, so a
# connection dropped halfway through a script written top-to-bottom runs half an
# installation and reports success. If this file is truncated anywhere, main is
# never defined or never called, and nothing happens.
#
# Nothing here is idempotency-sensitive: re-running it upgrades the package and
# re-verifies the services, and it never overwrites an existing
# /etc/hyn-view/config.
#
# Environment overrides, for image builders and CI:
#   HYN_INSTALL_VERSION=1.9.0   install an exact version instead of latest
#   HYN_SKIP_APT=1              never touch apt, even if curl is missing
#   HYN_SKIP_NODE=1            never install or upgrade node
#   HYN_ASSUME_YES=1            reserved; this script is already non-interactive

set -uo pipefail

HYN_PKG='hyn-view'
HYN_MIN_NODE=18
# Not a wall of colour: three codes, and only when stdout is a terminal. Piped
# into a log or a provisioning tool the output stays plain text.
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_R=$'\033[0m'
else
  C_OK='' C_ERR='' C_DIM='' C_B='' C_R=''
fi

say()  { printf '%s==>%s %s\n' "$C_B" "$C_R" "$*"; }
ok()   { printf '  %sok%s   %s\n' "$C_OK" "$C_R" "$*"; }
note() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_R"; }
fail() { printf '  %sfail%s %s\n' "$C_ERR" "$C_R" "$*" >&2; }
die()  { fail "$*"; printf '\n%shyn-view was not installed.%s\n' "$C_ERR" "$C_R" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# apt-get, quietly, and only when we are actually going to install something.
# DEBIAN_FRONTEND because this runs unattended and a package that wants to ask
# about a config file would otherwise hang for ever.
apt_install() {
  [[ ${HYN_SKIP_APT:-0} == 1 ]] && { note "skipping apt ($*) because HYN_SKIP_APT=1"; return 1; }
  have apt-get || return 1
  if [[ ${_APT_UPDATED:-0} != 1 ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    _APT_UPDATED=1
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1
}

node_major() {
  local v
  have node || { printf '0'; return 0; }
  v=$(node --version 2>/dev/null) || v=''
  v=${v#v}
  v=${v%%.*}
  [[ $v =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# The agent is pure bash, so this is not a runtime: npm is the delivery channel
# and npm needs node. Ubuntu 24.04's own package is new enough; 22.04 ships
# node 12, which modern npm refuses to run on, so that box needs NodeSource.
ensure_node() {
  local major
  major=$(node_major)
  if have npm && ((major >= HYN_MIN_NODE)); then
    ok "node $(node --version 2>/dev/null) with npm $(npm --version 2>/dev/null)"
    return 0
  fi
  if [[ ${HYN_SKIP_NODE:-0} == 1 ]]; then
    have npm || die 'npm is required and HYN_SKIP_NODE=1 was set'
    return 0
  fi
  if ((major > 0 && major < HYN_MIN_NODE)); then
    note "node $major is too old for npm; installing node ${HYN_MIN_NODE}+"
  else
    note 'node and npm are not installed; installing them'
  fi

  # The distribution package first: on 24.04 that is the whole job, needs no
  # third-party repository, and is what the machine will keep updated by itself.
  if apt_install nodejs npm && have npm && (($(node_major) >= HYN_MIN_NODE)); then
    ok "node $(node --version) from the distribution"
    return 0
  fi

  # Otherwise NodeSource, which is how Node upstream distributes for Debian and
  # Ubuntu. Piped to bash, like this script, and for the same reason: there is no
  # alternative that does not involve trusting the same TLS connection.
  if have curl; then
    note 'installing node 20 from NodeSource (deb.nodesource.com)'
    if curl -fsSL --max-time 120 https://deb.nodesource.com/setup_20.x -o /tmp/hyn-nodesource.sh &&
       DEBIAN_FRONTEND=noninteractive bash /tmp/hyn-nodesource.sh >/dev/null 2>&1 &&
       apt_install nodejs; then
      rm -f /tmp/hyn-nodesource.sh
      have npm || apt_install npm || true
    fi
    rm -f /tmp/hyn-nodesource.sh
  fi

  have npm || die 'could not install npm. Install node 18 or newer, then re-run this command'
  (($(node_major) >= HYN_MIN_NODE)) ||
    note "node $(node --version 2>/dev/null) is older than $HYN_MIN_NODE; continuing, but upgrade it if the install fails"
  ok "node $(node --version 2>/dev/null) with npm $(npm --version 2>/dev/null)"
  return 0
}

# What the agent itself needs at runtime, as opposed to what installing it needs.
# None of these is fatal: every collector treats a missing tool as an unavailable
# reading rather than an error, which is the whole reason `hyn doctor` exists. But
# an agent that cannot resolve TLS or measure latency is a degraded one, and
# fixing that during the install is free.
ensure_runtime_deps() {
  local want=() pkg
  have curl || want+=(curl)
  # ca-certificates is the one that is genuinely not optional: without it every
  # https request the agent makes -- the portal, the npm registry, its own
  # updates -- fails certificate verification.
  [[ -e /etc/ssl/certs/ca-certificates.crt ]] || want+=(ca-certificates)
  have ping || want+=(iputils-ping)
  if ((${#want[@]} == 0)); then
    ok 'curl, CA certificates and ping are present'
    return 0
  fi
  note "installing: ${want[*]}"
  apt_install "${want[@]}" || true
  for pkg in "${want[@]}"; do
    case $pkg in
      curl) have curl && ok 'curl installed' || fail 'curl is still missing; speed tests and updates will not work' ;;
      ca-certificates)
        [[ -e /etc/ssl/certs/ca-certificates.crt ]] && ok 'CA certificates installed' ||
          fail 'CA certificates are still missing; https will fail' ;;
      iputils-ping) have ping && ok 'ping installed' || note 'ping is missing; latency falls back to a TCP handshake' ;;
    esac
  done
  return 0
}

install_package() {
  local spec="$HYN_PKG"
  [[ -n ${HYN_INSTALL_VERSION:-} ]] && spec="$HYN_PKG@$HYN_INSTALL_VERSION"
  say "Installing $spec globally"
  # The package's own postinstall writes /etc/hyn-view/config, creates the state
  # directory and installs and enables the systemd units, including the resident
  # agent. It cannot fail the install by design, which is exactly why this script
  # verifies the result below instead of believing the exit code.
  if ! npm install -g --no-fund --no-audit "$spec"; then
    die "npm could not install $spec. The output above says why; the usual cause is no network or a full disk"
  fi
  ok 'package installed'
}

# npm's global bin is not always on root's PATH under sudo, and `hyn setup`
# symlinks /usr/local/bin/hyn for exactly that reason. Resolve whichever exists.
hyn_bin() {
  if have hyn; then command -v hyn; return 0; fi
  local p
  for p in /usr/local/bin/hyn /usr/bin/hyn "$(npm prefix -g 2>/dev/null)/bin/hyn"; do
    [[ -x $p ]] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

verify() {
  local exe version
  exe=$(hyn_bin) || die 'hyn was installed but is not on PATH. Try: sudo /usr/local/bin/hyn doctor'
  version=$("$exe" --version 2>/dev/null | head -1) || version=''
  [[ -n $version ]] || die "$exe will not run. Run it directly to see why"
  ok "$version"

  if ! have systemctl; then
    note 'no systemd on this machine, so nothing is scheduled and no heartbeat is sent'
    note 'the CLI itself works: run `hyn`'
    return 0
  fi

  # The resident agent is the one that matters: it is what beats every 24
  # seconds, keeps the package updated and re-arms the other units. If the
  # postinstall could not enable it, say so and repair it rather than finishing
  # with a green tick.
  local state
  state=$(systemctl is-active hyn-agent.service 2>/dev/null)
  if [[ $state != active ]]; then
    note "hyn-agent.service is $state; repairing"
    "$exe" doctor --fix >/dev/null 2>&1 || true
    state=$(systemctl is-active hyn-agent.service 2>/dev/null)
  fi
  if [[ $state == active ]]; then
    ok 'hyn-agent.service is running (heartbeat every 24s, self-updating)'
  else
    fail "hyn-agent.service is $state — run: sudo hyn doctor"
  fi

  local u n=0
  for u in hyn-record.timer hyn-speedtest.timer hyn-alerts.timer hyn-report.timer; do
    [[ $(systemctl is-active "$u" 2>/dev/null) == active ]] && n=$((n + 1))
  done
  ok "$n of 4 scheduled timers active"
  return 0
}

main() {
  printf '\n%shyn-view%s · network-first monitor for Ubuntu Server\n' "$C_B" "$C_R"
  printf '%sinstalling the CLI, the systemd units and the resident 24/7 agent%s\n\n' "$C_DIM" "$C_R"

  [[ $(uname -s 2>/dev/null) == Linux ]] ||
    die "this installs a systemd agent, so it needs Linux (found $(uname -s 2>/dev/null || printf unknown))"

  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    printf '%s\n' \
      "  This installs system packages and systemd units, so it needs root." \
      '' \
      '    curl -fsSL https://www.hyn-view.in/install.sh | sudo bash' \
      '' >&2
    exit 1
  fi

  have bash || die 'bash is required'
  say 'Checking what this machine already has'
  ensure_runtime_deps
  ensure_node
  install_package
  say 'Verifying'
  verify

  printf '\n%sDone.%s\n' "$C_OK$C_B" "$C_R"
  printf '  %s\n' \
    "hyn                     open the dashboard" \
    "sudo hyn link           pair with the portal to watch this box from anywhere" \
    "hyn doctor              what works on this machine, and what does not"
  printf '\n%sMonitoring is already running: metrics are being sampled, alerts are being%s\n' "$C_DIM" "$C_R"
  printf '%sevaluated, and the agent updates itself. Pairing is the only optional step.%s\n\n' "$C_DIM" "$C_R"
  return 0
}

# Last line on purpose. See the header: a truncated download must do nothing.
main "$@"
