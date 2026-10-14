#!/usr/bin/env bash
# Install or update the dashboard on this VPS (run as root).
#   bash install.sh            install/update, enable at boot, start
#   bash install.sh uninstall  stop and remove (keeps /var/lib/hyn-dashboard)
# Default: http://127.0.0.1:8787, loopback only. Reach it with:
#   ssh -L 8787:127.0.0.1:8787 root@<server>   then open http://localhost:8787
# To listen elsewhere, set DASH_HOST and DASH_TOKEN in /etc/hyn-dashboard.env (token is mandatory).
set -euo pipefail
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dst=/opt/hyn-dashboard
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

if [ "${1:-}" = uninstall ]; then
  systemctl disable --now hyn-dashboard.service 2>/dev/null || true
  rm -f /etc/systemd/system/hyn-dashboard.service; rm -rf "$dst"; systemctl daemon-reload
  echo "removed (history kept in /var/lib/hyn-dashboard)"; exit 0
fi

command -v node >/dev/null || { echo "node is required (>= 20)" >&2; exit 1; }
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)' || { echo "node >= 20 required" >&2; exit 1; }
for f in server.mjs collector.mjs public/app.js; do
  node --input-type=module --check <"$src/$f" 2>/dev/null || { echo "syntax error in $f" >&2; exit 1; }
done

install -d -m 0755 "$dst" "$dst/public"
install -m 0644 "$src/server.mjs" "$src/collector.mjs" "$dst/"
install -m 0644 "$src"/public/* "$dst/public/"
install -m 0644 "$src/hyn-dashboard.service" /etc/systemd/system/hyn-dashboard.service
if [ ! -f /etc/hyn-dashboard.env ]; then
  repo=$(cd "$src/.." && pwd)                       # this checkout, when the dashboard lives inside it
  [ -d "$repo/.git" ] || repo=$(dirname "$src")/HYN-view
  { echo "# Dashboard settings. See install.sh header. Mode 0600."; [ -d "$repo/.git" ] && echo "HYN_REPO=$repo"; echo "DASH_PORT=8787"; } >/etc/hyn-dashboard.env
  chmod 0600 /etc/hyn-dashboard.env
fi
systemctl daemon-reload
systemctl enable hyn-dashboard.service >/dev/null
systemctl restart hyn-dashboard.service
for _ in $(seq 1 20); do
  curl -fsS -m2 "http://127.0.0.1:$(sed -n 's/^DASH_PORT=//p' /etc/hyn-dashboard.env | tail -1)/healthz" >/dev/null 2>&1 && { echo "hyn-dashboard is up (enabled at boot)"; exit 0; }
  sleep 1
done
echo "started but /healthz did not answer; see: journalctl -u hyn-dashboard -n 50" >&2; exit 1
