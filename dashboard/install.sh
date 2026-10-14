#!/usr/bin/env bash
# Install or update the dashboard on this VPS (run as root).
#   bash install.sh            install/update, enable at boot, start
#   bash install.sh uninstall  stop and remove (keeps /var/lib/hyn-dashboard)
# Default: http://127.0.0.1:8787, loopback only. Reach it with:
#   ssh -L 8787:127.0.0.1:8787 root@<server>   then open http://localhost:8787
# To listen elsewhere, set DASH_HOST and DASH_TOKEN in /etc/hyn-dashboard.env. A token over plain HTTP
# can be sniffed, so a non-loopback host also needs DASH_TLS_CERT and DASH_TLS_KEY (or a TLS proxy in
# front plus DASH_ALLOW_PLAINTEXT=1, with the dashboard itself kept on loopback).
set -euo pipefail
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dst=/opt/hyn-dashboard
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

if [ "${1:-}" = uninstall ]; then
  systemctl disable --now hyn-dashboard.service 2>/dev/null || true
  rm -f /etc/systemd/system/hyn-dashboard.service; rm -rf "$dst"; systemctl daemon-reload
  echo "removed (history kept in /var/lib/hyn-dashboard)"; exit 0
fi

command -v node >/dev/null || { echo "node is required (>= 18.15)" >&2; exit 1; }
for f in server.mjs collector.mjs public/app.js; do
  node --input-type=module --check <"$src/$f" 2>/dev/null || { echo "syntax error in $f" >&2; exit 1; }
done

install -d -m 0755 "$dst" "$dst/public"
install -m 0644 "$src/server.mjs" "$src/collector.mjs" "$dst/"
install -m 0644 "$src"/public/* "$dst/public/"
# The unit must run a system-wide node that survives reboots and tool updates, never one from a home directory.
nodebin=
for cand in /usr/bin/node /usr/local/bin/node /opt/node/bin/node "$(command -v node || true)"; do
  [ -x "$cand" ] || continue
  real=$(readlink -f "$cand")
  case "$real" in /root/*|/home/*) continue ;; esac
  nodebin=$real; break
done
[ -n "$nodebin" ] || { echo "no system-wide node found (looked in /usr/bin, /usr/local/bin, /opt/node); install Node >= 18.15 system-wide" >&2; exit 1; }
# 18.15 is where fs.statfsSync landed; the dashboard is tested on the Ubuntu 24.04 system node (18.19).
"$nodebin" -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>18||(a===18&&b>=15)?0:1)' || { echo "$nodebin is older than Node 18.15" >&2; exit 1; }
sed "s#@NODE@#$nodebin#" "$src/hyn-dashboard.service" >/etc/systemd/system/hyn-dashboard.service
chmod 0644 /etc/systemd/system/hyn-dashboard.service
if [ ! -f /etc/hyn-dashboard.env ]; then
  repo=$(cd "$src/.." && pwd)                       # this checkout, when the dashboard lives inside it
  [ -e "$repo/.git" ] || repo=$(dirname "$src")/HYN-view   # -e: a git worktree has a .git file, not a directory
  { echo "# Dashboard settings. See install.sh header. Mode 0600."; [ -e "$repo/.git" ] && echo "HYN_REPO=$repo"; echo "DASH_PORT=8787"; } >/etc/hyn-dashboard.env
fi
chmod 0600 /etc/hyn-dashboard.env                         # also tightens a file that already existed (it may hold DASH_TOKEN)
systemctl daemon-reload
systemctl enable hyn-dashboard.service >/dev/null
systemctl restart hyn-dashboard.service
# Probe the address the service really binds to (defaults match server.mjs).
envval() { sed -n "s/^$1=//p" /etc/hyn-dashboard.env | tail -1; }
host=$(envval DASH_HOST); host=${host:-127.0.0.1}; port=$(envval DASH_PORT); port=${port:-8787}
case "$host" in 0.0.0.0|::|'[::]') host=127.0.0.1 ;; esac
scheme=http; [ -n "$(envval DASH_TLS_CERT)" ] && scheme=https
for _ in $(seq 1 20); do
  curl -fsSk -m2 "$scheme://$host:$port/healthz" >/dev/null 2>&1 && { echo "hyn-dashboard is up (enabled at boot)"; exit 0; }
  sleep 1
done
echo "started but /healthz did not answer; see: journalctl -u hyn-dashboard -n 50" >&2; exit 1
