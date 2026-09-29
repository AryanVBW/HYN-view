# SSH to server02 over Cloudflare Tunnel (`ssh.hyn-view.in`)

Why not `data.hyn-view.in`: it resolves to Cloudflare edge IPs and Cloudflare's proxy
carries HTTP/HTTPS only — port 22 is never forwarded (verified: `ssh server02@data.hyn-view.in`
→ `Operation timed out`). That hostname is also already bound to Supabase's gateway in the
tunnel ingress, and one hostname cannot serve both HTTP and SSH. So SSH gets its own
hostname on the **same** tunnel.

Run everything below **on the server** unless marked "on your Mac".

---

## Step 0 — which mode is your tunnel in?

```sh
sudo systemctl cat cloudflared | grep -E 'ExecStart'
sudo ls -la /etc/cloudflared/ /root/.cloudflared/ 2>/dev/null
```

- ExecStart contains **`--token ey…`** or `tunnel run --token` → **dashboard-managed** → do **Step 1A**
- ExecStart contains **`--config /etc/cloudflared/config.yml`** (and that file exists) →
  **locally managed** → do **Step 1B**

Get the tunnel name/id either way:

```sh
cloudflared tunnel list
```

---

## Step 1A — dashboard-managed tunnel (no local config file)

Ingress lives in Cloudflare, so do not create a local `config.yml` — it would be ignored.

1. Cloudflare dashboard → **Zero Trust** → **Networks → Tunnels**
2. Click your tunnel → **Public Hostname** → **Add a public hostname**
3. Fill in:
   - Subdomain: `ssh`
   - Domain: `hyn-view.in`
   - Type: **SSH**
   - URL: `localhost:22`
4. Save. Cloudflare creates the DNS record automatically.

Nothing to restart — dashboard-managed tunnels pick up config live.

---

## Step 1B — locally managed tunnel (`/etc/cloudflared/config.yml`)

Edit the file and add the SSH hostname **above** the catch-all. Keep the existing
Supabase entry exactly as it is:

```yaml
tunnel: <tunnel-id-or-name>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: ssh.hyn-view.in
    service: ssh://localhost:22

  - hostname: data.hyn-view.in
    service: http://localhost:8000     # existing Supabase gateway — do not change

  - service: http_status:404           # must stay last
```

Order matters: cloudflared takes the first matching rule, and the catch-all must be last.

```sh
sudo cloudflared tunnel ingress validate            # syntax check before restarting
sudo cloudflared tunnel route dns <tunnel-name> ssh.hyn-view.in
sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager | head -15
```

---

## Step 2 — verify from outside (on your Mac)

```sh
brew install cloudflared                 # not currently installed on the Mac
dig +short ssh.hyn-view.in               # should return Cloudflare IPs
cloudflared access ssh --hostname ssh.hyn-view.in --destination-only   # connectivity probe
```

Add to `~/.ssh/config`:

```
Host ssh.hyn-view.in
  User server02
  ProxyCommand cloudflared access ssh --hostname %h
  ServerAliveInterval 30
```

Then:

```sh
ssh ssh.hyn-view.in          # or: ssh server02@ssh.hyn-view.in
```

This works from any network, which is the point — it survives the subnet change that
just cut off `192.168.0.105`.

---

## Step 3 — fix SSH authentication (do this, not optional)

The account currently accepts **password** auth with a 4-space password. Once SSH is
reachable from anywhere, that is a live risk. Install a key and turn passwords off.

**On your Mac:**

```sh
ssh-keygen -t ed25519 -C "vivek-mac -> server02" -f ~/.ssh/server02_ed25519
cat ~/.ssh/server02_ed25519.pub
```

**On the server** — paste that public key:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA... vivek-mac -> server02' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Confirm key login works in a second terminal before locking anything**, then:

```sh
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

`sudo sshd -t` validates the config first — if it fails, do **not** reload, or you can
lock yourself out. Keep the existing session open until a fresh key login succeeds.

Point the Mac's ssh config at the key:

```
Host ssh.hyn-view.in
  User server02
  IdentityFile ~/.ssh/server02_ed25519
  ProxyCommand cloudflared access ssh --hostname %h
```

Also change the account password to something real:

```sh
passwd
```

---

## Step 4 — gate it with Cloudflare Access (recommended)

Without this, anyone who learns the hostname reaches your SSH banner. With it, they
must pass Cloudflare identity first.

1. Zero Trust → **Access → Applications → Add an application → Self-hosted**
2. Application domain: `ssh.hyn-view.in`
3. Policy: Action **Allow**, Include → **Emails** → `hynview@gmail.com`
4. Save

The `cloudflared access ssh` ProxyCommand handles the auth flow; first connection opens
a browser once, then caches the token.

---

## Supabase MCP over this SSH login

Studio's MCP server has no authentication, so `data.hyn-view.in/mcp` and `/api/mcp`
stay blocked (403) at the gateway. Do **not** follow the Supabase guide's step that
allow-lists the Docker gateway IP. Here every request, including every one arriving
through Cloudflare, reaches Envoy from `172.18.0.1`, so that allow-list would open MCP to
the whole internet.

[`supabase/mcp-over-ssh.sh`](../supabase/mcp-over-ssh.sh) is a local stdio MCP server
instead. It uses your SSH key login (`ssh hyn`, through this tunnel) and runs a small
bridge inside the Studio container. The bridge forwards each JSON-RPC message to Studio
on loopback. Nothing is opened on the server. Kiro, in `.kiro/settings/mcp.json`:

```json
{ "mcpServers": { "supabase": {
    "command": "/bin/bash",
    "args": ["/Volumes/DATA_vivek/GITHUB/HYN-view/supabase/mcp-over-ssh.sh"] } } }
```

- **Read-only by default.** SQL runs as `supabase_read_only_user` in a read-only
  transaction. Set `HYN_MCP_QUERY=read_only=false` in the server's `env` to allow writes.
  Keep schema changes on the reviewed migration path in `selfhost-supabase-migration.md`.
- **Read-only mode needs a password on `supabase_read_only_user`.** Studio connects as
  that role with `POSTGRES_PASSWORD`. The Supabase image creates the role without one,
  so read-only SQL failed with `password authentication failed`. The password was set on
  2026-09-29. After rebuilding the database, set it again from inside the LXD container:

  ```sh
  docker exec -i supabase-db psql -U supabase_admin -d postgres <<'SQL'
  \set pgpass `echo "$POSTGRES_PASSWORD"`
  alter role supabase_read_only_user with password :'pgpass';
  SQL
  ```
- On the LAN, set `HYN_MCP_HOST=hyn-lan`. With a Cloudflare Access policy on
  `ssh.hyn-view.in` (Step 4), the first launch waits for the browser sign-in.
- Check: `/mcp` in Kiro shows `supabase` with 10 tools.

---

## What this does not change

- `data.hyn-view.in` keeps serving Supabase exactly as now — this only adds a hostname.
- Supabase's `/mcp` route stays blocked by envoy RBAC; use the SSH bridge above.
- Google sign-in remains broken until the real `GOCSPX-…` client secret is set in
  `~/supabase-project/.env` → `GOOGLE_SECRET=`, then:
  ```sh
  cd ~/supabase-project && sudo docker compose up -d --force-recreate auth
  ```
  (run inside the LXD container: `sudo lxc exec supabase -- bash -c 'cd /opt/supabase-project && docker compose up -d --force-recreate auth'`)
