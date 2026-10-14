#!/usr/bin/env bash
# Daily configuration and state backup for this VPS (not a disk image).
#
# What it is for: undoing mistakes and rebuilding the box's setup (systemd units, hyn-view and
# dashboard config/state, Highway/Nebula configs, package list, SSH config).
# What it deliberately leaves out: every private key and credential (*.key, *_key, *.env, secrets,
# shadow, SSH host keys, hway-key-custody) and the large reinstallable Highway binaries.
# Highway's own sealed recovery file (/root/highway-recovery-*.hrb, encrypted with the manager
# mnemonic) is included because it is already encrypted. Relayer keys stay protected by it.
#
# This copy lives on the same disk. For disaster recovery, ship the archives off the machine
# (see HYN_BACKUP_REMOTE below).
set -euo pipefail
umask 077

DEST=${HYN_BACKUP_DIR:-/var/backups/hyn-system}
KEEP=${HYN_BACKUP_KEEP:-7}
[[ $KEEP =~ ^[1-9][0-9]*$ ]] || { echo "HYN_BACKUP_KEEP must be a positive integer, using 7" >&2; KEEP=7; }
REMOTE=${HYN_BACKUP_REMOTE:-}         # optional rsync target, e.g. user@host:/path/ (ssh key auth, no passwords)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
host=$(hostname)
name="$host-$STAMP.tar.gz"

mkdir -p "$DEST"
exec 9>"$DEST/.lock"
flock -n 9 || { echo "another backup is running" >&2; exit 0; }

work=$(mktemp -d "$DEST/.work.XXXXXX")
trap 'rm -rf "$work"' EXIT

# Inventory written into the archive: lets you see what the machine looked like.
inv="$work/inventory"; mkdir -p "$inv"
dpkg --get-selections >"$inv/dpkg-selections.txt" 2>/dev/null || true
systemctl list-unit-files --no-pager >"$inv/unit-files.txt" 2>/dev/null || true
systemctl list-units --all --no-pager >"$inv/units.txt" 2>/dev/null || true
crontab -l >"$inv/root-crontab.txt" 2>/dev/null || true
ip -br addr >"$inv/ip-addr.txt" 2>/dev/null || true
sshd -T >"$inv/sshd-effective.txt" 2>/dev/null || true
df -h >"$inv/df.txt" 2>/dev/null || true
{ echo "created=$STAMP"; echo "host=$host"; echo "kernel=$(uname -r)"; echo "hyn=$(hyn --version 2>/dev/null </dev/null | head -1)"; } >"$inv/manifest.txt"

# Small helper files under /usr/local (scripts and wrappers; skip big binaries).
find /usr/local/bin /usr/local/sbin -maxdepth 1 -type f -size -2M 2>/dev/null | sed 's#^/##' >"$work/small-bins.txt"

# Everything except secrets and bulk. Failures to read a vanished file must not abort the run.
set +e
tar --create --gzip --file "$work/$name" --warning=no-file-changed --ignore-failed-read \
  --exclude='*.key' --exclude='*_key' --exclude='*.env' --exclude='*secret*' --exclude='*token*' \
  --exclude='shadow*' --exclude='gshadow*' --exclude='ssh_host_*' --exclude='*.pem' --exclude='device.key.file' \
  --exclude='var/lib/hyn-view/local' --exclude='var/lib/hyn-view/*.lock' \
  --exclude='etc/ssl/private' --exclude='etc/hway-relayer/relayers/*/data' \
  -C / \
  etc \
  var/lib/hyn-view \
  var/lib/hyn-dashboard \
  opt/hyn-dashboard \
  usr/local/lib/node_modules/hyn-view \
  root/highway-recovery-*.hrb \
  -T "$work/small-bins.txt" \
  -C "$work" inventory 2>"$work/tar.err"
rc=$?
set -e
# tar exits 1 when a file changed or vanished while it was read (normal for live state);
# only 2+ means the archive itself is bad. Say what was skipped instead of hiding it.
if [ "$rc" -ge 2 ]; then cat "$work/tar.err" >&2; echo "tar failed (rc=$rc)" >&2; exit 1; fi
[ -s "$work/tar.err" ] && echo "note: $(wc -l <"$work/tar.err") file warning(s), e.g. $(head -1 "$work/tar.err")" >&2

tar --list --gzip --file "$work/$name" >/dev/null                       # archive must read back
if tar --list --gzip --file "$work/$name" | grep -Eq '(^|/)(shadow|gshadow|host\.key|p2p_key|secrets|ssh_host_[a-z0-9_]+_key)$'; then
  echo "refusing: a secret slipped into the archive" >&2; exit 1
fi
# Filenames are not enough: also refuse an archive whose content holds a PEM private key.
if tar --extract --to-stdout --gzip --file "$work/$name" 2>/dev/null | grep -aqE -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'; then
  echo "refusing: archive content contains a private key" >&2; exit 1
fi
# Excluded paths must really be absent (a wrong pattern once let 27k files through).
if tar --list --gzip --file "$work/$name" | grep -Eq '^(var/lib/hyn-view/local/|etc/hway-relayer/relayers/[^/]+/data/)'; then
  echo "refusing: an excluded directory is inside the archive" >&2; exit 1
fi

mv "$work/$name" "$DEST/$name"
( cd "$DEST" && sha256sum "$name" >"$name.sha256" )
date +%s >"$DEST/last-success"

# Retention: newest $KEEP archives.
ls -1t "$DEST"/*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do rm -f "$old" "$old.sha256"; done

if [ -n "$REMOTE" ]; then
  sent=0
  for attempt in 1 2 3; do      # the network may still be coming up after a catch-up run
    if rsync -a --timeout=60 -e 'ssh -o BatchMode=yes -o StrictHostKeyChecking=yes' "$DEST/$name" "$DEST/$name.sha256" "$REMOTE"; then
      date +%s >"$DEST/last-offsite"; sent=1; break
    fi
    sleep 30
  done
  [ "$sent" = 1 ] || echo "offsite copy failed after 3 tries (local backup is fine)" >&2
fi
echo "backup ok: $DEST/$name ($(du -h "$DEST/$name" | cut -f1))"
