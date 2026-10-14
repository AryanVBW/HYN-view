# VPS dashboard

A single-page, live dashboard for the server hyn-view runs on. Zero npm dependencies (Node >= 20),
read-only, and separate from the npm package (`package.json` `files` does not include it).

It reads the machine directly: `/proc`, systemd, journald, `ss`, `sshd -T`, and hyn-view's own state
files and `hyn snapshot --json`. It shows CPU, memory, disk, network, load and pressure charts
(30 min live, up to 7 days of history), services and timers, alerts with history, deployment checks
(installed vs repo version, unit drift, backups, portal sync), Highway and Nebula status, top
processes, listening ports, security posture and a live log viewer.

```bash
sudo bash dashboard/install.sh              # install or update; enabled at boot, restarts on failure
sudo bash dashboard/install.sh uninstall
node dashboard/test/ui-smoke.mjs            # renders public/app.js against a running instance
```

It listens on `127.0.0.1:8787` only. Reach it with `ssh -L 8787:127.0.0.1:8787 root@host`.
Settings live in `/etc/hyn-dashboard.env`: `DASH_PORT`, `DASH_HOST`, `DASH_TOKEN` (mandatory for any
non-loopback host), `DASH_WEBHOOK_URL` (critical alerts as JSON), `HYN_REPO`, and
`DASH_OFFSITE_PROVIDER=1` to record that off-machine copies come from the VPS provider.

## Backup

`backup/` installs `hyn-sysbackup.timer`: a daily archive of configuration and state in
`/var/backups/hyn-system` (7 kept, checksummed, read back before it counts as a success). It is not
a disk image. It leaves out every private key and credential (`*.key`, `*_key`, `*.env`, secrets,
shadow, SSH host keys) and the large Highway binaries. Highway's sealed `.hrb` recovery file, which
is already encrypted with the manager mnemonic, is included. Set `HYN_BACKUP_REMOTE=user@host:/path/`
in `/etc/hyn-sysbackup.env` to rsync each archive off the machine.

Install it with `sudo install -m 0750 dashboard/backup/hyn-sysbackup.sh /usr/local/sbin/ &&
sudo install -m 0644 dashboard/backup/hyn-sysbackup.{service,timer} /etc/systemd/system/ &&
sudo systemctl daemon-reload && sudo systemctl enable --now hyn-sysbackup.timer`.
