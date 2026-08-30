#!/usr/bin/env bash
# hyn-view :: npm postinstall
#
# `npm install -g hyn-view` is the whole installation. This script finishes it:
# the config file under /etc, the state directory under /var/lib, and the systemd
# timers. Nothing to answer, nothing to run afterwards except `sudo hyn link` if
# the machine is going to report to the portal.
#
# This used to be a deliberate manual step, on the reasoning that a postinstall
# writing systemd units is doing something the user did not ask for. That is a
# fair concern for a library. It is the wrong call for a monitoring agent whose
# entire value is being installed on a box nobody logs into: an operator who runs
# `npm install -g hyn-view`, sees it succeed, and walks away had every reason to
# believe monitoring was running. It was not, and nothing said so.
#
# Four rules keep it honest:
#
#   1. It NEVER fails the install. Every path exits 0. A monitor that cannot
#      configure itself is a degraded monitor, not a broken package.
#   2. It only acts on a global install as root on a systemd Linux box. A local
#      `npm i hyn-view` in someone's project touches nothing.
#   3. It is idempotent, and it never overwrites an existing config file.
#   4. HYN_NO_POSTINSTALL=1 opts out completely, for image builders and CI.
#
# It does not pair with the portal, because pairing needs a human with a browser,
# and it does not ask questions, because there is no terminal to ask on.

set -u

# Never let a monitoring tool's own setup break `npm install`.
trap 'exit 0' ERR

say() { printf 'hyn-view: %s\n' "$1"; }

[[ ${HYN_NO_POSTINSTALL:-} == 1 ]] && { say 'postinstall skipped (HYN_NO_POSTINSTALL=1)'; exit 0; }

# A local dependency install must not reconfigure the machine. npm sets this for
# `-g`; when it is absent, assume local and do nothing.
case ${npm_config_global:-} in
  true | 1) ;;
  *)
    say 'local install detected; not configuring system services'
    say 'run `sudo hyn setup` if this was meant to be a global install'
    exit 0 ;;
esac

[[ $(uname -s 2>/dev/null) == Linux ]] || { say 'not Linux; nothing to configure'; exit 0; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  say 'not running as root, so the timers were not installed'
  say 'finish with: sudo hyn setup --no-wizard'
  exit 0
fi

command -v systemctl >/dev/null 2>&1 || {
  say 'no systemd here; the CLI works but nothing will be scheduled'
  exit 0
}

# Resolve our own bin relative to this script, not via PATH: during a global
# install the symlink into /usr/local/bin may not exist yet.
here=$(cd -P "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd) || here=''
exe="${here%/scripts}/bin/hyn"
[[ -x $exe ]] || { say "cannot find my own executable at ${exe:-unknown}"; exit 0; }

say 'configuring system integration'
# --no-wizard because there is no terminal to run a wizard on. Every default is
# already the right answer for a 24/7 node, which is what makes this safe to do
# unattended at all.
if "$exe" setup --no-wizard; then
  say 'ready. Monitoring is scheduled.'
  # Only mention pairing when it has not already happened, so a reinstall on a
  # linked box does not read like an unfinished install.
  if ! "$exe" cloud status 2>/dev/null | grep -q 'token *present'; then
    say 'to see this machine in the web portal: sudo hyn link'
  fi
else
  say 'setup did not complete. The CLI still works; run: sudo hyn doctor --fix'
fi
exit 0
