-- hyn-view <-> web portal integration schema
--
-- Apply this in the Supabase SQL editor (or `supabase db push`) before pairing
-- any node. Definitions are written to support reapplication, but reapplying
-- this file is not universally non-destructive: its in-place privacy upgrades
-- remove legacy central notification tables and discard unsupported node-config
-- keys. Review the migration notes and take any required export or backup first.
--
-- Design notes that matter:
--
--   * The Ubuntu server has NO browser, so pairing uses a device-code flow
--     modelled on `gh auth login`: the server asks for a code, prints it, and
--     polls; the human approves it from a browser on some other device.
--
--   * The server authenticates to Supabase with the PUBLIC anon key only. It
--     never holds a service-role key, because a monitoring agent on a rented
--     VPS is exactly the wrong place to keep a key that bypasses RLS. All
--     privileged work happens inside SECURITY DEFINER functions with a pinned
--     search_path, which are the only things the anon role may call.
--
--   * Human pairing codes use slow, independently salted bcrypt verifiers.
--     High-entropy device codes and node tokens use SHA-256 verifiers. Plaintext
--     credentials are returned only to the party that needs them and are not
--     stored afterwards.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- tables
-- ---------------------------------------------------------------------------

create table if not exists public.nodes (
  id           uuid primary key default gen_random_uuid(),
  owner        uuid not null references auth.users (id) on delete cascade,
  name         text not null,
  hostname     text,
  os           text,
  agent_version text,
  token_hash   text unique,
  is_demo      boolean not null default false,
  revoked      boolean not null default false,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz
);

create index if not exists nodes_owner_idx on public.nodes (owner);

-- One row per `hyn push`. payload keeps the full snapshot so the portal can
-- grow new panels without a migration; the extracted columns exist because
-- charting 24h of data through jsonb accessors gets slow enough to notice.
create table if not exists public.metrics (
  id           bigserial primary key,
  node_id      uuid not null references public.nodes (id) on delete cascade,
  ts           timestamptz not null default now(),
  cpu_pct      numeric,
  cpu_temp_c   numeric,
  cpu_mhz      numeric,
  cpu_model    text,
  cpu_steal    numeric,
  cpu_iowait   numeric,
  cpu_cores    integer,
  load1        numeric,
  mem_pct      numeric,
  mem_total    bigint,
  mem_used     bigint,
  swap_used    bigint,
  disk_pct     numeric,
  uptime_s     bigint,
  net_iface    text,
  net_rx_bps   bigint,
  net_tx_bps   bigint,
  net_retrans_pm numeric,
  latency_ms   numeric,
  payload      jsonb,
  unique (node_id, ts)
);

create index if not exists metrics_node_ts_idx on public.metrics (node_id, ts desc);

create table if not exists public.speedtests (
  id        bigserial primary key,
  node_id   uuid not null references public.nodes (id) on delete cascade,
  ts        timestamptz not null default now(),
  down_bps  bigint,
  up_bps    bigint,
  latency_ms numeric,
  note      text,
  unique (node_id, ts)
);

create index if not exists speedtests_node_ts_idx on public.speedtests (node_id, ts desc);

create table if not exists public.alert_events (
  id        bigserial primary key,
  node_id   uuid not null references public.nodes (id) on delete cascade,
  ts        timestamptz not null default now(),
  rule      text,
  severity  text not null check (severity in ('info', 'warn', 'crit')),
  message   text not null,
  resolved  boolean not null default false
);

create index if not exists alert_events_node_ts_idx on public.alert_events (node_id, ts desc);

-- Short-lived pairing codes. The eight-symbol human code uses a slow salted
-- verifier because it has far less entropy than the 32-byte device secret.
create table if not exists public.device_codes (
  id                 uuid primary key default gen_random_uuid(),
  user_code_verifier text not null,
  device_code_hash   text not null unique,
  hostname           text,
  os                 text,
  agent_version      text,
  approved_by        uuid references auth.users (id) on delete cascade,
  node_id            uuid references public.nodes (id) on delete set null,
  node_token_hash    text,
  token_claimed      boolean not null default false,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null
);

-- `schema.sql` is also documented as safe to reapply to an older project, so
-- perform the same in-place upgrade as the timestamped migration. Active
-- legacy pairings remain usable; only their persisted representation changes.
alter table public.device_codes
  add column if not exists user_code_verifier text;

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'device_codes'
       and column_name = 'user_code'
  ) then
    execute $sql$
      update public.device_codes
         set user_code_verifier = extensions.crypt(
               upper(trim(user_code)), extensions.gen_salt('bf', 10)
             )
       where user_code_verifier is null
    $sql$;
  end if;
end;
$$;

alter table public.device_codes
  alter column user_code_verifier set not null;

drop index if exists public.device_codes_user_code_hash_idx;
alter table public.device_codes drop column if exists user_code_hash;
alter table public.device_codes drop column if exists user_code;

create index if not exists device_codes_expiry_idx on public.device_codes (expires_at);

-- Owner-requested maintenance commands. Nodes pull these with their own token;
-- the browser can observe progress but cannot forge agent acknowledgements.
create table if not exists public.node_commands (
  id               uuid primary key default gen_random_uuid(),
  node_id          uuid not null references public.nodes (id) on delete cascade,
  requested_by     uuid references auth.users (id) on delete set null,
  command          text not null check (command in ('update')),
  status           text not null default 'queued'
                     check (status in ('queued', 'running', 'succeeded', 'failed', 'expired')),
  stage            text not null default 'queued'
                     check (stage in ('queued', 'accepted', 'checking', 'installing',
                                      'restarting', 'verifying', 'completed', 'failed', 'expired')),
  message          text not null default 'Waiting for the machine to check in',
  target_version   text,
  result_version   text,
  requested_at     timestamptz not null default now(),
  started_at       timestamptz,
  finished_at      timestamptz,
  updated_at       timestamptz not null default now(),
  lease_expires_at timestamptz
);

create index if not exists node_commands_node_requested_idx
  on public.node_commands (node_id, requested_at desc);
create unique index if not exists node_commands_one_active_update_idx
  on public.node_commands (node_id, command)
  where status in ('queued', 'running');

-- ---------------------------------------------------------------------------
-- row level security
-- ---------------------------------------------------------------------------
-- Owners read their own rows and nothing else. Note there are deliberately NO
-- insert policies for metrics/speedtests/alert_events: writes arrive only
-- through hyn_ingest(), which authenticates a node token. A browser session
-- cannot forge telemetry for a node it happens to own.

alter table public.nodes        enable row level security;
alter table public.metrics      enable row level security;
alter table public.speedtests   enable row level security;
alter table public.alert_events enable row level security;
alter table public.device_codes enable row level security;
alter table public.node_commands enable row level security;

drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes
  for select using (owner = auth.uid());

-- Renaming and revoking a node is a legitimate browser action.
drop policy if exists nodes_update_own on public.nodes;
create policy nodes_update_own on public.nodes
  for update using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists nodes_delete_own on public.nodes;
create policy nodes_delete_own on public.nodes
  for delete using (owner = auth.uid());

drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics
  for select using (
    exists (select 1 from public.nodes n where n.id = metrics.node_id and n.owner = auth.uid())
  );

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests
  for select using (
    exists (select 1 from public.nodes n where n.id = speedtests.node_id and n.owner = auth.uid())
  );

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events
  for select using (
    exists (select 1 from public.nodes n where n.id = alert_events.node_id and n.owner = auth.uid())
  );

-- device_codes is intentionally unreadable from any client. The pairing code is
-- shown on the server's terminal; letting a browser list pending codes would
-- turn "approve the code in front of me" into "approve whatever is pending",
-- which is the one thing this flow exists to prevent.

drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands
  for select using (
    exists (
      select 1 from public.nodes n
       where n.id = node_commands.node_id and n.owner = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

create or replace function public._hyn_sha256(p_text text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(p_text, 'sha256'), 'hex');
$$;

-- Delete one expired pairing and, when approval already created a node but the
-- agent never claimed its token, delete that unclaimable node in the same
-- transaction. Claimed nodes remain; only their expired pairing row is burned.
create or replace function public._hyn_delete_expired_device_code(p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_node_id uuid;
  v_token_claimed boolean;
begin
  delete from public.device_codes
   where id = p_id and expires_at <= now()
   returning node_id, token_claimed into v_node_id, v_token_claimed;

  if not found then
    return false;
  end if;

  if v_node_id is not null and not v_token_claimed then
    delete from public.nodes
     where id = v_node_id
       and not exists (
         select 1 from public.device_codes where node_id = v_node_id
       );
  end if;

  return true;
end;
$$;

-- Cleanup is event-driven: each pairing RPC runs this, so an expired row may
-- remain until the next pairing request. Ordered SKIP LOCKED acquisition makes
-- concurrent cleanup non-blocking and avoids cross-row lock cycles.
create or replace function public._hyn_purge_expired_device_codes()
returns bigint
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_id uuid;
begin
  v_deleted := 0;
  for v_id in
    select id
      from public.device_codes
     where expires_at <= now()
     order by id
     for update skip locked
  loop
    if public._hyn_delete_expired_device_code(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

-- Internal only. The security-definer pairing RPCs call it as their owner.
revoke all on function public._hyn_delete_expired_device_code(uuid) from public;
revoke all on function public._hyn_purge_expired_device_codes() from public;

-- Crockford-ish alphabet: no 0/O/1/I/L/U, because these codes get read off one
-- screen and typed into another, frequently over a phone camera.
create or replace function public._hyn_user_code()
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  n constant integer := 30;             -- length(alphabet)
  -- Largest multiple of n below 256. Bytes at or above it are discarded so the
  -- draw is uniform; taking v % n over the whole byte range would make the first
  -- 16 symbols ~7% likelier than the rest.
  limit_b constant integer := 240;
  out text := '';
  buf bytea;
  i integer := 0;
  v integer;
begin
  -- gen_random_bytes, not random(): random() is a fast non-cryptographic PRNG,
  -- and this code is the only thing standing between a pending pairing request
  -- and whoever types it in first. The device code and node token already come
  -- from here; this one was the odd exception.
  buf := extensions.gen_random_bytes(64);
  while length(out) < 9 loop
    if i >= 64 then
      buf := extensions.gen_random_bytes(64);
      i := 0;
    end if;
    v := get_byte(buf, i);
    i := i + 1;
    continue when v >= limit_b;
    out := out || substr(alphabet, 1 + (v % n), 1);
    if length(out) = 4 then
      out := out || '-';
    end if;
  end loop;
  return out;
end;
$$;

-- ---------------------------------------------------------------------------
-- device pairing: step 1, the server asks for a code
-- ---------------------------------------------------------------------------

create or replace function public.hyn_device_start(
  p_hostname text default null,
  p_os text default null,
  p_agent_version text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_device_code text;
  v_user_code text;
  v_expires timestamptz;
  v_try integer := 0;
begin
  -- Event-driven cleanup: expiry is enforced now, on this pairing RPC.
  perform public._hyn_purge_expired_device_codes();

  v_expires := now() + interval '15 minutes';

  -- Salted verifiers cannot enforce plaintext uniqueness with an index. Briefly
  -- serialize code allocation so the verify-before-insert collision check is
  -- authoritative even when two agents start pairing at the same instant.
  perform pg_advisory_xact_lock(482791360);

  loop
    v_try := v_try + 1;
    v_device_code := encode(extensions.gen_random_bytes(32), 'hex');
    v_user_code := public._hyn_user_code();

    if exists (
      select 1
        from public.device_codes d
       where d.user_code_verifier = extensions.crypt(
               v_user_code, d.user_code_verifier
             )
    ) then
      if v_try >= 5 then
        raise exception 'could not allocate a pairing code, try again';
      end if;
      continue;
    end if;

    begin
      insert into public.device_codes (
        user_code_verifier, device_code_hash, hostname, os, agent_version, expires_at
      ) values (
        extensions.crypt(v_user_code, extensions.gen_salt('bf', 10)),
        public._hyn_sha256(v_device_code),
        left(coalesce(p_hostname, ''), 200),
        left(coalesce(p_os, ''), 200),
        left(coalesce(p_agent_version, ''), 50),
        v_expires
      );
      exit;
    exception when unique_violation then
      if v_try >= 5 then
        raise exception 'could not allocate a pairing code, try again';
      end if;
    end;
  end loop;

  return json_build_object(
    'user_code', v_user_code,
    'device_code', v_device_code,
    'expires_at', v_expires,
    'interval', 5
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- device pairing: step 2, the human approves it from a browser
-- ---------------------------------------------------------------------------
-- Returns the pending request's identity so the page can show WHICH host is
-- asking before the user commits. Requires an authenticated session.

create or replace function public.hyn_device_lookup(p_user_code text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  -- Capture the submitted row first so `expired` remains distinguishable from
  -- `not_found`, then purge before any per-code lock is taken.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  return json_build_object(
    'status', 'pending',
    'hostname', v.hostname,
    'os', v.os,
    'agent_version', v.agent_version,
    'requested_at', v.created_at
  );
end;
$$;

create or replace function public.hyn_device_approve(
  p_user_code text,
  p_node_name text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_node_id uuid;
  v_node_token text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  -- Global cleanup always precedes the single-row approval lock. Purge workers
  -- use ordered SKIP LOCKED scans, eliminating cross-row lock cycles.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  v_node_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.nodes (owner, name, hostname, os, agent_version, token_hash)
  values (
    v_uid,
    coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node'),
    v.hostname, v.os, v.agent_version,
    public._hyn_sha256(v_node_token)
  )
  returning id into v_node_id;

  update public.device_codes
     set approved_by = v_uid,
         node_id = v_node_id,
         node_token_hash = public._hyn_sha256(v_node_token)
   where id = v.id;

  -- The plaintext token is handed to the polling server, not to this browser.
  -- Stashing it here (hashed) is what lets the poll succeed exactly once.
  return json_build_object(
    'status', 'approved',
    'node_id', v_node_id,
    'node_name', coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- device pairing: step 3, the server polls until approved
-- ---------------------------------------------------------------------------
-- The node token is released exactly once, then the code is burned. A replayed
-- poll gets 'claimed', which is a hard error on the agent side rather than a
-- second valid credential.

create or replace function public.hyn_device_poll(p_device_code text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_token text;
begin
  select * into v from public.device_codes
   where device_code_hash = public._hyn_sha256(p_device_code);

  -- As with approval, cleanup runs before the target row is locked.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is null then
    return json_build_object('status', 'pending', 'interval', 5);
  end if;
  if v.token_claimed then
    return json_build_object('status', 'claimed');
  end if;

  -- Regenerate a fresh token at claim time and rebind the node to it, so the
  -- value only ever exists in transit to the machine that asked for it.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update public.nodes
     set token_hash = public._hyn_sha256(v_token)
   where id = v.node_id;
  update public.device_codes
     set token_claimed = true, node_token_hash = public._hyn_sha256(v_token)
   where id = v.id;

  return json_build_object(
    'status', 'approved',
    'node_id', v.node_id,
    'node_token', v_token,
    'node_name', (select name from public.nodes where id = v.node_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- ingest
-- ---------------------------------------------------------------------------
-- Called by the agent with its node token. Accepts the same shape that
-- `hyn snapshot --json` already emits, so the agent has no second serialiser.

create or replace function public.hyn_ingest(
  p_node_token text,
  p_payload jsonb
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_ts timestamptz;
  v_alert jsonb;
  v_st jsonb;
  v_written integer := 0;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false;

  if not found then
    raise exception 'invalid node token';
  end if;

  -- A pause with an elapsed deadline resolves itself before the status check, so
  -- a temporary pause really is temporary even if nobody comes back to clear it.
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  -- Distinct messages: the agent backs off quietly on a pause and says so
  -- loudly on a suspension, because one is expected and the other needs a human.
  if v_node.status = 'paused' then
    raise exception 'node paused%', coalesce(' until ' || v_node.paused_until::text, '');
  end if;
  if v_node.status = 'suspended' then
    raise exception 'node suspended: %', coalesce(v_node.status_reason, 'contact your administrator');
  end if;

  v_ts := coalesce((p_payload->>'ts')::timestamptz, now());

  insert into public.metrics (
    node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
    load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
    net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms,
    net_link_mbps, psi_cpu, psi_mem, psi_io, tcp_estab, conntrack_pct, proc_count,
    sensors, payload
  ) values (
    v_node.id, v_ts,
    (p_payload#>>'{cpu,pct}')::numeric,
    (p_payload#>>'{cpu,temp_c}')::numeric,
    (p_payload#>>'{cpu,mhz}')::numeric,
    nullif(p_payload#>>'{cpu,model}', ''),
    (p_payload#>>'{cpu,steal}')::numeric,
    (p_payload#>>'{cpu,iowait}')::numeric,
    (p_payload#>>'{cpu,cores}')::integer,
    (p_payload#>>'{load,0}')::numeric,
    (p_payload#>>'{memory,pct}')::numeric,
    (p_payload#>>'{memory,total}')::bigint,
    (p_payload#>>'{memory,used}')::bigint,
    (p_payload#>>'{memory,swap_used}')::bigint,
    (p_payload#>>'{disk,pct}')::numeric,
    (p_payload->>'uptime_s')::bigint,
    (p_payload#>>'{network,iface}'),
    (p_payload#>>'{network,rx_bps}')::bigint,
    (p_payload#>>'{network,tx_bps}')::bigint,
    (p_payload#>>'{network,retrans_permille}')::numeric,
    (p_payload->>'latency_ms')::numeric,
    (p_payload#>>'{network,link_mbps}')::numeric,
    (p_payload#>>'{psi,cpu}')::numeric,
    (p_payload#>>'{psi,memory}')::numeric,
    (p_payload#>>'{psi,io}')::numeric,
    (p_payload#>>'{network,tcp_estab}')::integer,
    (p_payload#>>'{network,conntrack_pct}')::numeric,
    (p_payload#>>'{processes,count}')::integer,
    p_payload->'sensors',
    p_payload
  )
  on conflict (node_id, ts) do nothing;

  -- A speed test only happens a few times a day, so the agent sends its last
  -- known result on every push. Dedupe on (node, ts) rather than re-inserting.
  v_st := p_payload->'speedtest';
  if v_st is not null and coalesce((v_st->>'ts')::bigint, 0) > 0 then
    insert into public.speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
    values (
      v_node.id,
      to_timestamp((v_st->>'ts')::bigint),
      (v_st->>'down_bps')::bigint,
      (v_st->>'up_bps')::bigint,
      round(coalesce((v_st->>'latency_us')::numeric, 0) / 1000.0, 2),
      nullif(v_st->>'note', '')
    )
    on conflict (node_id, ts) do nothing;
  end if;

  for v_alert in select * from jsonb_array_elements(coalesce(p_payload->'alerts', '[]'::jsonb))
  loop
    insert into public.alert_events (node_id, ts, rule, severity, message, resolved)
    values (
      v_node.id,
      coalesce((v_alert->>'ts')::timestamptz, v_ts),
      v_alert->>'rule',
      case when v_alert->>'severity' in ('info','warn','crit') then v_alert->>'severity' else 'info' end,
      left(coalesce(v_alert->>'message', 'alert'), 500),
      coalesce((v_alert->>'resolved')::boolean, false)
    );
    v_written := v_written + 1;
  end loop;

  update public.nodes
     set last_seen_at = now(),
         agent_version = coalesce(nullif(p_payload->>'agent_version', ''), agent_version),
         hostname = coalesce(nullif(p_payload->>'host', ''), hostname)
   where id = v_node.id;

  -- Retention. The agent's own config decides how long it keeps local history;
  -- this is the server-side cap so a long-lived node cannot grow unbounded.
  delete from public.metrics
   where node_id = v_node.id and ts < now() - interval '30 days';

  return json_build_object('status', 'ok', 'node_id', v_node.id, 'alerts_written', v_written);
end;
$$;

-- ---------------------------------------------------------------------------
-- demo data
-- ---------------------------------------------------------------------------
-- Opt-in only, and clearly flagged. The dashboard shows real data or an honest
-- empty state; this exists so someone evaluating the portal without a server to
-- pair can still see what a populated dashboard looks like.

create or replace function public.hyn_demo_seed()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_node_id uuid;
  i integer;
  v_ts timestamptz;
  v_cpu numeric;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.nodes where owner = v_uid and is_demo = true;

  insert into public.nodes (owner, name, hostname, os, agent_version, is_demo)
  values (v_uid, 'demo-node', 'demo-node', 'Ubuntu 24.04 LTS (demo)', '0.0.0-demo', true)
  returning id into v_node_id;

  for i in 0..287 loop
    v_ts := now() - (i * interval '5 minutes');
    v_cpu := 18 + 22 * abs(sin(i / 26.0)) + (random() * 9);
    insert into public.metrics (
      node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
      load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
      net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms, payload
    ) values (
      v_node_id, v_ts,
      round(v_cpu, 1),
      round((41 + v_cpu * 0.32 + random() * 2)::numeric, 1),
      round((2400 + v_cpu * 14 + random() * 60)::numeric),
      'AMD EPYC 9354 32-Core (demo)',
      round((random() * 2)::numeric, 2),
      round((random() * 4)::numeric, 2),
      8,
      round(((v_cpu / 100.0) * 8 * 0.7)::numeric, 2),
      round((52 + 9 * sin(i / 41.0) + random() * 3)::numeric, 1),
      33285996544, 17301504000, 0,
      round((58 + (i / 288.0) * 3)::numeric, 1),
      1900800 - (i * 300),
      'eth0',
      (620000000 + random() * 260000000)::bigint,
      (180000000 + random() * 90000000)::bigint,
      round((random() * 7)::numeric, 2),
      round((7 + random() * 4)::numeric, 2),
      -- The Highway section of the payload, so the demo dashboard shows the
      -- node panel the way a paired relay would. Same key names as the agent's
      -- `highway` object in lib/cloud.sh; flagged demo like everything else here.
      jsonb_build_object(
        'demo', true,
        'highway', jsonb_build_object(
          'present', 1,
          'tracked', true,
          'health', 'ok',
          'health_why', '2 unit(s) active',
          'version', 'v0.1.75',
          'version_src', 'file',
          'latest', 'v0.1.80',
          'update_available', 1,
          'bin_path', '/usr/local/bin/highway',
          'bin_size', 48234496,
          'bin_mtime', extract(epoch from now() - interval '9 days')::bigint,
          'units_total', 2,
          'units_active', 2,
          'units_failed', 0,
          'units', jsonb_build_array(
            jsonb_build_object(
              'name', 'highway.service', 'state', 'active', 'sub', 'running',
              'restarts', 1, 'memory', (402653184 + random() * 20000000)::bigint,
              'active_s', 1900800 - (i * 300)
            ),
            jsonb_build_object(
              'name', 'nebula.service', 'state', 'active', 'sub', 'running',
              'restarts', 0, 'memory', 18874368,
              'active_s', 1900800 - (i * 300)
            )
          ),
          'pid', 1471,
          'cpu_tenths', (40 + random() * 60)::int,
          'rss', (402653184 + random() * 20000000)::bigint,
          'threads', 19,
          'fds', 48,
          'proc_uptime_s', 1900800 - (i * 300),
          'mesh_iface', 'nebula1',
          'mesh_rx_bps', (900000 + random() * 400000)::bigint,
          'mesh_tx_bps', (700000 + random() * 300000)::bigint,
          'mesh_rx_total', 88000000000::bigint,
          'mesh_tx_total', 44000000000::bigint,
          'mesh_drops', 0,
          'qdisc', 'fq_codel',
          'qdisc_drops', 0,
          'congestion', 'bbr',
          'nft_tables', 3,
          'journal_err_1h', 0,
          'journal_warn_1h', 2,
          'journal_tail', jsonb_build_array(
            'demo: peer handshake retry', 'demo: lighthouse reconnect'
          )
        )
      )
    ) on conflict (node_id, ts) do nothing;
  end loop;

  for i in 0..11 loop
    insert into public.speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
    values (
      v_node_id, now() - (i * interval '6 hours'),
      (720000000 + random() * 180000000)::bigint,
      (330000000 + random() * 120000000)::bigint,
      round((8 + random() * 5)::numeric, 2), 'demo'
    ) on conflict (node_id, ts) do nothing;
  end loop;

  insert into public.alert_events (node_id, ts, rule, severity, message, resolved) values
    (v_node_id, now() - interval '3 hours',  'cpu_temp',  'warn', 'CPU temperature 71C above threshold 70C', true),
    (v_node_id, now() - interval '19 hours', 'disk_pct',  'warn', 'Filesystem / at 86% (projected full in 12 days)', false),
    (v_node_id, now() - interval '2 days',   'unit_failed', 'crit', 'systemd unit highway.service entered failed state', true),
    (v_node_id, now() - interval '4 days',   'report',    'info', 'Daily report delivered', true);

  return json_build_object('status', 'ok', 'node_id', v_node_id);
end;
$$;

create or replace function public.hyn_demo_clear()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  delete from public.nodes where owner = v_uid and is_demo = true;
  get diagnostics v_count = row_count;
  return json_build_object('status', 'ok', 'removed', v_count);
end;
$$;

-- ===========================================================================
-- multi-tenant control plane
-- ===========================================================================
-- Everything above is the single-tenant core: pair a node, push metrics, read
-- them back. Everything below turns that into a managed fleet:
--
--   * the dashboard can manage ordinary monitoring configuration while provider
--     targets and credentials remain root-only on each monitored server;
--   * notification delivery history lives here so clients can review outcomes;
--   * an administrator can see every client and every PC, and pause or suspend
--     either, with every privileged action written to an audit trail.

-- ---------------------------------------------------------------------------
-- profiles and roles
-- ---------------------------------------------------------------------------
-- auth.users is managed by Supabase and cannot carry application columns, so
-- role and account status live alongside it. The email is mirrored here because
-- the admin dashboard has to name a client without reading the auth schema.
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  full_name  text,
  role       text not null default 'user'   check (role in ('user', 'admin')),
  status     text not null default 'active' check (status in ('active', 'suspended')),
  suspended_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_role_idx on public.profiles (role);

-- Every signup gets a profile without the client code having to remember to
-- create one; a missing profile would mean an invisible client in the admin view.
create or replace function public._hyn_on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists hyn_on_auth_user_created on auth.users;
create trigger hyn_on_auth_user_created
  after insert on auth.users
  for each row execute function public._hyn_on_auth_user_created();

-- Backfill, so applying this to a project that already has users does not leave
-- them unmanageable.
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- SECURITY DEFINER and a pinned search_path, because this is called from inside
-- the RLS policies on profiles itself -- a plain query there would recurse.
create or replace function public.hyn_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

-- A suspended client keeps their rows but loses access. Checked separately from
-- is_admin so a suspended admin is simply not an admin.
create or replace function public.hyn_is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and status = 'active'
  );
$$;

alter table public.profiles enable row level security;

drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin on public.profiles
  for select using (id = auth.uid() or public.hyn_is_admin());

-- A client may edit their own display name. Deliberately no policy lets anyone
-- write role or status from a session: those go through the admin RPCs, which
-- record who did it. Column grants below enforce the same thing.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- node lifecycle and server-side configuration
-- ---------------------------------------------------------------------------
alter table public.nodes add column if not exists status text not null default 'active';
alter table public.nodes add column if not exists paused_until timestamptz;
alter table public.nodes add column if not exists status_reason text;
alter table public.nodes add column if not exists config jsonb not null default '{}'::jsonb;
alter table public.nodes add column if not exists last_config_pull_at timestamptz;

-- A node owner can update config through the public PostgREST API, so the
-- database—not the portal form—must define which keys can cross to an agent.
-- Sanitise older rows before adding the constraint. This deliberately drops
-- all keys not exposed by components/account/node-settings.tsx.
create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  e record;
  v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' then return false; end if;
        if v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' then return false; end if;
        if v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'cloud_storage' then
        if v not in ('cloud','local') then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'cloud_checkin_min' then
        if v !~ '^[1-9][0-9]{0,2}$' then return false; end if;
        if v::integer > 60 then return false; end if;
      when e.key = 'heartbeat_sec' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer < 5 or v::integer > 3600 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'dashboard_view' then
        if v not in ('dash', 'simple') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;

update public.nodes n
   set config = coalesce((
     select jsonb_object_agg(e.key, e.value)
       from jsonb_each(
         case when jsonb_typeof(n.config) = 'object' then n.config else '{}'::jsonb end
       ) as e
      where e.key = any (array[
        'alert_mem_pct', 'alert_disk_pct', 'alert_temp_c',
        'alert_load_per_core', 'alert_latency_ms', 'alert_min_severity',
        'alert_repeat_hours', 'report_at', 'notify_max_per_day', 'cloud_push_min', 'cloud_storage',
        'auto_update', 'dashboard_view'
      ]::text[])
        and public._hyn_portal_config_valid(jsonb_build_object(e.key, e.value))
   ), '{}'::jsonb);

alter table public.nodes drop constraint if exists nodes_config_portal_keys_check;
alter table public.nodes add constraint nodes_config_portal_keys_check check (
  public._hyn_portal_config_valid(config)
);

-- Managed defaults are stored on the node as well as in the agent so old and
-- newly installed CLIs receive the same policy on their next one-minute config
-- check. Existing explicit choices win over these defaults.
alter table public.nodes alter column config
  set default '{"auto_update":"install","cloud_push_min":"10"}'::jsonb;
update public.nodes
   set config = '{"auto_update":"install","cloud_push_min":"10"}'::jsonb || config
 where not (config @> '{"auto_update":"install","cloud_push_min":"10"}'::jsonb);

do $$ begin
  alter table public.nodes add constraint nodes_status_check
    check (status in ('active', 'paused', 'suspended'));
exception when duplicate_object then null; end $$;

create index if not exists nodes_status_idx on public.nodes (status);

-- Extra sampled columns for the richer agent payload. Kept as real columns
-- rather than jsonb accessors because these are charted over 24h windows.
alter table public.metrics add column if not exists net_link_mbps numeric;
alter table public.metrics add column if not exists psi_cpu      numeric;
alter table public.metrics add column if not exists psi_mem      numeric;
alter table public.metrics add column if not exists psi_io       numeric;
alter table public.metrics add column if not exists tcp_estab    integer;
alter table public.metrics add column if not exists conntrack_pct numeric;
alter table public.metrics add column if not exists proc_count   integer;
alter table public.metrics add column if not exists sensors      jsonb;

-- ---------------------------------------------------------------------------
-- notification delivery log
-- ---------------------------------------------------------------------------
-- "How many emails have come, and all the logs" -- reported by the agent after
-- each attempt, so the dashboard shows what was actually delivered rather than
-- what was theoretically configured.
create table if not exists public.notification_log (
  id        bigserial primary key,
  node_id   uuid not null references public.nodes (id) on delete cascade,
  owner     uuid not null references auth.users (id) on delete cascade,
  ts        timestamptz not null default now(),
  kind      text not null,
  target    text,
  severity  text not null default 'info' check (severity in ('info', 'warn', 'crit')),
  subject   text,
  status    text not null check (status in ('sent', 'failed', 'skipped')),
  error     text,
  category  text not null default 'alert' check (category in ('alert', 'report', 'test', 'other'))
);

create index if not exists notification_log_owner_ts_idx on public.notification_log (owner, ts desc);
create index if not exists notification_log_node_ts_idx on public.notification_log (node_id, ts desc);

alter table public.notification_log enable row level security;

drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log
  for select using (owner = auth.uid() or public.hyn_is_admin());

-- ---------------------------------------------------------------------------
-- admin audit
-- ---------------------------------------------------------------------------
-- Pausing someone's monitoring is exactly the kind of action that needs to be
-- attributable after the fact.
create table if not exists public.admin_audit (
  id          bigserial primary key,
  ts          timestamptz not null default now(),
  actor       uuid references auth.users (id) on delete set null,
  actor_email text,
  action      text not null,
  target_user uuid references auth.users (id) on delete set null,
  target_node uuid references public.nodes (id) on delete set null,
  detail      jsonb not null default '{}'::jsonb
);

create index if not exists admin_audit_ts_idx on public.admin_audit (ts desc);

alter table public.admin_audit enable row level security;

-- Admins read it; nobody writes it from a session (only the RPCs do).
drop policy if exists admin_audit_select_admin on public.admin_audit;
create policy admin_audit_select_admin on public.admin_audit
  for select using (public.hyn_is_admin());

-- Non-secret presentation wrappers for the HTML produced by each agent. The
-- provider credential and delivery destination remain local to the monitored
-- server; this table contains only the markup an administrator wants around
-- the generated alert or report. {{content}} is mandatory so a template can
-- never silently discard the incident details it is supposed to deliver.
create table if not exists public.notification_templates (
  template_key  text primary key check (template_key in ('alert', 'report', 'system')),
  name          text not null,
  description   text not null,
  html_template text not null check (
    position('{{content}}' in html_template) > 0
    and octet_length(html_template) <= 100000
  ),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null
);

alter table public.notification_templates
  drop constraint if exists notification_templates_template_key_check;
alter table public.notification_templates
  add constraint notification_templates_template_key_check
  check (template_key in ('alert', 'report', 'system'));

insert into public.notification_templates (template_key, name, description, html_template)
values
  ('alert', 'Incident alert', 'Wraps new, ongoing, and resolved alert digests.', '{{content}}'),
  ('report', 'Daily health digest', 'Wraps the scheduled 24-hour performance digest.', '{{content}}'),
  ('system', 'System information', 'Wraps the scheduled hardware, software, and service inventory.', '{{content}}')
on conflict (template_key) do nothing;

alter table public.notification_templates enable row level security;
revoke all on public.notification_templates from anon, authenticated;

-- Customer-managed schedules for cloud-delivered email. Provider credentials
-- are deployment secrets and never appear here.
create table if not exists public.email_preferences (
  node_id                uuid primary key references public.nodes (id) on delete cascade,
  recipient              text not null check (recipient ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  timezone               text not null default 'UTC' check (octet_length(timezone) between 1 and 80),
  incident_enabled       boolean not null default true,
  daily_enabled          boolean not null default true,
  daily_at               time not null default '08:00',
  system_enabled         boolean not null default true,
  system_at              time not null default '09:00',
  last_daily_local_date  date,
  last_system_local_date date,
  last_alert_id          bigint not null default 0,
  updated_at             timestamptz not null default now()
);

alter table public.email_preferences enable row level security;
drop policy if exists email_preferences_select_own on public.email_preferences;
create policy email_preferences_select_own on public.email_preferences
  for select using (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));
drop policy if exists email_preferences_insert_own on public.email_preferences;
create policy email_preferences_insert_own on public.email_preferences
  for insert with check (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));
drop policy if exists email_preferences_update_own on public.email_preferences;
create policy email_preferences_update_own on public.email_preferences
  for update using (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()))
  with check (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));

create or replace function public._hyn_create_email_preferences()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_demo = false then
    insert into public.email_preferences (node_id, recipient)
      select new.id, p.email from public.profiles p
       where p.id = new.owner and p.email is not null
    on conflict (node_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists hyn_node_email_preferences on public.nodes;
create trigger hyn_node_email_preferences after insert on public.nodes
  for each row execute function public._hyn_create_email_preferences();

insert into public.email_preferences (node_id, recipient)
select n.id, p.email from public.nodes n join public.profiles p on p.id = n.owner
 where n.is_demo = false and p.email is not null
on conflict (node_id) do nothing;

-- Prevent overlapping cron invocations from sending a message twice. Browser
-- sessions cannot access this internal ledger.
create table if not exists public.cloud_email_dispatches (
  idempotency_key text primary key,
  node_id         uuid not null references public.nodes (id) on delete cascade,
  kind            text not null check (kind in ('alert', 'report', 'system')),
  created_at      timestamptz not null default now(),
  provider_id     text
);
alter table public.cloud_email_dispatches enable row level security;
revoke all on public.cloud_email_dispatches from anon, authenticated;

-- The agent gateway uses the same credential that just completed ingest to
-- claim one first-telemetry email. This avoids requiring a service-role key in
-- the public agent route while keeping recipient data scoped to that node.
create or replace function public.hyn_claim_first_telemetry_email(
  p_node_token text,
  p_public_ip text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_recipient text;
  v_system_enabled boolean;
  v_payload jsonb;
  v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false;
  if not found then raise exception 'invalid node token'; end if;

  select recipient, system_enabled into v_recipient, v_system_enabled
    from public.email_preferences where node_id = v_node.id;
  if not found or not coalesce(v_system_enabled, false) then
    return json_build_object('status', 'skip', 'reason', 'system email disabled');
  end if;

  select payload into v_payload from public.metrics
   where node_id = v_node.id order by ts desc limit 1;
  if not found then
    return json_build_object('status', 'skip', 'reason', 'awaiting telemetry');
  end if;
  v_payload := coalesce(v_payload, '{}'::jsonb);
  if p_public_ip is not null and octet_length(p_public_ip) <= 64
     and p_public_ip ~ '^[0-9A-Fa-f:.]+$' then
    v_payload := jsonb_set(
      v_payload,
      '{network}',
      coalesce(v_payload->'network', '{}'::jsonb) || jsonb_build_object('public_ip', p_public_ip),
      true
    );
  end if;

  v_key := 'first-system:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system')
  on conflict (idempotency_key) do nothing;
  if not found then
    return json_build_object('status', 'skip', 'reason', 'already sent');
  end if;

  return json_build_object(
    'status', 'send',
    'idempotency_key', v_key,
    'node_id', v_node.id,
    'node_name', v_node.name,
    'hostname', v_node.hostname,
    'os', v_node.os,
    'agent_version', v_node.agent_version,
    'last_seen_at', v_node.last_seen_at,
    'recipient', v_recipient,
    'payload', v_payload
  );
end;
$$;

create or replace function public.hyn_complete_first_telemetry_email(
  p_node_token text,
  p_provider_id text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_node public.nodes; v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token) and revoked = false;
  if not found then raise exception 'invalid node token'; end if;
  v_key := 'first-system:' || v_node.id::text;
  update public.cloud_email_dispatches
     set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = v_key and node_id = v_node.id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_first_telemetry_email(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_node public.nodes; v_key text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token) and revoked = false;
  if not found then raise exception 'invalid node token'; end if;
  v_key := 'first-system:' || v_node.id::text;
  delete from public.cloud_email_dispatches
   where idempotency_key = v_key and node_id = v_node.id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_node from public.nodes
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false;
  if not found then raise exception 'node not found'; end if;
  select recipient into v_recipient from public.email_preferences where node_id = v_node.id;
  if not found then return json_build_object('status', 'skip', 'reason', 'email preference missing'); end if;
  v_key := 'device-linked:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system') on conflict (idempotency_key) do nothing;
  if not found then return json_build_object('status', 'skip', 'reason', 'already sent'); end if;
  return json_build_object(
    'status', 'send', 'node_id', v_node.id, 'node_name', v_node.name,
    'hostname', v_node.hostname, 'os', v_node.os, 'agent_version', v_node.agent_version,
    'recipient', v_recipient, 'linked_at', v_node.created_at
  );
end;
$$;

create or replace function public.hyn_complete_device_linked_email(p_node_id uuid, p_provider_id text default null)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text
     and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

-- ---------------------------------------------------------------------------
-- cross-tenant read access for administrators
-- ---------------------------------------------------------------------------
-- Replaces the owner-only policies with owner-or-admin. A client's reach is
-- unchanged; an admin can see the whole fleet, which is the requirement.
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes
  for select using (owner = auth.uid() or public.hyn_is_admin());

drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics
  for select using (
    public.hyn_is_admin() or exists (
      select 1 from public.nodes n where n.id = metrics.node_id and n.owner = auth.uid()
    )
  );

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests
  for select using (
    public.hyn_is_admin() or exists (
      select 1 from public.nodes n where n.id = speedtests.node_id and n.owner = auth.uid()
    )
  );

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events
  for select using (
    public.hyn_is_admin() or exists (
      select 1 from public.nodes n where n.id = alert_events.node_id and n.owner = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- portal-to-agent maintenance commands
-- ---------------------------------------------------------------------------
create or replace function public.hyn_request_node_update(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_command public.node_commands;
  v_created boolean := false;
begin
  if auth.uid() is null or not public.hyn_is_active() then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.nodes
     where id = p_node_id and owner = auth.uid() and revoked = false
       and is_demo = false and status = 'active'
  ) then
    raise exception 'active node not found';
  end if;

  select * into v_command
    from public.node_commands
   where node_id = p_node_id and command = 'update'
     and status in ('queued', 'running')
   order by requested_at desc
   limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command)
    values (p_node_id, auth.uid(), 'update')
    returning * into v_command;
    v_created := true;
  end if;

  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version,
    'result_version', v_command.result_version,
    'requested_at', v_command.requested_at,
    'started_at', v_command.started_at,
    'finished_at', v_command.finished_at,
    'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_claim_node_command(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;

  with candidate as (
    select id from public.node_commands
     where node_id = v_node.id and command = 'update'
       and (
         status = 'queued'
         or (status = 'running' and coalesce(lease_expires_at, '-infinity') <= now())
       )
     order by requested_at
     for update skip locked
     limit 1
  )
  update public.node_commands c
     set status = 'running', stage = 'accepted',
         message = 'Machine accepted the update request',
         started_at = coalesce(c.started_at, now()), updated_at = now(),
         lease_expires_at = now() + interval '20 minutes'
    from candidate
   where c.id = candidate.id
  returning c.* into v_command;

  if not found then return json_build_object('status', 'idle'); end if;
  return json_build_object(
    'status', 'command', 'id', v_command.id,
    'action', v_command.command, 'stage', v_command.stage
  );
end;
$$;

create or replace function public.hyn_report_node_command(
  p_node_token text,
  p_command_id uuid,
  p_status text,
  p_stage text,
  p_message text,
  p_target_version text default null,
  p_result_version text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false;
  if not found then raise exception 'invalid node token'; end if;
  if p_status not in ('running', 'succeeded', 'failed') then
    raise exception 'invalid command status';
  end if;
  if p_stage not in ('accepted', 'checking', 'installing', 'restarting',
                     'verifying', 'completed', 'failed') then
    raise exception 'invalid command stage';
  end if;
  if octet_length(coalesce(p_message, '')) > 500 then
    raise exception 'command message is too long';
  end if;
  if octet_length(coalesce(p_target_version, '')) > 64
     or octet_length(coalesce(p_result_version, '')) > 64 then
    raise exception 'command version is too long';
  end if;

  update public.node_commands
     set status = p_status, stage = p_stage,
         message = coalesce(nullif(trim(p_message), ''), p_stage),
         target_version = coalesce(nullif(p_target_version, ''), target_version),
         result_version = coalesce(nullif(p_result_version, ''), result_version),
         updated_at = now(),
         lease_expires_at = case when p_status = 'running'
                                 then now() + interval '20 minutes' else null end,
         finished_at = case when p_status in ('succeeded', 'failed')
                            then now() else finished_at end
   where id = p_command_id and node_id = v_node.id and status = 'running'
  returning * into v_command;
  if not found then raise exception 'active command not found'; end if;

  return json_build_object(
    'status', v_command.status, 'stage', v_command.stage,
    'updated_at', v_command.updated_at
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- agent: pull configuration
-- ---------------------------------------------------------------------------
-- The whole point of the thin agent: the box asks the API what it should be
-- doing rather than being told by a file someone edited over ssh months ago.
-- Authenticated by node token, so a node can only ever fetch its own settings.
create or replace function public.hyn_fetch_config(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_alert_template text;
  v_report_template text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token);

  if not found then
    raise exception 'invalid node token';
  end if;
  if v_node.revoked then
    raise exception 'node revoked';
  end if;

  -- A temporary pause that has elapsed resolves itself, so nobody has to
  -- remember to switch monitoring back on.
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  update public.nodes set last_config_pull_at = now() where id = v_node.id;

  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_alert_template
    from public.notification_templates t
   where t.template_key = 'alert';
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_report_template
    from public.notification_templates t
   where t.template_key = 'report';

  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_name', v_node.name,
    'node_status', v_node.status,
    'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason,
    'config', v_node.config,
    'alert_template_b64', coalesce(v_alert_template, ''),
    'report_template_b64', coalesce(v_report_template, '')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- agent: report notification deliveries
-- ---------------------------------------------------------------------------
-- So the dashboard can answer "how many alerts went out, and did any fail?"
create or replace function public.hyn_report_notification(
  p_node_token text,
  p_events jsonb
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_event jsonb;
  v_n integer := 0;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false;

  if not found then
    raise exception 'invalid node token';
  end if;

  for v_event in select * from jsonb_array_elements(coalesce(p_events, '[]'::jsonb))
  loop
    insert into public.notification_log
      (node_id, owner, ts, kind, target, severity, subject, status, error, category)
    values (
      v_node.id, v_node.owner,
      coalesce((v_event->>'ts')::timestamptz, now()),
      left(coalesce(v_event->>'kind', 'unknown'), 40),
      left(nullif(v_event->>'target', ''), 200),
      case when v_event->>'severity' in ('info','warn','crit') then v_event->>'severity' else 'info' end,
      left(nullif(v_event->>'subject', ''), 300),
      case when v_event->>'status' in ('sent','failed','skipped') then v_event->>'status' else 'failed' end,
      left(nullif(v_event->>'error', ''), 500),
      case when v_event->>'category' in ('alert','report','test','other') then v_event->>'category' else 'other' end
    );
    v_n := v_n + 1;
  end loop;

  return json_build_object('status', 'ok', 'written', v_n);
end;
$$;

-- ---------------------------------------------------------------------------
-- administration
-- ---------------------------------------------------------------------------
-- Every function here refuses a non-admin and records what it did. The checks
-- live in the database, not only in the UI, because the UI is not a security
-- boundary -- anyone can call these RPCs with the public anon key.

create or replace function public._hyn_require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.hyn_is_admin() then
    raise exception 'administrator role required';
  end if;
  return v_uid;
end;
$$;

create or replace function public._hyn_audit(
  p_action text, p_target_user uuid, p_target_node uuid, p_detail jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_audit (actor, actor_email, action, target_user, target_node, detail)
  values (
    auth.uid(),
    (select email from public.profiles where id = auth.uid()),
    p_action, p_target_user, p_target_node, coalesce(p_detail, '{}'::jsonb)
  );
end;
$$;

-- Fleet summary for the top of the admin dashboard.
create or replace function public.hyn_admin_overview()
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._hyn_require_admin();
  return json_build_object(
    'clients_total',     (select count(*) from public.profiles),
    'clients_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'admins',            (select count(*) from public.profiles where role = 'admin'),
    'nodes_total',       (select count(*) from public.nodes where is_demo = false),
    'nodes_active',      (select count(*) from public.nodes where status = 'active' and revoked = false and is_demo = false),
    'nodes_paused',      (select count(*) from public.nodes where status = 'paused' and is_demo = false),
    'nodes_suspended',   (select count(*) from public.nodes where status = 'suspended' and is_demo = false),
    'nodes_revoked',     (select count(*) from public.nodes where revoked = true),
    -- "Stale" is the closest a central server can get to "that box is in
    -- trouble": it stopped checking in. It cannot know the machine is down, only
    -- that it went quiet.
    'nodes_stale',       (select count(*) from public.nodes
                           where is_demo = false and revoked = false and status = 'active'
                             and (last_seen_at is null or last_seen_at < now() - make_interval(
                               mins => greatest(15, 3 * case
                                 when config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
                                   then (config->>'cloud_push_min')::integer
                                 else 10 end
                             )))),
    'alerts_open',       (select count(*) from public.alert_events where resolved = false
                            and ts > now() - interval '7 days'),
    'notifications_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours'),
    'notifications_failed_24h', (select count(*) from public.notification_log
                                  where ts > now() - interval '24 hours' and status = 'failed'),
    'metrics_24h',       (select count(*) from public.metrics where ts > now() - interval '24 hours')
  );
end;
$$;

-- Every PC in the fleet, with the client it belongs to and enough health for a
-- single table view.
create or replace function public.hyn_admin_nodes()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.last_seen_at desc nulls last), '[]'::json)
    into v
    from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status,
             p.role as owner_role,
             (select count(*) from public.notification_log l
               where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l
               where l.node_id = n.id and l.ts > now() - interval '24 hours'
                 and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a
               where a.node_id = n.id and a.resolved = false
                 and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id
               order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id
               order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id
               order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id
               order by m.ts desc limit 1) as last_disk_pct
        from public.nodes n
        left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

-- Every client, with their fleet size and notification volume.
create or replace function public.hyn_admin_clients()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json)
    into v
    from (
      select p.id, p.email, p.full_name, p.role, p.status, p.suspended_reason, p.created_at,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false) as nodes,
             (select count(*) from public.nodes n where n.owner = p.id and n.status = 'active'
                and n.revoked = false and n.is_demo = false) as nodes_active,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days') as notifications_30d,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days' and l.status = 'failed') as notifications_failed_30d,
             (select max(n.last_seen_at) from public.nodes n where n.owner = p.id) as last_seen_at
        from public.profiles p
    ) x;
  return v;
end;
$$;

-- Pause, suspend or reinstate one PC.
--
--   active     normal operation
--   paused     temporarily stop accepting data (maintenance, a noisy box)
--   suspended  stop accepting data until an administrator says otherwise
--
-- p_minutes makes a pause self-expiring, which is what "temporary" should mean:
-- monitoring you forgot to switch back on is worse than no monitoring, because
-- you believe you still have it.
create or replace function public.hyn_admin_set_node_status(
  p_node_id uuid,
  p_status text,
  p_minutes integer default null,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_until timestamptz;
begin
  perform public._hyn_require_admin();
  if p_status not in ('active', 'paused', 'suspended') then
    raise exception 'unknown status: %', p_status;
  end if;

  v_until := case
    when p_status = 'paused' and coalesce(p_minutes, 0) > 0
      then now() + make_interval(mins => p_minutes)
    else null
  end;

  update public.nodes
     set status = p_status,
         paused_until = v_until,
         status_reason = case when p_status = 'active' then null else left(p_reason, 300) end
   where id = p_node_id;

  if not found then
    raise exception 'no such node';
  end if;

  perform public._hyn_audit('node.status.' || p_status, null, p_node_id,
    jsonb_build_object('minutes', p_minutes, 'reason', p_reason, 'until', v_until));

  return json_build_object('status', 'ok', 'node_status', p_status, 'paused_until', v_until);
end;
$$;

-- Revoking a node's credential is separate from pausing it: pause is reversible
-- with no work on the box, revoke means re-pairing it.
create or replace function public.hyn_admin_set_node_revoked(
  p_node_id uuid,
  p_revoked boolean,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._hyn_require_admin();
  update public.nodes
     set revoked = p_revoked,
         status_reason = case when p_revoked then left(p_reason, 300) else status_reason end
   where id = p_node_id;
  if not found then
    raise exception 'no such node';
  end if;
  perform public._hyn_audit(case when p_revoked then 'node.revoke' else 'node.unrevoke' end,
    null, p_node_id, jsonb_build_object('reason', p_reason));
  return json_build_object('status', 'ok', 'revoked', p_revoked);
end;
$$;

-- An administrator sets the same managed settings a client can set for their
-- own node (thresholds, schedule, update policy, dashboard view) -- the RPC a
-- client calls is owner-scoped and refuses everyone else, so this is a
-- deliberate second entry point rather than a bypass of it. It is restricted
-- to the exact same allowlist for the exact same reason: an admin console is
-- not a bigger trust boundary than the account page, just a different caller.
create or replace function public.hyn_admin_set_node_config(
  p_node_id uuid,
  p_config jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_config jsonb;
begin
  perform public._hyn_require_admin();
  if not public._hyn_portal_config_valid(p_config) then
    raise exception 'invalid portal configuration';
  end if;
  update public.nodes set config = p_config
   where id = p_node_id and revoked = false and is_demo = false
  returning config into v_config;
  if not found then
    raise exception 'no such node';
  end if;
  perform public._hyn_audit('node.config', null, p_node_id, p_config);
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

-- Suspend or reinstate a whole client account.
create or replace function public.hyn_admin_set_user_status(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public._hyn_require_admin();
  if p_status not in ('active', 'suspended') then
    raise exception 'unknown status: %', p_status;
  end if;
  -- Locking yourself out is never the intent.
  if p_user_id = v_actor and p_status = 'suspended' then
    raise exception 'refusing to suspend your own account';
  end if;

  update public.profiles
     set status = p_status,
         suspended_reason = case when p_status = 'suspended' then left(p_reason, 300) else null end,
         updated_at = now()
   where id = p_user_id;
  if not found then
    raise exception 'no such client';
  end if;

  -- Suspending a client suspends their fleet, otherwise their boxes keep
  -- reporting into an account nobody is allowed to look at.
  if p_status = 'suspended' then
    update public.nodes set status = 'suspended',
           status_reason = 'account suspended'
     where owner = p_user_id and status <> 'suspended';
  else
    update public.nodes set status = 'active', status_reason = null, paused_until = null
     where owner = p_user_id and status = 'suspended'
       and status_reason = 'account suspended';
  end if;

  perform public._hyn_audit('client.status.' || p_status, p_user_id, null,
    jsonb_build_object('reason', p_reason));

  return json_build_object('status', 'ok', 'client_status', p_status);
end;
$$;

create or replace function public.hyn_admin_set_role(
  p_user_id uuid,
  p_role text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid; v_admins integer;
begin
  v_actor := public._hyn_require_admin();
  if p_role not in ('user', 'admin') then
    raise exception 'unknown role: %', p_role;
  end if;

  -- Never leave the installation with no administrator.
  if p_role = 'user' then
    select count(*) into v_admins from public.profiles where role = 'admin' and status = 'active';
    if v_admins <= 1 and exists (select 1 from public.profiles where id = p_user_id and role = 'admin') then
      raise exception 'refusing to remove the last administrator';
    end if;
  end if;

  update public.profiles set role = p_role, updated_at = now() where id = p_user_id;
  if not found then
    raise exception 'no such client';
  end if;

  perform public._hyn_audit('client.role.' || p_role, p_user_id, null, '{}'::jsonb);
  return json_build_object('status', 'ok', 'role', p_role);
end;
$$;

-- Notification history across the fleet, for the admin log view.
create or replace function public.hyn_admin_notifications(p_limit integer default 200)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select l.id, l.ts, l.kind, l.target, l.severity, l.subject, l.status, l.error, l.category,
             n.name as node_name, p.email as owner_email
        from public.notification_log l
        left join public.nodes n on n.id = l.node_id
        left join public.profiles p on p.id = l.owner
       order by l.ts desc
       limit least(greatest(coalesce(p_limit, 200), 1), 1000)
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_audit(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select a.id, a.ts, a.actor_email, a.action, a.detail,
             a.target_user, a.target_node,
             n.name as target_node_name,
             p.email as target_user_email
        from public.admin_audit a
        left join public.nodes n on n.id = a.target_node
        left join public.profiles p on p.id = a.target_user
       order by a.ts desc
       limit least(greatest(coalesce(p_limit, 100), 1), 1000)
    ) x;
  return v;
end;
$$;

-- List and edit the two globally supported email wrappers. Browser sessions do
-- not receive table privileges; both operations pass through admin-checked
-- SECURITY DEFINER functions and every write is audited.
create or replace function public.hyn_admin_templates()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.template_key), '[]'::json)
    into v
    from (
      select t.template_key, t.name, t.description, t.html_template, t.updated_at,
             p.email as updated_by_email
        from public.notification_templates t
        left join public.profiles p on p.id = t.updated_by
       order by t.template_key
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_save_template(
  p_template_key text,
  p_html_template text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public._hyn_require_admin();
  if p_template_key not in ('alert', 'report', 'system') then
    raise exception 'unknown notification template: %', p_template_key;
  end if;
  if position('{{content}}' in coalesce(p_html_template, '')) = 0 then
    raise exception 'template must include {{content}}';
  end if;
  if octet_length(p_html_template) > 100000 then
    raise exception 'template exceeds 100 KB';
  end if;
  if p_html_template ~* '<[[:space:]]*(script|iframe|object|embed|form)([[:space:]>])'
     or p_html_template ~* '[[:space:]]on[a-z]+[[:space:]]*=' then
    raise exception 'template contains active HTML that is not allowed in email';
  end if;

  update public.notification_templates
     set html_template = p_html_template,
         updated_at = now(),
         updated_by = v_actor
   where template_key = p_template_key;
  if not found then
    raise exception 'notification template is not installed: %', p_template_key;
  end if;

  perform public._hyn_audit('notification_template.update', null, null,
    jsonb_build_object('template_key', p_template_key, 'bytes', octet_length(p_html_template)));
  return json_build_object('status', 'ok', 'template_key', p_template_key);
end;
$$;

-- ---------------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------------
-- Least privilege: the anon role (what the headless agent uses) may call only
-- the functions the pairing flow, config pull and reporting need. Everything
-- else requires a logged-in session.

revoke all on function public.hyn_device_start(text, text, text) from public;
revoke all on function public.hyn_device_poll(text) from public;
revoke all on function public.hyn_ingest(text, jsonb) from public;
revoke all on function public.hyn_device_lookup(text) from public;
revoke all on function public.hyn_device_approve(text, text) from public;
revoke all on function public.hyn_demo_seed() from public;
revoke all on function public.hyn_demo_clear() from public;

grant execute on function public.hyn_device_start(text, text, text) to anon, authenticated;
grant execute on function public.hyn_device_poll(text) to anon, authenticated;
grant execute on function public.hyn_ingest(text, jsonb) to anon, authenticated;

grant execute on function public.hyn_device_lookup(text) to authenticated;
grant execute on function public.hyn_device_approve(text, text) to authenticated;
grant execute on function public.hyn_demo_seed() to authenticated;
grant execute on function public.hyn_demo_clear() to authenticated;

-- Agent-facing, authenticated by node token rather than by session.
revoke all on function public.hyn_fetch_config(text) from public;
revoke all on function public.hyn_report_notification(text, jsonb) from public;
revoke all on function public.hyn_claim_node_command(text) from public;
revoke all on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) from public;
revoke all on function public.hyn_request_node_update(uuid) from public;
revoke all on function public.hyn_claim_first_telemetry_email(text, text) from public;
revoke all on function public.hyn_complete_first_telemetry_email(text, text) from public;
revoke all on function public.hyn_release_first_telemetry_email(text) from public;
revoke all on function public.hyn_claim_device_linked_email(uuid) from public;
revoke all on function public.hyn_complete_device_linked_email(uuid, text) from public;
revoke all on function public.hyn_release_device_linked_email(uuid) from public;
grant execute on function public.hyn_fetch_config(text) to anon, authenticated;
grant execute on function public.hyn_report_notification(text, jsonb) to anon, authenticated;
grant execute on function public.hyn_claim_node_command(text) to anon, authenticated;
grant execute on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) to anon, authenticated;
grant execute on function public.hyn_request_node_update(uuid) to authenticated;
grant execute on function public.hyn_claim_first_telemetry_email(text, text) to anon, authenticated;
grant execute on function public.hyn_complete_first_telemetry_email(text, text) to anon, authenticated;
grant execute on function public.hyn_release_first_telemetry_email(text) to anon, authenticated;
grant execute on function public.hyn_claim_device_linked_email(uuid) to authenticated;
grant execute on function public.hyn_complete_device_linked_email(uuid, text) to authenticated;
grant execute on function public.hyn_release_device_linked_email(uuid) to authenticated;

-- Session-facing helpers.
revoke all on function public.hyn_is_admin() from public;
revoke all on function public.hyn_is_active() from public;
grant execute on function public.hyn_is_admin() to authenticated;
grant execute on function public.hyn_is_active() to authenticated;

-- Administration. Granted to `authenticated` because that is the only role that
-- can have an identity at all; each function then refuses a caller whose profile
-- is not an active admin. The database is the boundary, not the UI.
revoke all on function public.hyn_admin_overview() from public;
revoke all on function public.hyn_admin_nodes() from public;
revoke all on function public.hyn_admin_clients() from public;
revoke all on function public.hyn_admin_notifications(integer) from public;
revoke all on function public.hyn_admin_audit(integer) from public;
revoke all on function public.hyn_admin_templates() from public;
revoke all on function public.hyn_admin_save_template(text, text) from public;
revoke all on function public.hyn_admin_set_node_status(uuid, text, integer, text) from public;
revoke all on function public.hyn_admin_set_node_revoked(uuid, boolean, text) from public;
revoke all on function public.hyn_admin_set_node_config(uuid, jsonb) from public;
revoke all on function public.hyn_admin_set_user_status(uuid, text, text) from public;
revoke all on function public.hyn_admin_set_role(uuid, text) from public;

grant execute on function public.hyn_admin_overview() to authenticated;
grant execute on function public.hyn_admin_nodes() to authenticated;
grant execute on function public.hyn_admin_clients() to authenticated;
grant execute on function public.hyn_admin_notifications(integer) to authenticated;
grant execute on function public.hyn_admin_audit(integer) to authenticated;
grant execute on function public.hyn_admin_templates() to authenticated;
grant execute on function public.hyn_admin_save_template(text, text) to authenticated;
grant execute on function public.hyn_admin_set_node_status(uuid, text, integer, text) to authenticated;
grant execute on function public.hyn_admin_set_node_revoked(uuid, boolean, text) to authenticated;
grant execute on function public.hyn_admin_set_node_config(uuid, jsonb) to authenticated;
grant execute on function public.hyn_admin_set_user_status(uuid, text, text) to authenticated;
grant execute on function public.hyn_admin_set_role(uuid, text) to authenticated;

-- These are internals of the functions above, not an API.
revoke all on function public._hyn_require_admin() from public;
revoke all on function public._hyn_audit(text, uuid, uuid, jsonb) from public;

-- The agent talks to the database exclusively through hyn_ingest, so the anon
-- role needs no table privileges at all.
revoke all on public.nodes        from anon;
revoke all on public.metrics      from anon;
revoke all on public.speedtests   from anon;
revoke all on public.alert_events from anon;
revoke all on public.device_codes from anon, authenticated;
revoke all on public.node_commands from anon, authenticated;

-- Table privileges for signed-in users are granted explicitly rather than
-- inherited from the project's default privileges, so this schema works on a
-- fresh or a hardened project without a surprise "permission denied for table
-- nodes" on the first dashboard load. RLS above is what limits WHICH rows.
--
-- nodes is granted by COLUMN so that token_hash is not one of them. It is only a
-- SHA-256 verifier, not the token, so reading it does not let anyone write
-- telemetry — but it is still one half of a credential, there is no page that
-- needs it, and a value the browser never receives cannot leak from the browser.
-- Note this means `select *` on nodes fails for a session; the portal selects an
-- explicit column list (see NODE_COLUMNS in web-portal/lib/types.ts).
revoke select on public.nodes from authenticated;
grant select (id, owner, name, hostname, os, agent_version, is_demo, revoked,
              created_at, last_seen_at, status, paused_until, status_reason,
              config, last_config_pull_at)
  on public.nodes to authenticated;
grant select on public.metrics      to authenticated;
grant select on public.speedtests   to authenticated;
grant select on public.alert_events to authenticated;
grant select on public.node_commands to authenticated;

-- Renaming a node and revoking one are browser actions; inserting telemetry is
-- not, which is why there is no insert grant here for any of the data tables.
grant update (name, revoked) on public.nodes to authenticated;
grant delete on public.nodes to authenticated;

-- The client's own settings for a node are edited in the dashboard.
grant update (config) on public.nodes to authenticated;

grant select on public.profiles          to authenticated;
grant select on public.notification_log  to authenticated;
grant select on public.admin_audit       to authenticated;
grant select, insert, update, delete on public.email_preferences to authenticated;

-- A client may edit their display name only. role and status are deliberately
-- absent: changing those goes through the admin RPCs so it lands in the audit
-- trail, and a column grant is a harder guarantee than a policy alone.
grant update (full_name) on public.profiles to authenticated;

-- Sequences behind the bigserial keys, needed for the inserts granted above.
grant usage, select on all sequences in schema public to authenticated;

-- Promote an existing client to administrator by email, for the "add another
-- admin" action in the admin panel. Only reachable by an existing admin (via
-- _hyn_require_admin). Distinct from hyn_admin_set_role: this one takes an
-- email because an admin adding a colleague knows their address, not their
-- internal id. If nobody has signed up with that email yet there is no
-- profile row to promote -- returned as 'not_found' rather than an error, so
-- the UI can say "ask them to sign in once first" instead of a stack trace.
create or replace function public.hyn_admin_promote_by_email(p_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  perform public._hyn_require_admin();

  select id into v_target from public.profiles where lower(email) = lower(trim(p_email));
  if v_target is null then
    return json_build_object('status', 'not_found');
  end if;

  update public.profiles set role = 'admin', updated_at = now() where id = v_target;

  perform public._hyn_audit('client.role.admin', v_target, null,
    jsonb_build_object('via', 'promote_by_email'));

  return json_build_object('status', 'ok', 'user_id', v_target);
end;
$$;

revoke all on function public.hyn_admin_promote_by_email(text) from public;
grant execute on function public.hyn_admin_promote_by_email(text) to authenticated;

revoke all on public.profiles              from anon;
revoke all on public.notification_log      from anon;
revoke all on public.admin_audit           from anon;

-- ===========================================================================
-- local-only notification configuration
-- ===========================================================================
-- Notification destinations and provider credentials are configured only in
-- /etc/hyn-view/config and /etc/hyn-view/secrets on each monitored server. A
-- schema reapplication also removes storage and the routing-directory RPC from
-- older deployments. notification_log intentionally remains: it records the
-- delivery result reported by a node, not a credential used to send it.
drop function if exists public.hyn_list_admins();
drop table if exists public.notify_prefs;
drop table if exists public.notification_channels;

-- ---------------------------------------------------------------------------
-- administrator allow list
-- ---------------------------------------------------------------------------
-- Who MAY become an administrator, enforced in the database.
--
-- The earlier version of this took the list from an ADMIN_EMAILS environment
-- variable and checked it in the Next.js server component, then called an RPC
-- that only verified "this email is really yours". That is not a boundary: the
-- RPC is granted to `authenticated`, so any signed-in user could call it
-- directly with the public anon key and their own address and be promoted —
-- the app-layer check was skippable, which is the whole point of the rule that
-- authorisation lives in the database and the UI is only a courtesy.
--
-- This table has RLS on and NO policies, and is revoked from both session
-- roles: it is unreadable and unwritable from any browser session, including an
-- administrator's. It is managed in the SQL editor, deliberately, because "who
-- can become an admin" should need the same access as the schema itself.
create table if not exists public.admin_allowlist (
  email    text primary key,
  note     text,
  added_at timestamptz not null default now()
);

alter table public.admin_allowlist enable row level security;
revoke all on public.admin_allowlist from anon, authenticated;

-- Claim administrator, if the caller's own verified email is on the list above.
--
-- Two independent checks, both server-side: the email must match the session's
-- real address in auth.users (so the argument cannot be used to claim someone
-- else's), and it must be on the allow list (so a legitimate user of the portal
-- cannot promote themselves). Not being allowed returns a status rather than
-- raising, because this runs on every sign-in and a refused claim is the normal
-- case, not an error.
--
-- The name keeps its `_env_` for compatibility with a deployed portal that
-- still calls it; the environment variable is no longer consulted anywhere.
create or replace function public.hyn_claim_env_admin(p_caller_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_real_email text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select email into v_real_email from auth.users where id = v_uid;
  if v_real_email is null then
    return json_build_object('status', 'no_email');
  end if;
  -- p_caller_email is optional now that the list lives here; when supplied it
  -- must be the caller's own address.
  if p_caller_email is not null and p_caller_email <> ''
     and lower(v_real_email) <> lower(p_caller_email) then
    raise exception 'email does not match the authenticated session';
  end if;

  if not exists (
    select 1 from public.admin_allowlist a where lower(a.email) = lower(v_real_email)
  ) then
    return json_build_object('status', 'not_allowed');
  end if;

  update public.profiles
     set role = 'admin', updated_at = now()
   where id = v_uid and role <> 'admin';

  return json_build_object('status', 'ok', 'role', 'admin');
end;
$$;

revoke all on function public.hyn_claim_env_admin(text) from public;
grant execute on function public.hyn_claim_env_admin(text) to authenticated;

-- ===========================================================================
-- durable heartbeat, synchronization, and managed web delivery
-- ===========================================================================
-- Kept at the end so reapplying this canonical schema upgrades every earlier
-- command/config definition in place, matching migration 20260824023000.
alter table public.nodes add column if not exists last_heartbeat_at timestamptz;
-- `nodes` uses a column-level browser grant so token_hash never reaches a
-- session. Every safe column added after that grant must be granted explicitly.
grant select (last_heartbeat_at) on public.nodes to authenticated;
update public.nodes
   set last_heartbeat_at = coalesce(last_config_pull_at, last_seen_at, created_at)
 where last_heartbeat_at is null;
create index if not exists nodes_last_heartbeat_idx
  on public.nodes (last_heartbeat_at desc) where is_demo = false and revoked = false;

-- New agents check for config/commands every minute even when the telemetry
-- collection interval is longer. Pre-1.7 agents retain the legacy
-- three-configured-interval freshness rule during the rollout.
create or replace function public.hyn_admin_overview()
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  return json_build_object(
    'clients_total', (select count(*) from public.profiles),
    'clients_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'admins', (select count(*) from public.profiles where role = 'admin'),
    'nodes_total', (select count(*) from public.nodes where is_demo = false),
    'nodes_active', (select count(*) from public.nodes where status = 'active' and revoked = false and is_demo = false),
    'nodes_paused', (select count(*) from public.nodes where status = 'paused' and is_demo = false),
    'nodes_suspended', (select count(*) from public.nodes where status = 'suspended' and is_demo = false),
    'nodes_revoked', (select count(*) from public.nodes where revoked = true),
    'nodes_stale', (select count(*) from public.nodes n
      where n.is_demo = false and n.revoked = false and n.status = 'active'
        and case
          when coalesce(n.agent_version, '') ~ '^(1\.([7-9]|[1-9][0-9]+)\.|([2-9]|[1-9][0-9]+)\.)'
            then n.last_heartbeat_at is null or n.last_heartbeat_at <= now() - interval '15 minutes'
          else n.last_seen_at is null or n.last_seen_at < now() - make_interval(
            mins => greatest(15, 3 * case
              when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
                then (n.config->>'cloud_push_min')::integer else 10 end))
        end),
    'alerts_open', (select count(*) from public.alert_events where resolved = false and ts > now() - interval '7 days'),
    'notifications_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours'),
    'notifications_failed_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours' and status = 'failed'),
    'metrics_24h', (select count(*) from public.metrics where ts > now() - interval '24 hours')
  );
end;
$$;

create or replace function public.hyn_admin_nodes()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.last_heartbeat_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.last_heartbeat_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours' and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a where a.node_id = n.id and a.resolved = false and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_disk_pct,
             (select m.payload #>> '{agent_update,latest}' from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as latest_agent_version,
             coalesce((select m.payload #>> '{agent_update,available}' in ('true', '1') from public.metrics m where m.node_id = n.id order by m.ts desc limit 1), false) as update_available
        from public.nodes n left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

alter table public.node_commands drop constraint if exists node_commands_command_check;
alter table public.node_commands add constraint node_commands_command_check
  check (command in ('update', 'sync'));
alter table public.node_commands drop constraint if exists node_commands_stage_check;
alter table public.node_commands add constraint node_commands_stage_check
  check (stage in ('queued', 'accepted', 'checking', 'installing', 'restarting',
                   'collecting', 'uploading', 'verifying', 'completed', 'failed',
                   'expired'));
drop index if exists public.node_commands_one_active_update_idx;
create unique index if not exists node_commands_one_active_kind_idx
  on public.node_commands (node_id, command)
  where status in ('queued', 'running');

create table if not exists public.node_watchdogs (
  node_id          uuid primary key references public.nodes (id) on delete cascade,
  state            text not null default 'starting'
                     check (state in ('starting', 'running', 'stopped')),
  run_id           text,
  last_alert_state text not null default 'unknown'
                     check (last_alert_state in ('unknown', 'online', 'offline')),
  started_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.web_notification_jobs (
  id          uuid primary key default gen_random_uuid(),
  node_id     uuid not null references public.nodes (id) on delete cascade,
  fingerprint text not null,
  category    text not null default 'alert'
                check (category in ('alert', 'report', 'test', 'other')),
  severity    text not null default 'info'
                check (severity in ('info', 'warn', 'crit')),
  subject     text not null,
  text_body   text not null,
  html_body   text,
  status      text not null default 'queued'
                check (status in ('queued', 'sending', 'sent', 'failed')),
  attempts    integer not null default 0 check (attempts between 0 and 5),
  provider_id text,
  error       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  sent_at     timestamptz,
  unique (node_id, fingerprint)
);
create index if not exists web_notification_jobs_retry_idx
  on public.web_notification_jobs (status, updated_at)
  where status in ('queued', 'failed');

create table if not exists public.admin_report_jobs (
  id           uuid primary key default gen_random_uuid(),
  requested_by uuid not null references auth.users (id) on delete cascade,
  target_user  uuid not null references auth.users (id) on delete cascade,
  status       text not null default 'queued'
                 check (status in ('queued', 'sending', 'sent', 'failed')),
  provider_id  text,
  error        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  sent_at      timestamptz
);
create unique index if not exists admin_report_jobs_one_active_idx
  on public.admin_report_jobs (target_user)
  where status in ('queued', 'sending');

alter table public.node_watchdogs enable row level security;
alter table public.web_notification_jobs enable row level security;
alter table public.admin_report_jobs enable row level security;
revoke all on public.node_watchdogs from anon, authenticated;
revoke all on public.web_notification_jobs from anon, authenticated;
revoke all on public.admin_report_jobs from anon, authenticated;

create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_created boolean := false;
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'not authenticated'; end if;
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  if not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
      and revoked = false and is_demo = false and status = 'active'
  ) then raise exception 'active node not found'; end if;
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_request_node_update(p_node_id uuid)
returns json language sql security definer set search_path = public as $$
  select public.hyn_request_node_command(p_node_id, 'update');
$$;

create or replace function public.hyn_admin_request_node_command(p_node_id uuid, p_command text)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_owner uuid; v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  select owner into v_owner from public.nodes
   where id = p_node_id and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'active node not found'; end if;
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Administrator requested a complete synchronization'
           else 'Administrator requested an agent update' end
    ) returning * into v_command;
    v_created := true;
  end if;
  perform public._hyn_audit(
    'node.command.' || p_command, v_owner, p_node_id,
    jsonb_build_object('command_id', v_command.id, 'created', v_created)
  );
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_claim_node_command(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_node public.nodes; v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;
  with candidate as (
    select id from public.node_commands
     where node_id = v_node.id and command in ('update', 'sync')
       and (status = 'queued'
            or (status = 'running' and coalesce(lease_expires_at, '-infinity') <= now()))
     order by requested_at for update skip locked limit 1
  )
  update public.node_commands c
     set status = 'running', stage = 'accepted',
         message = case when c.command = 'sync'
                        then 'Machine accepted the synchronization request'
                        else 'Machine accepted the update request' end,
         started_at = coalesce(c.started_at, now()), updated_at = now(),
         lease_expires_at = now() + interval '20 minutes'
    from candidate where c.id = candidate.id returning c.* into v_command;
  if not found then return json_build_object('status', 'idle'); end if;
  return json_build_object(
    'status', 'command', 'id', v_command.id,
    'action', v_command.command, 'stage', v_command.stage
  );
end;
$$;

create or replace function public.hyn_report_node_command(
  p_node_token text,
  p_command_id uuid,
  p_status text,
  p_stage text,
  p_message text,
  p_target_version text default null,
  p_result_version text default null
)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_node public.nodes; v_command public.node_commands;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token) and revoked = false and is_demo = false;
  if not found then raise exception 'invalid node token'; end if;
  if p_status not in ('running', 'succeeded', 'failed') then raise exception 'invalid command status'; end if;
  if p_stage not in ('accepted', 'checking', 'installing', 'restarting', 'collecting',
                     'uploading', 'verifying', 'completed', 'failed') then
    raise exception 'invalid command stage';
  end if;
  select * into v_command from public.node_commands
   where id = p_command_id and node_id = v_node.id and status = 'running' for update;
  if not found then raise exception 'active command not found'; end if;
  if (v_command.command = 'update' and p_stage in ('collecting', 'uploading'))
     or (v_command.command = 'sync' and p_stage in ('checking', 'installing', 'restarting')) then
    raise exception 'stage does not belong to command';
  end if;
  if octet_length(coalesce(p_message, '')) > 500 then raise exception 'command message is too long'; end if;
  if octet_length(coalesce(p_target_version, '')) > 64
     or octet_length(coalesce(p_result_version, '')) > 64 then
    raise exception 'command version is too long';
  end if;
  update public.node_commands
     set status = p_status, stage = p_stage,
         message = coalesce(nullif(trim(p_message), ''), p_stage),
         target_version = coalesce(nullif(p_target_version, ''), target_version),
         result_version = coalesce(nullif(p_result_version, ''), result_version),
         updated_at = now(),
         lease_expires_at = case when p_status = 'running'
                                 then now() + interval '20 minutes' else null end,
         finished_at = case when p_status in ('succeeded', 'failed')
                            then now() else finished_at end
   where id = p_command_id returning * into v_command;
  return json_build_object('status', v_command.status, 'stage', v_command.stage,
                           'updated_at', v_command.updated_at);
end;
$$;

create or replace function public.hyn_update_node_config(p_node_id uuid, p_config jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare v_config jsonb;
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'not authenticated'; end if;
  if not public._hyn_portal_config_valid(p_config) then raise exception 'invalid portal configuration'; end if;
  update public.nodes set config = p_config
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false
  returning config into v_config;
  if not found then raise exception 'node not found'; end if;
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

create or replace function public.hyn_claim_node_watchdog(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_node public.nodes; v_watchdog public.node_watchdogs; v_created boolean := false;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;
  insert into public.node_watchdogs (node_id) values (v_node.id)
  on conflict (node_id) do nothing returning * into v_watchdog;
  if found then
    v_created := true;
  else
    select * into v_watchdog from public.node_watchdogs where node_id = v_node.id for update;
    if v_watchdog.state = 'stopped'
       or v_watchdog.updated_at < now() - interval '5 minutes' then
      update public.node_watchdogs set state = 'starting', run_id = null, updated_at = now()
       where node_id = v_node.id returning * into v_watchdog;
      v_created := true;
    end if;
  end if;
  return json_build_object(
    'node_id', v_node.id, 'created', v_created,
    'state', v_watchdog.state, 'last_alert_state', v_watchdog.last_alert_state
  );
end;
$$;

create or replace function public.hyn_queue_web_notification(p_node_token text, p_event jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_node public.nodes; v_job public.web_notification_jobs; v_created boolean := false;
  v_fingerprint text; v_category text; v_severity text; v_subject text; v_text text; v_html text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false and is_demo = false and status = 'active';
  if not found then raise exception 'invalid or inactive node token'; end if;
  if p_event is null or jsonb_typeof(p_event) <> 'object'
     or octet_length(p_event::text) > 32768 then raise exception 'invalid web event'; end if;
  if p_event ?| array['recipient', 'to', 'from', 'sender', 'email'] then
    raise exception 'web event cannot select a recipient or sender';
  end if;
  v_fingerprint := trim(coalesce(p_event->>'fingerprint', ''));
  v_category := coalesce(nullif(trim(p_event->>'category'), ''), 'alert');
  v_severity := coalesce(nullif(trim(p_event->>'severity'), ''), 'info');
  v_subject := trim(coalesce(p_event->>'subject', ''));
  v_text := trim(coalesce(p_event->>'text_body', ''));
  v_html := nullif(p_event->>'html_body', '');
  if length(v_fingerprint) not between 1 and 200
     or v_category not in ('alert', 'report', 'test', 'other')
     or v_severity not in ('info', 'warn', 'crit')
     or length(v_subject) not between 1 and 300
     or length(v_text) not between 1 and 10000
     or length(coalesce(v_html, '')) > 20000 then raise exception 'invalid web event fields'; end if;
  insert into public.web_notification_jobs (
    node_id, fingerprint, category, severity, subject, text_body, html_body
  ) values (v_node.id, v_fingerprint, v_category, v_severity, v_subject, v_text, v_html)
  on conflict (node_id, fingerprint) do nothing returning * into v_job;
  if found then
    v_created := true;
  else
    select * into v_job from public.web_notification_jobs
     where node_id = v_node.id and fingerprint = v_fingerprint;
  end if;
  return json_build_object(
    'status', v_job.status, 'id', v_job.id,
    'created', v_created, 'fingerprint', v_job.fingerprint
  );
end;
$$;

create or replace function public.hyn_claim_web_notification(p_job_id uuid default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_job public.web_notification_jobs; v_node public.nodes; v_recipient text;
begin
  with candidate as (
    select id from public.web_notification_jobs
     where (p_job_id is null or id = p_job_id)
       and (status = 'queued' or (status = 'failed' and attempts < 5))
     order by created_at for update skip locked limit 1
  )
  update public.web_notification_jobs j
     set status = 'sending', attempts = j.attempts + 1, updated_at = now(), error = null
    from candidate where j.id = candidate.id returning j.* into v_job;
  if not found then return json_build_object('status', 'idle'); end if;
  select * into v_node from public.nodes where id = v_job.node_id;
  select recipient into v_recipient from public.email_preferences where node_id = v_job.node_id;
  return json_build_object(
    'status', 'send', 'id', v_job.id, 'node_id', v_job.node_id,
    'node_name', v_node.name, 'hostname', v_node.hostname,
    'owner', v_node.owner, 'recipient', v_recipient,
    'fingerprint', v_job.fingerprint, 'category', v_job.category,
    'severity', v_job.severity, 'subject', v_job.subject,
    'text_body', v_job.text_body, 'html_body', v_job.html_body,
    'attempts', v_job.attempts
  );
end;
$$;

create or replace function public.hyn_complete_web_notification(
  p_job_id uuid,
  p_status text,
  p_target text default null,
  p_provider_id text default null,
  p_error text default null
)
returns json language plpgsql security definer set search_path = public as $$
declare v_job public.web_notification_jobs; v_owner uuid;
begin
  if p_status not in ('sent', 'failed') then raise exception 'invalid delivery status'; end if;
  update public.web_notification_jobs
     set status = p_status, provider_id = left(nullif(p_provider_id, ''), 200),
         error = left(nullif(p_error, ''), 1000), updated_at = now(),
         sent_at = case when p_status = 'sent' then now() else null end
   where id = p_job_id and status = 'sending' returning * into v_job;
  if not found then raise exception 'active web notification not found'; end if;
  select owner into v_owner from public.nodes where id = v_job.node_id;
  insert into public.notification_log (
    node_id, owner, kind, target, severity, subject, status, error, category
  ) values (
    v_job.node_id, v_owner, 'web', left(p_target, 320), v_job.severity,
    v_job.subject, p_status, left(p_error, 1000), v_job.category
  );
  return json_build_object('status', p_status, 'id', v_job.id);
end;
$$;

create or replace function public.hyn_claim_admin_report(p_target_user uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_job public.admin_report_jobs; v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if not exists (select 1 from public.profiles where id = p_target_user and status = 'active') then
    raise exception 'active client not found';
  end if;
  if not exists (
    select 1 from public.nodes
     where owner = p_target_user and revoked = false and is_demo = false and status = 'active'
  ) then raise exception 'client has no active machines'; end if;
  select * into v_job from public.admin_report_jobs
   where target_user = p_target_user and status in ('queued', 'sending')
   order by created_at desc limit 1;
  if not found then
    insert into public.admin_report_jobs (requested_by, target_user)
    values (auth.uid(), p_target_user) returning * into v_job;
    v_created := true;
  end if;
  perform public._hyn_audit(
    'client.report.requested', p_target_user, null,
    jsonb_build_object('report_id', v_job.id, 'created', v_created)
  );
  return json_build_object(
    'id', v_job.id, 'status', v_job.status,
    'target_user', v_job.target_user, 'created', v_created
  );
end;
$$;

create or replace function public.hyn_complete_admin_report(
  p_report_id uuid,
  p_status text,
  p_provider_id text default null,
  p_error text default null
)
returns json language plpgsql security definer set search_path = public as $$
declare v_job public.admin_report_jobs;
begin
  perform public._hyn_require_admin();
  if p_status not in ('sending', 'sent', 'failed') then raise exception 'invalid report status'; end if;
  update public.admin_report_jobs
     set status = p_status, provider_id = left(nullif(p_provider_id, ''), 200),
         error = left(nullif(p_error, ''), 1000), updated_at = now(),
         sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_report_id returning * into v_job;
  if not found then raise exception 'report not found'; end if;
  perform public._hyn_audit(
    'client.report.' || p_status, v_job.target_user, null,
    jsonb_build_object('report_id', v_job.id, 'error', v_job.error)
  );
  return json_build_object('id', v_job.id, 'status', v_job.status);
end;
$$;

create or replace function public.hyn_fetch_config(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_node public.nodes;
  v_alert_template text;
  v_report_template text;
  v_watchdog json;
begin
  select * into v_node from public.nodes where token_hash = public._hyn_sha256(p_node_token);
  if not found then raise exception 'invalid node token'; end if;
  if v_node.revoked then raise exception 'node revoked'; end if;
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id returning * into v_node;
  end if;
  update public.nodes set last_config_pull_at = now(), last_heartbeat_at = now()
   where id = v_node.id;
  if v_node.status = 'active' and not v_node.is_demo then
    v_watchdog := public.hyn_claim_node_watchdog(p_node_token);
  else
    v_watchdog := json_build_object('created', false, 'state', 'stopped');
  end if;
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_alert_template from public.notification_templates t where t.template_key = 'alert';
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_report_template from public.notification_templates t where t.template_key = 'report';
  return json_build_object(
    'status', 'ok', 'node_id', v_node.id, 'node_name', v_node.name,
    'node_status', v_node.status, 'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason, 'config', v_node.config,
    'heartbeat_at', now(), 'watchdog', v_watchdog,
    'alert_template_b64', coalesce(v_alert_template, ''),
    'report_template_b64', coalesce(v_report_template, '')
  );
end;
$$;

revoke all on function public.hyn_request_node_command(uuid, text) from public;
revoke all on function public.hyn_request_node_update(uuid) from public;
revoke all on function public.hyn_admin_request_node_command(uuid, text) from public;
revoke all on function public.hyn_update_node_config(uuid, jsonb) from public;
revoke all on function public.hyn_claim_node_command(text) from public;
revoke all on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) from public;
revoke all on function public.hyn_claim_node_watchdog(text) from public;
revoke all on function public.hyn_queue_web_notification(text, jsonb) from public;
revoke all on function public.hyn_claim_web_notification(uuid) from public;
revoke all on function public.hyn_complete_web_notification(uuid, text, text, text, text) from public;
revoke all on function public.hyn_claim_admin_report(uuid) from public;
revoke all on function public.hyn_complete_admin_report(uuid, text, text, text) from public;

grant execute on function public.hyn_request_node_command(uuid, text) to authenticated;
grant execute on function public.hyn_request_node_update(uuid) to authenticated;
grant execute on function public.hyn_admin_request_node_command(uuid, text) to authenticated;
grant execute on function public.hyn_update_node_config(uuid, jsonb) to authenticated;
grant execute on function public.hyn_claim_node_command(text) to anon, authenticated;
grant execute on function public.hyn_report_node_command(text, uuid, text, text, text, text, text) to anon, authenticated;
grant execute on function public.hyn_claim_node_watchdog(text) to anon, authenticated;
grant execute on function public.hyn_queue_web_notification(text, jsonb) to anon, authenticated;
grant execute on function public.hyn_claim_admin_report(uuid) to authenticated;
grant execute on function public.hyn_complete_admin_report(uuid, text, text, text) to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.hyn_claim_web_notification(uuid) to service_role;
    grant execute on function public.hyn_complete_web_notification(uuid, text, text, text, text) to service_role;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- resident agent heartbeat (see migrations/20260830120000_resident_agent_heartbeat.sql)
--
-- One column written, four fields returned. Deliberately NOT hyn_fetch_config:
-- that call claims the watchdog, encodes two email templates and triggers
-- notification dispatch, none of which a 24-second liveness beat needs.
create or replace function public.hyn_heartbeat(
  p_node_token text,
  p_agent_version text default null
)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_node public.nodes;
begin
  select * into v_node from public.nodes where token_hash = public._hyn_sha256(p_node_token);
  if not found then raise exception 'invalid node token'; end if;
  if v_node.revoked then raise exception 'node revoked'; end if;
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id returning * into v_node;
  end if;
  -- last_seen_at is left alone on purpose: it means "last sent us a reading",
  -- and several portal views distinguish a node that is reachable from one that
  -- is actually reporting telemetry. A beat is not a reading.
  update public.nodes
     set last_heartbeat_at = now(),
         agent_version = coalesce(nullif(left(coalesce(p_agent_version, ''), 50), ''), agent_version)
   where id = v_node.id;
  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_status', v_node.status,
    'heartbeat_at', now()
  );
end;
$$;

revoke all on function public.hyn_heartbeat(text, text) from public;
grant execute on function public.hyn_heartbeat(text, text) to anon, authenticated;

-- ===========================================================================
-- an administrator can delete one machine, and can see which never linked
-- ===========================================================================
-- Pause, suspend and revoke all leave the row in place, which is correct for a
-- machine that exists: a revoked box is history worth keeping. It is wrong for a
-- machine that never existed. Approving a pairing code creates the node row
-- immediately, so a client who approves a code and then never finishes
-- `sudo hyn link` -- wrong box, a typo, a changed mind -- keeps a machine on
-- their dashboard that will never report anything. The only thing that ever
-- removed one was the pairing-expiry sweep, and only while the pairing row
-- survived; after that the phantom was permanent and nobody, client or
-- administrator, had a button for it.

-- "Never connected" is a different fact from "gone quiet", and the two must not
-- be conflated: quiet means go and look at the box, never connected means the
-- row was created by an approval the agent never completed. Defined once and
-- called from both admin views, because a duplicated definition of this drifts
-- and then the count and the badge disagree.
--
-- last_heartbeat_at is compared against created_at rather than tested for null:
-- migration 20260824023000 backfilled it to coalesce(..., created_at) for every
-- pre-existing row, so a never-connected node from before that migration has a
-- non-null heartbeat equal to its creation time. A real beat is always later.
create or replace function public._hyn_node_ever_connected(p_node public.nodes)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_node.last_seen_at is not null
      or p_node.last_config_pull_at is not null
      or coalesce(p_node.last_heartbeat_at > p_node.created_at, false);
$$;

revoke all on function public._hyn_node_ever_connected(public.nodes) from public;

-- Delete one machine and everything recorded for it. Irreversible, and the
-- audit entry is written first: admin_audit.target_node is ON DELETE SET NULL,
-- so the row survives the delete but loses its reference -- the detail is what
-- keeps the trail readable afterwards.
create or replace function public.hyn_admin_delete_node(
  p_node_id uuid,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_node public.nodes;
  v_owner_email text;
begin
  perform public._hyn_require_admin();

  select * into v_node from public.nodes where id = p_node_id;
  if not found then
    raise exception 'no such node';
  end if;
  select email into v_owner_email from public.profiles where id = v_node.owner;

  perform public._hyn_audit('node.delete', v_node.owner, p_node_id,
    jsonb_build_object(
      'reason', p_reason,
      'name', v_node.name,
      'hostname', v_node.hostname,
      'owner_email', v_owner_email,
      'ever_connected', public._hyn_node_ever_connected(v_node),
      'agent_version', v_node.agent_version
    ));

  -- An unclaimed pairing row points here with ON DELETE SET NULL, and a code
  -- whose node_id is null reads as 'pending' to the polling agent: it would sit
  -- there until expiry waiting for an approval that already happened.
  delete from public.device_codes where node_id = p_node_id;
  -- metrics, speedtests, alert_events, node_commands, watchdogs, web jobs and
  -- email preferences are all ON DELETE CASCADE from nodes.
  delete from public.nodes where id = p_node_id;

  return json_build_object('status', 'ok', 'deleted', p_node_id, 'name', v_node.name);
end;
$$;

revoke all on function public.hyn_admin_delete_node(uuid, text) from public;
grant execute on function public.hyn_admin_delete_node(uuid, text) to authenticated;

-- ever_connected joins the fleet list so a phantom is visible as one rather than
-- looking like a machine that has been quiet since it was created.
create or replace function public.hyn_admin_nodes()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.last_heartbeat_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.last_heartbeat_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
             public._hyn_node_ever_connected(n) as ever_connected,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours' and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a where a.node_id = n.id and a.resolved = false and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_disk_pct,
             (select m.payload #>> '{agent_update,latest}' from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as latest_agent_version,
             coalesce((select m.payload #>> '{agent_update,available}' in ('true', '1') from public.metrics m where m.node_id = n.id order by m.ts desc limit 1), false) as update_available
        from public.nodes n left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

-- How many machines a client has, how many are enabled, and how many are
-- phantoms -- which is the number an administrator is asked about, because it is
-- the one the client can see and cannot explain.
create or replace function public.hyn_admin_clients()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json)
    into v from (
      select p.id, p.email, p.full_name, p.role, p.status, p.suspended_reason, p.created_at,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false) as nodes,
             (select count(*) from public.nodes n where n.owner = p.id and n.status = 'active'
                and n.revoked = false and n.is_demo = false) as nodes_active,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false
                and not public._hyn_node_ever_connected(n)) as nodes_unlinked,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days') as notifications_30d,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days' and l.status = 'failed') as notifications_failed_30d,
             (select max(n.last_seen_at) from public.nodes n where n.owner = p.id) as last_seen_at
        from public.profiles p
    ) x;
  return v;
end;
$$;

-- ===========================================================================
-- a refused machine command says which state refused it
-- ===========================================================================
-- `active node not found` was one message for six different situations: a paused
-- machine, one whose pause deadline had already passed, one suspended by an
-- administrator, one whose credential was revoked, a demo row, and a node id
-- belonging to another account. The portal printed it verbatim under "Recovery
-- on the server: sudo hyn doctor", which is the fix for none of them -- no amount
-- of doctoring on the box clears a pause that is held in the portal.
--
-- One of those cases was a refusal that should have succeeded. Ingest, the
-- settings pull and the heartbeat all resolve an elapsed `paused_until` lazily,
-- because a timed pause is meant to expire by itself; the command RPCs tested
-- `status = 'active'` without doing so. On a machine whose agent is not beating
-- -- exactly when someone reaches for "Sync now" -- nothing else would ever
-- clear it, so the button stayed broken permanently.

-- Resolves the node a command is aimed at, or raises the reason it cannot be.
-- Shared by the owner-scoped and admin RPCs so the two cannot drift into
-- disagreeing about what a paused machine means. p_owner null means "an
-- administrator is asking", which skips only the ownership test.
create or replace function public._hyn_command_node(p_node_id uuid, p_owner uuid)
returns public.nodes
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_node public.nodes;
begin
  select * into v_node from public.nodes where id = p_node_id;
  if not found then
    raise exception 'that machine no longer exists in the portal';
  end if;
  if p_owner is not null and v_node.owner <> p_owner then
    raise exception 'that machine belongs to another account';
  end if;
  if v_node.revoked then
    raise exception 'this machine''s credential was revoked, so the portal can no longer reach it. Pair it again on the server: sudo hyn link';
  end if;
  if v_node.is_demo then
    raise exception 'this is demo data rather than a real server, so there is nothing to collect from it';
  end if;

  -- Same lazy rule as ingest and the heartbeat: a timed pause that outlived its
  -- deadline is not a refusal, it is a pause nobody has cleared yet.
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
    returning * into v_node;
  end if;

  if v_node.status = 'paused' then
    raise exception 'monitoring is paused for this machine%, so it is not accepting readings or commands. Resume it in the portal.%',
      case when v_node.paused_until is not null
        then ' until ' || to_char(v_node.paused_until at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC'
        else '' end,
      case when v_node.status_reason is not null
        then ' Reason: ' || v_node.status_reason || '.' else '' end;
  end if;
  if v_node.status = 'suspended' then
    raise exception 'this machine is suspended, so it is not accepting readings or commands. An administrator has to lift it.%',
      case when v_node.status_reason is not null
        then ' Reason: ' || v_node.status_reason || '.' else '' end;
  end if;

  return v_node;
end;
$$;

revoke all on function public._hyn_command_node(uuid, uuid) from public;

create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_created boolean := false;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  -- Separated from the authentication check: "not authenticated" sent a signed-in
  -- customer whose account had been suspended to look for a login problem.
  if not public.hyn_is_active() then
    raise exception 'this account is suspended, so it cannot send commands to its machines';
  end if;
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  perform public._hyn_command_node(p_node_id, auth.uid());
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_admin_request_node_command(p_node_id uuid, p_command text)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_node public.nodes; v_created boolean := false;
begin
  perform public._hyn_require_admin();
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  v_node := public._hyn_command_node(p_node_id, null);
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Administrator requested a complete synchronization'
           else 'Administrator requested an agent update' end
    ) returning * into v_command;
    v_created := true;
  end if;
  perform public._hyn_audit(
    'node.command.' || p_command, v_node.owner, p_node_id,
    jsonb_build_object('command_id', v_command.id, 'created', v_created)
  );
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

-- ===========================================================================
-- the internal helpers are actually unreachable, not merely revoked from PUBLIC
-- ===========================================================================
-- Every internal in this schema is followed by `revoke all on function ... from
-- public`, and on a plain PostgreSQL install that is the whole story: the only
-- grant a new function carries is the implicit one to PUBLIC. On a Supabase
-- project it is not. The project's default privileges grant EXECUTE on every new
-- function to `anon`, `authenticated` and `service_role` **by name**, and
-- revoking PUBLIC does not touch a grant made to a role. So each of these was
-- callable over /rest/v1/rpc with nothing but the public anon key.
--
-- Measured, not theorised. Against the live project:
--
--   POST /rest/v1/rpc/_hyn_audit  ->  204, and a row in admin_audit
--
-- which is an unauthenticated write into the one table whose entire value is
-- being trustworthy after the fact. `_hyn_command_node` answered
-- `_hyn_sha256` computed hashes, and `_hyn_require_admin` was reachable too.
-- The probe row is removed below.
--
-- The test harness never caught it because it was stricter than production: it
-- created anon and authenticated but not Supabase's default privileges, so
-- "revoked from PUBLIC" really was unreachable there. supabase/test-harness.sql
-- now sets those defaults, and supabase/flow-test.sql asserts this property for
-- every `_hyn_` function, so the next helper cannot reintroduce it quietly.
--
-- _hyn_portal_config_valid is deliberately left reachable: it backs a CHECK
-- constraint on public.nodes, and a check constraint is evaluated as the role
-- performing the write, so revoking it from `authenticated` would break the
-- direct `grant update (config) on nodes` path with "permission denied for
-- function". Reading it back tells a caller nothing it did not already supply.

delete from public.admin_audit where action = 'probe.anon';

do $$
declare
  v_sig text;
  v_role text;
begin
  foreach v_sig in array array[
    'public._hyn_audit(text, uuid, uuid, jsonb)',
    'public._hyn_require_admin()',
    'public._hyn_sha256(text)',
    'public._hyn_command_node(uuid, uuid)',
    'public._hyn_node_ever_connected(public.nodes)',
    'public._hyn_delete_expired_device_code(uuid)',
    'public._hyn_purge_expired_device_codes()',
    -- Trigger functions and the pairing-code generator: reachable is reachable,
    -- even where calling one outside its trigger only produces an error.
    'public._hyn_user_code()',
    'public._hyn_on_auth_user_created()',
    'public._hyn_create_email_preferences()'
  ] loop
    if to_regprocedure(v_sig) is null then continue; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = v_role) then
        execute format('revoke all on function %s from %I', v_sig, v_role);
      end if;
    end loop;
    execute format('revoke all on function %s from public', v_sig);
  end loop;
end;
$$;

-- ===========================================================================
-- an administrator can clear the delivery log
-- ===========================================================================
-- notification_log only ever grew. Rows leave it when a node or an Auth user is
-- deleted and never otherwise -- docs/compliance/retention-schedule.md records it
-- as the one table with no age purge -- so a fleet that has been mailing for a
-- year keeps every long-resolved failure from every machine it has ever owned.
-- The admin panel is where that log is actually read, and a wall of history is
-- what stops it being read.
--
-- Deleting rather than hiding: `target` and `error` are the most personal columns
-- in the schema (a recipient address, and a provider's verbatim reason for
-- refusing it), so keeping them out of sight but on disk is the wrong answer to
-- "we no longer need these".
--
-- p_before makes it a retention purge as well as a wipe -- null clears
-- everything, a timestamp keeps what is recent -- because an administrator
-- tidying up months of resolved failures and one destroying this morning's
-- evidence are not the same action, and only one of them is routine.
create or replace function public.hyn_admin_clear_notifications(
  p_before timestamptz default null,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_deleted bigint;
begin
  perform public._hyn_require_admin();

  with gone as (
    delete from public.notification_log
     where p_before is null or ts < p_before
    returning 1
  )
  select count(*) into v_deleted from gone;

  -- Audited after the fact so the count is the real one, and audited even when it
  -- removed nothing: who cleared the log is the one thing the log can no longer
  -- say about itself.
  perform public._hyn_audit('notification_log.clear', null, null,
    jsonb_build_object('reason', p_reason, 'deleted', v_deleted, 'before', p_before));

  return json_build_object('status', 'ok', 'deleted', v_deleted);
end;
$$;

revoke all on function public.hyn_admin_clear_notifications(timestamptz, text) from public;
grant execute on function public.hyn_admin_clear_notifications(timestamptz, text) to authenticated;

-- ===========================================================================
-- incident alert email is off until somebody asks for it
-- ===========================================================================
-- It shipped on. Every paired machine therefore started mailing its owner the
-- moment a rule fired, on an account that had never chosen to receive mail, and a
-- fleet with a real problem produced thousands of attempts a day -- the admin
-- panel's own attention banner read `4501 notifications failed in the last 24h`.
-- A default nobody chose, that fails four and a half thousand times a day, is not
-- a default: it is the loudest possible way to be ignored.
--
-- So the two per-node digests keep their defaults and this one is opt-in. Both
-- halves matter: the column default changes what a machine paired from now on
-- does, and the backfill changes what the existing fleet does, because a default
-- only ever governed rows that did not exist yet.
--
-- Note what this also switches off, since it is not obvious from the name: the
-- portal's dead-server watchdog (workflows/heartbeat-watchdog.ts) sends its
-- outage mail through the same `incident_enabled` gate. An account that wants to
-- hear about a machine going quiet has to turn Incident alerts on -- one switch on
-- /account, and the panel's own note now says so rather than leaving somebody to
-- discover it during an outage.
alter table public.email_preferences alter column incident_enabled set default false;

-- Reported rather than assumed: this runs once, against a fleet whose size the
-- next person reading the log cannot recover, and "how many accounts were mailing
-- without having asked to" is the whole justification for the change.
do $$
declare v_disabled bigint;
begin
  update public.email_preferences
     set incident_enabled = false,
         updated_at = now()
   where incident_enabled;
  get diagnostics v_disabled = row_count;
  raise notice 'incident alert email switched off for % existing node preference row(s)', v_disabled;
end;
$$;
-- An administrator maps a Highway identity to one portal account. Provider
-- names are display labels; authorization always uses owner + numeric ID.
create table if not exists public.relayer_assignments (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  relayer_id integer not null unique check (relayer_id > 0),
  relayer_name text not null check (length(relayer_name) between 1 and 160),
  created_at timestamptz not null default now()
);
create index if not exists relayer_assignments_owner_idx on public.relayer_assignments(owner);
alter table public.relayer_assignments enable row level security;
drop policy if exists relayer_assignments_read on public.relayer_assignments;
create policy relayer_assignments_read on public.relayer_assignments
  for select to authenticated using (
    public.hyn_is_admin() or (owner = auth.uid() and public.hyn_is_active())
  );
revoke all on public.relayer_assignments from anon, authenticated;
grant select on public.relayer_assignments to authenticated;

create or replace function public.hyn_admin_assign_relayer(p_owner uuid, p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public._hyn_require_admin();
  if p_owner is null or p_relayer_id is null or p_relayer_id <= 0
     or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A user, positive relayer ID and name are required';
  end if;
  if not exists (select 1 from public.profiles where id = p_owner and status = 'active') then
    raise exception 'Select an active portal account';
  end if;
  -- Concurrent assignment attempts are serialized by the unique constraint.
  -- Reassignment requires an explicit removal; never silently transfer access.
  insert into public.relayer_assignments(owner, relayer_id, relayer_name)
  values (p_owner, p_relayer_id, trim(p_relayer_name))
  on conflict (relayer_id) do update set relayer_name = excluded.relayer_name
    where relayer_assignments.owner = excluded.owner
  returning id into v_id;
  if v_id is null then raise exception 'This relayer is already assigned to another account'; end if;
  perform public._hyn_audit('relayer.assign', p_owner, null,
    jsonb_build_object('relayer_id', p_relayer_id, 'relayer_name', trim(p_relayer_name)));
  return v_id;
end;
$$;

create or replace function public.hyn_admin_remove_relayer(p_assignment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_row public.relayer_assignments;
begin
  perform public._hyn_require_admin();
  delete from public.relayer_assignments where id = p_assignment_id returning * into v_row;
  if v_row.id is null then raise exception 'Assignment no longer exists'; end if;
  perform public._hyn_audit('relayer.remove', v_row.owner, null,
    jsonb_build_object('relayer_id', v_row.relayer_id, 'relayer_name', v_row.relayer_name));
end;
$$;
revoke all on function public.hyn_admin_assign_relayer(uuid, integer, text) from public, anon;
revoke all on function public.hyn_admin_remove_relayer(uuid) from public, anon;
grant execute on function public.hyn_admin_assign_relayer(uuid, integer, text) to authenticated;
grant execute on function public.hyn_admin_remove_relayer(uuid) to authenticated;
-- Control-plane metadata only. Detailed readings never enter this RPC.
alter table public.nodes add column if not exists telemetry_mode text not null default 'cloud'
  check (telemetry_mode in ('local', 'cloud'));
grant select (telemetry_mode) on public.nodes to authenticated;

create or replace function public.hyn_local_heartbeat(p_node_token text, p_agent_version text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_result json; v_node public.nodes;
begin
  v_result := public.hyn_heartbeat(p_node_token, p_agent_version);
  select * into v_node from public.nodes where id = (v_result->>'node_id')::uuid;
  if not exists (select 1 from public.profiles where id = v_node.owner and status = 'active') then
    raise exception 'account suspended';
  end if;
  update public.nodes set telemetry_mode = 'local' where id = v_node.id and telemetry_mode <> 'local';
  return v_result;
end;
$$;
revoke all on function public.hyn_local_heartbeat(text, text) from public;
grant execute on function public.hyn_local_heartbeat(text, text) to anon, authenticated;

-- Local history does not need email templates, dispatch queues or a Workflow
-- lease on every settings poll. Return only the managed property allowlist.
create or replace function public.hyn_fetch_local_config(p_node_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_result json; v_node public.nodes;
begin
  v_result := public.hyn_local_heartbeat(p_node_token);
  update public.nodes set last_config_pull_at = now()
    where id = (v_result->>'node_id')::uuid returning * into v_node;
  return json_build_object('node_id', v_node.id, 'node_status', v_node.status,
    'status_reason', v_node.status_reason, 'config', v_node.config);
end;
$$;
revoke all on function public.hyn_fetch_local_config(text) from public;
grant execute on function public.hyn_fetch_local_config(text) to anon, authenticated;

-- An operator explicitly enabling the legacy archive is reflected in the UI.
create or replace function public._hyn_mark_cloud_telemetry()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.nodes set telemetry_mode = 'cloud' where id = new.node_id and telemetry_mode <> 'cloud';
  return new;
end;
$$;
revoke all on function public._hyn_mark_cloud_telemetry() from public, anon, authenticated;
drop trigger if exists hyn_mark_cloud_telemetry on public.metrics;
create trigger hyn_mark_cloud_telemetry after insert on public.metrics
for each row execute function public._hyn_mark_cloud_telemetry();

-- Allow bounded monitoring schedules and sleep prevention through existing owner/admin settings.
-- Endpoints, credentials and local storage permissions remain local-only.
create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  e record;
  v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_enabled', 'report_enabled', 'keep_awake') then
        if v not in ('on', 'off') then return false; end if;
      when e.key in ('alert_interval_min', 'record_interval_min') then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'speedtest_per_day' then
        if v !~ '^[1-9][0-9]?$' then return false; end if;
        if v::integer > 24 then return false; end if;
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' then return false; end if;
        if v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' then return false; end if;
        if v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'cloud_storage' then
        if v not in ('cloud','local') then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'cloud_checkin_min' then
        if v !~ '^[1-9][0-9]{0,2}$' then return false; end if;
        if v::integer > 60 then return false; end if;
      when e.key = 'heartbeat_sec' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer < 5 or v::integer > 3600 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'dashboard_view' then
        if v not in ('dash', 'simple') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;
-- A request never grants access. Only an active administrator can assign an ID.
create table if not exists public.relayer_requests (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  relayer_id integer not null check (relayer_id > 0),
  relayer_name text not null check (length(trim(relayer_name)) between 1 and 160),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  unique (owner, relayer_id)
);
create index if not exists relayer_requests_pending_idx on public.relayer_requests(created_at) where status='pending';
alter table public.relayer_requests enable row level security;
drop policy if exists relayer_requests_read on public.relayer_requests;
create policy relayer_requests_read on public.relayer_requests for select to authenticated
  using (public.hyn_is_admin() or (owner=auth.uid() and public.hyn_is_active()));
revoke all on public.relayer_requests from anon, authenticated;
grant select on public.relayer_requests to authenticated;

create or replace function public.hyn_request_relayer(p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  -- Serialize this owner's submissions so concurrent calls cannot evade limits.
  perform 1 from public.profiles where id=auth.uid() for update;
  if exists(select 1 from public.relayer_assignments where relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned. Ask an administrator to check its assignment';
  end if;
  select id into v_id from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id and status='pending';
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.relayer_requests where owner=auth.uid() and status='pending')>=10 then
    raise exception 'You already have 10 pending requests. Cancel one or wait for a review';
  end if;
  if not exists(select 1 from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id)
     and (select count(*) from public.relayer_requests where owner=auth.uid())>=50 then
    raise exception 'Request limit reached. Contact an administrator';
  end if;
  insert into public.relayer_requests(owner,relayer_id,relayer_name)
    values(auth.uid(),p_relayer_id,trim(p_relayer_name))
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name,status='pending',created_at=now(),reviewed_at=null,reviewed_by=null
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.hyn_cancel_relayer_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  update public.relayer_requests set status='cancelled',reviewed_at=now()
    where id=p_request_id and owner=auth.uid() and status='pending';
  if not found then raise exception 'Pending request not found'; end if;
end $$;

-- Direct admin assignment also resolves a matching request, so the two paths
-- cannot leave a customer both assigned and waiting for approval.
create or replace function public._hyn_resolve_relayer_request()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  update public.relayer_requests set status='approved',relayer_name=new.relayer_name,reviewed_at=now(),reviewed_by=auth.uid()
    where owner=new.owner and relayer_id=new.relayer_id and status='pending';
  if found then
    perform public._hyn_audit('relayer.request.approved',new.owner,null,jsonb_build_object('relayer_id',new.relayer_id));
  end if;
  return new;
end $$;
drop trigger if exists relayer_assignment_resolves_request on public.relayer_assignments;
create trigger relayer_assignment_resolves_request after insert or update on public.relayer_assignments
  for each row execute function public._hyn_resolve_relayer_request();

create or replace function public.hyn_admin_review_relayer_request(p_request_id uuid, p_approve boolean, p_relayer_name text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_request public.relayer_requests;
begin
  perform public._hyn_require_admin();
  if p_approve is null then raise exception 'Choose approve or reject'; end if;
  select * into v_request from public.relayer_requests where id=p_request_id and status='pending' for update;
  if not found then raise exception 'This request is no longer pending'; end if;
  if p_approve then
    perform public.hyn_admin_assign_relayer(v_request.owner,v_request.relayer_id,p_relayer_name);
  else
    update public.relayer_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
    perform public._hyn_audit('relayer.request.rejected',v_request.owner,null,jsonb_build_object('relayer_id',v_request.relayer_id));
  end if;
end $$;
revoke all on function public._hyn_resolve_relayer_request() from public,anon,authenticated;
revoke all on function public.hyn_request_relayer(integer,text) from public,anon;
revoke all on function public.hyn_cancel_relayer_request(uuid) from public,anon;
revoke all on function public.hyn_admin_review_relayer_request(uuid,boolean,text) from public,anon;
grant execute on function public.hyn_request_relayer(integer,text) to authenticated;
grant execute on function public.hyn_cancel_relayer_request(uuid) to authenticated;
grant execute on function public.hyn_admin_review_relayer_request(uuid,boolean,text) to authenticated;

-- HYN PORTAL ROLES V1
-- Four roles, explicit dashboard sharing, and database-enforced capabilities.
-- Apply after 20260909090000_relayer_requests.sql. Safe to apply again.
begin;

-- Detect the legacy constraint BEFORE converting. Reapplying must never promote
-- a new, deliberately restricted Admin into a Super admin.
do $$
begin
  if exists (select 1 from pg_constraint where conrelid='public.profiles'::regclass
    and conname='profiles_role_check' and pg_get_constraintdef(oid) like '%''user''%') then
    alter table public.profiles drop constraint profiles_role_check;
    update public.profiles set role=case role when 'admin' then 'super_admin' when 'user' then 'monitor' else role end;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.profiles'::regclass and conname='profiles_role_check') then
    alter table public.profiles add constraint profiles_role_check check(role in ('viewer','monitor','admin','super_admin'));
  end if;
end $$;
alter table public.profiles alter column role set default 'monitor';

create or replace function public.hyn_is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role in ('admin','super_admin'));
$$;
create or replace function public.hyn_is_super_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role='super_admin');
$$;
create or replace function public.hyn_can_monitor()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active' and role in ('monitor','super_admin'));
$$;
create or replace function public._hyn_require_staff()
returns uuid language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_admin() then raise exception 'administrator role required'; end if;
  return auth.uid();
end $$;
-- Existing operational RPCs all call this guard. Staff read RPCs below use the
-- separate staff guard, so every old write endpoint remains protected.
create or replace function public._hyn_require_admin()
returns uuid language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_super_admin() then raise exception 'super administrator role required'; end if;
  return auth.uid();
end $$;

create table if not exists public.dashboard_access (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(viewer_id,owner_id),
  check(viewer_id<>owner_id)
);
alter table public.dashboard_access enable row level security;
revoke all on public.dashboard_access from public,anon,authenticated;
grant select on public.dashboard_access to authenticated;
drop policy if exists dashboard_access_read on public.dashboard_access;
create policy dashboard_access_read on public.dashboard_access for select to authenticated
using(public.hyn_is_active() and (viewer_id=auth.uid() or public.hyn_is_admin()));

create or replace function public.hyn_can_view_dashboard(p_owner uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and (
    public.hyn_is_admin() or
    exists(select 1 from public.profiles p where p.id=p_owner and p.status='active' and (
      p.id=auth.uid() or exists(select 1 from public.dashboard_access a where a.viewer_id=auth.uid() and a.owner_id=p_owner)
    ))
  );
$$;
create or replace function public.hyn_dashboard_accounts()
returns json language sql stable security definer set search_path=public as $$
  select coalesce(json_agg(json_build_object('id',p.id,
    'name',case when p.id=auth.uid() then 'My dashboard' else coalesce(nullif(p.full_name,''),'Shared dashboard ' || left(p.id::text,8)) end,
    'own',p.id=auth.uid()) order by (p.id=auth.uid()) desc,p.full_name,p.id),'[]'::json)
  from public.profiles p where public.hyn_can_view_dashboard(p.id);
$$;
create or replace function public.hyn_admin_set_dashboard_access(p_viewer uuid,p_owner uuid,p_allow boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public._hyn_require_admin();
  if p_allow is null then raise exception 'choose whether to grant or revoke access'; end if;
  if p_viewer=p_owner then raise exception 'accounts already have access to their own dashboard'; end if;
  if p_allow then
    insert into public.dashboard_access(viewer_id,owner_id,granted_by) values(p_viewer,p_owner,auth.uid()) on conflict do nothing;
  else
    delete from public.dashboard_access where viewer_id=p_viewer and owner_id=p_owner;
  end if;
  perform public._hyn_audit('dashboard.access',p_viewer,null,jsonb_build_object('owner',p_owner,'allowed',p_allow));
end $$;

create or replace function public.hyn_admin_set_role(p_user_id uuid,p_role text)
returns json language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_old text;
begin
  -- Serialize role/status changes and recheck the caller after acquiring the lock.
  perform pg_advisory_xact_lock(74821901);
  v_actor:=public._hyn_require_staff();
  if p_role is null or p_role not in ('viewer','monitor','admin','super_admin') then raise exception 'unknown role'; end if;
  select role into v_old from public.profiles where id=p_user_id for update;
  if not found then raise exception 'no such client'; end if;
  if v_actor=p_user_id and v_old<>p_role then raise exception 'refusing to change your own role'; end if;
  if not public.hyn_is_super_admin() and (p_role<>'admin' or v_old not in ('viewer','monitor','admin')) then
    raise exception 'admins can only add other admins';
  end if;
  if v_old<>p_role then
    update public.profiles set role=p_role,updated_at=now() where id=p_user_id;
    perform public._hyn_audit('client.role.'||p_role,p_user_id,null,jsonb_build_object('previous_role',v_old));
  end if;
  return json_build_object('status','ok','role',p_role);
end $$;
create or replace function public.hyn_admin_promote_by_email(p_email text)
returns json language plpgsql security definer set search_path=public as $$
declare v_target uuid; v_role text;
begin
  perform public._hyn_require_staff();
  select id,role into v_target,v_role from public.profiles where lower(email)=lower(trim(p_email));
  if not found then return json_build_object('status','not_found'); end if;
  if v_role='super_admin' then raise exception 'this account is already a super admin'; end if;
  perform public.hyn_admin_set_role(v_target,'admin');
  return json_build_object('status','ok','user_id',v_target);
end $$;


create or replace function public.hyn_admin_overview()
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_staff();
  return json_build_object(
    'clients_total', (select count(*) from public.profiles),
    'clients_suspended', (select count(*) from public.profiles where status = 'suspended'),
    'admins', (select count(*) from public.profiles where role in ('admin','super_admin')),
    'nodes_total', (select count(*) from public.nodes where is_demo = false),
    'nodes_active', (select count(*) from public.nodes where status = 'active' and revoked = false and is_demo = false),
    'nodes_paused', (select count(*) from public.nodes where status = 'paused' and is_demo = false),
    'nodes_suspended', (select count(*) from public.nodes where status = 'suspended' and is_demo = false),
    'nodes_revoked', (select count(*) from public.nodes where revoked = true),
    'nodes_stale', (select count(*) from public.nodes n
      where n.is_demo = false and n.revoked = false and n.status = 'active'
        and case
          when coalesce(n.agent_version, '') ~ '^(1\.([7-9]|[1-9][0-9]+)\.|([2-9]|[1-9][0-9]+)\.)'
            then n.last_heartbeat_at is null or n.last_heartbeat_at <= now() - interval '15 minutes'
          else n.last_seen_at is null or n.last_seen_at < now() - make_interval(
            mins => greatest(15, 3 * case
              when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
                then (n.config->>'cloud_push_min')::integer else 10 end))
        end),
    'alerts_open', (select count(*) from public.alert_events where resolved = false and ts > now() - interval '7 days'),
    'notifications_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours'),
    'notifications_failed_24h', (select count(*) from public.notification_log where ts > now() - interval '24 hours' and status = 'failed'),
    'metrics_24h', (select count(*) from public.metrics where ts > now() - interval '24 hours')
  );
end;
$$;

create or replace function public.hyn_admin_nodes()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.last_heartbeat_at desc nulls last), '[]'::json)
    into v from (
      select n.id, n.name, n.hostname, n.os, n.agent_version, n.status,
             n.paused_until, n.status_reason, n.revoked, n.is_demo,
             n.created_at, n.last_seen_at, n.last_config_pull_at, n.last_heartbeat_at, n.config,
             p.id as owner_id, p.email as owner_email, p.status as owner_status, p.role as owner_role,
             public._hyn_node_ever_connected(n) as ever_connected,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours') as notifications_24h,
             (select count(*) from public.notification_log l where l.node_id = n.id and l.ts > now() - interval '24 hours' and l.status = 'failed') as notifications_failed_24h,
             (select count(*) from public.alert_events a where a.node_id = n.id and a.resolved = false and a.ts > now() - interval '7 days') as alerts_open,
             (select m.cpu_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_cpu_pct,
             (select m.cpu_temp_c from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_temp_c,
             (select m.mem_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_mem_pct,
             (select m.disk_pct from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as last_disk_pct,
             (select m.payload #>> '{agent_update,latest}' from public.metrics m where m.node_id = n.id order by m.ts desc limit 1) as latest_agent_version,
             coalesce((select m.payload #>> '{agent_update,available}' in ('true', '1') from public.metrics m where m.node_id = n.id order by m.ts desc limit 1), false) as update_available
        from public.nodes n left join public.profiles p on p.id = n.owner
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_clients()
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json)
    into v from (
      select p.id, p.email, p.full_name, p.role, p.status, p.suspended_reason, p.created_at,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false) as nodes,
             (select count(*) from public.nodes n where n.owner = p.id and n.status = 'active'
                and n.revoked = false and n.is_demo = false) as nodes_active,
             (select count(*) from public.nodes n where n.owner = p.id and n.is_demo = false
                and not public._hyn_node_ever_connected(n)) as nodes_unlinked,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days') as notifications_30d,
             (select count(*) from public.notification_log l where l.owner = p.id
                and l.ts > now() - interval '30 days' and l.status = 'failed') as notifications_failed_30d,
             (select max(n.last_seen_at) from public.nodes n where n.owner = p.id) as last_seen_at
        from public.profiles p
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_notifications(p_limit integer default 200)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select l.id, l.ts, l.kind, l.target, l.severity, l.subject, l.status, l.error, l.category,
             n.name as node_name, p.email as owner_email
        from public.notification_log l
        left join public.nodes n on n.id = l.node_id
        left join public.profiles p on p.id = l.owner
       order by l.ts desc
       limit least(greatest(coalesce(p_limit, 200), 1), 1000)
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_audit(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.ts desc), '[]'::json)
    into v
    from (
      select a.id, a.ts, a.actor_email, a.action, a.detail,
             a.target_user, a.target_node,
             n.name as target_node_name,
             p.email as target_user_email
        from public.admin_audit a
        left join public.nodes n on n.id = a.target_node
        left join public.profiles p on p.id = a.target_user
       order by a.ts desc
       limit least(greatest(coalesce(p_limit, 100), 1), 1000)
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_templates()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_staff();
  select coalesce(json_agg(row_to_json(x) order by x.template_key), '[]'::json)
    into v
    from (
      select t.template_key, t.name, t.description, t.html_template, t.updated_at,
             p.email as updated_by_email
        from public.notification_templates t
        left join public.profiles p on p.id = t.updated_by
       order by t.template_key
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_set_user_status(
  p_user_id uuid,
  p_status text,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  perform pg_advisory_xact_lock(74821901);
  v_actor := public._hyn_require_admin();
  if p_status not in ('active', 'suspended') then
    raise exception 'unknown status: %', p_status;
  end if;
  -- Locking yourself out is never the intent.
  if p_user_id = v_actor and p_status = 'suspended' then
    raise exception 'refusing to suspend your own account';
  end if;

  update public.profiles
     set status = p_status,
         suspended_reason = case when p_status = 'suspended' then left(p_reason, 300) else null end,
         updated_at = now()
   where id = p_user_id;
  if not found then
    raise exception 'no such client';
  end if;

  -- Suspending a client suspends their fleet, otherwise their boxes keep
  -- reporting into an account nobody is allowed to look at.
  if p_status = 'suspended' then
    update public.nodes set status = 'suspended',
           status_reason = 'account suspended'
     where owner = p_user_id and status <> 'suspended';
  else
    update public.nodes set status = 'active', status_reason = null, paused_until = null
     where owner = p_user_id and status = 'suspended'
       and status_reason = 'account suspended';
  end if;

  perform public._hyn_audit('client.status.' || p_status, p_user_id, null,
    jsonb_build_object('reason', p_reason));

  return json_build_object('status', 'ok', 'client_status', p_status);
end;
$$;

create or replace function public.hyn_device_approve(
  p_user_code text,
  p_node_name text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_node_id uuid;
  v_node_token text;
  v_uid uuid := auth.uid();
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  -- Global cleanup always precedes the single-row approval lock. Purge workers
  -- use ordered SKIP LOCKED scans, eliminating cross-row lock cycles.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  v_node_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.nodes (owner, name, hostname, os, agent_version, token_hash)
  values (
    v_uid,
    coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node'),
    v.hostname, v.os, v.agent_version,
    public._hyn_sha256(v_node_token)
  )
  returning id into v_node_id;

  update public.device_codes
     set approved_by = v_uid,
         node_id = v_node_id,
         node_token_hash = public._hyn_sha256(v_node_token)
   where id = v.id;

  -- The plaintext token is handed to the polling server, not to this browser.
  -- Stashing it here (hashed) is what lets the poll succeed exactly once.
  return json_build_object(
    'status', 'approved',
    'node_id', v_node_id,
    'node_name', coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node')
  );
end;
$$;

create or replace function public.hyn_demo_seed()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_node_id uuid;
  i integer;
  v_ts timestamptz;
  v_cpu numeric;
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.nodes where owner = v_uid and is_demo = true;

  insert into public.nodes (owner, name, hostname, os, agent_version, is_demo)
  values (v_uid, 'demo-node', 'demo-node', 'Ubuntu 24.04 LTS (demo)', '0.0.0-demo', true)
  returning id into v_node_id;

  for i in 0..287 loop
    v_ts := now() - (i * interval '5 minutes');
    v_cpu := 18 + 22 * abs(sin(i / 26.0)) + (random() * 9);
    insert into public.metrics (
      node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
      load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
      net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms, payload
    ) values (
      v_node_id, v_ts,
      round(v_cpu, 1),
      round((41 + v_cpu * 0.32 + random() * 2)::numeric, 1),
      round((2400 + v_cpu * 14 + random() * 60)::numeric),
      'AMD EPYC 9354 32-Core (demo)',
      round((random() * 2)::numeric, 2),
      round((random() * 4)::numeric, 2),
      8,
      round(((v_cpu / 100.0) * 8 * 0.7)::numeric, 2),
      round((52 + 9 * sin(i / 41.0) + random() * 3)::numeric, 1),
      33285996544, 17301504000, 0,
      round((58 + (i / 288.0) * 3)::numeric, 1),
      1900800 - (i * 300),
      'eth0',
      (620000000 + random() * 260000000)::bigint,
      (180000000 + random() * 90000000)::bigint,
      round((random() * 7)::numeric, 2),
      round((7 + random() * 4)::numeric, 2),
      -- The Highway section of the payload, so the demo dashboard shows the
      -- node panel the way a paired relay would. Same key names as the agent's
      -- `highway` object in lib/cloud.sh; flagged demo like everything else here.
      jsonb_build_object(
        'demo', true,
        'highway', jsonb_build_object(
          'present', 1,
          'tracked', true,
          'health', 'ok',
          'health_why', '2 unit(s) active',
          'version', 'v0.1.75',
          'version_src', 'file',
          'latest', 'v0.1.80',
          'update_available', 1,
          'bin_path', '/usr/local/bin/highway',
          'bin_size', 48234496,
          'bin_mtime', extract(epoch from now() - interval '9 days')::bigint,
          'units_total', 2,
          'units_active', 2,
          'units_failed', 0,
          'units', jsonb_build_array(
            jsonb_build_object(
              'name', 'highway.service', 'state', 'active', 'sub', 'running',
              'restarts', 1, 'memory', (402653184 + random() * 20000000)::bigint,
              'active_s', 1900800 - (i * 300)
            ),
            jsonb_build_object(
              'name', 'nebula.service', 'state', 'active', 'sub', 'running',
              'restarts', 0, 'memory', 18874368,
              'active_s', 1900800 - (i * 300)
            )
          ),
          'pid', 1471,
          'cpu_tenths', (40 + random() * 60)::int,
          'rss', (402653184 + random() * 20000000)::bigint,
          'threads', 19,
          'fds', 48,
          'proc_uptime_s', 1900800 - (i * 300),
          'mesh_iface', 'nebula1',
          'mesh_rx_bps', (900000 + random() * 400000)::bigint,
          'mesh_tx_bps', (700000 + random() * 300000)::bigint,
          'mesh_rx_total', 88000000000::bigint,
          'mesh_tx_total', 44000000000::bigint,
          'mesh_drops', 0,
          'qdisc', 'fq_codel',
          'qdisc_drops', 0,
          'congestion', 'bbr',
          'nft_tables', 3,
          'journal_err_1h', 0,
          'journal_warn_1h', 2,
          'journal_tail', jsonb_build_array(
            'demo: peer handshake retry', 'demo: lighthouse reconnect'
          )
        )
      )
    ) on conflict (node_id, ts) do nothing;
  end loop;

  for i in 0..11 loop
    insert into public.speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
    values (
      v_node_id, now() - (i * interval '6 hours'),
      (720000000 + random() * 180000000)::bigint,
      (330000000 + random() * 120000000)::bigint,
      round((8 + random() * 5)::numeric, 2), 'demo'
    ) on conflict (node_id, ts) do nothing;
  end loop;

  insert into public.alert_events (node_id, ts, rule, severity, message, resolved) values
    (v_node_id, now() - interval '3 hours',  'cpu_temp',  'warn', 'CPU temperature 71C above threshold 70C', true),
    (v_node_id, now() - interval '19 hours', 'disk_pct',  'warn', 'Filesystem / at 86% (projected full in 12 days)', false),
    (v_node_id, now() - interval '2 days',   'unit_failed', 'crit', 'systemd unit highway.service entered failed state', true),
    (v_node_id, now() - interval '4 days',   'report',    'info', 'Daily report delivered', true);

  return json_build_object('status', 'ok', 'node_id', v_node_id);
end;
$$;

create or replace function public.hyn_demo_clear()
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  perform public._hyn_require_admin();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  delete from public.nodes where owner = v_uid and is_demo = true;
  get diagnostics v_count = row_count;
  return json_build_object('status', 'ok', 'removed', v_count);
end;
$$;

create or replace function public.hyn_update_node_config(p_node_id uuid, p_config jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare v_config jsonb;
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'not authenticated'; end if;
  if not public._hyn_portal_config_valid(p_config) then raise exception 'invalid portal configuration'; end if;
  update public.nodes set config = p_config
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false
  returning config into v_config;
  if not found then raise exception 'node not found'; end if;
  return json_build_object('status', 'ok', 'config', v_config);
end;
$$;

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
  perform public._hyn_require_admin();
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_node from public.nodes
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false;
  if not found then raise exception 'node not found'; end if;
  select recipient into v_recipient from public.email_preferences where node_id = v_node.id;
  if not found then return json_build_object('status', 'skip', 'reason', 'email preference missing'); end if;
  v_key := 'device-linked:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system') on conflict (idempotency_key) do nothing;
  if not found then return json_build_object('status', 'skip', 'reason', 'already sent'); end if;
  return json_build_object(
    'status', 'send', 'node_id', v_node.id, 'node_name', v_node.name,
    'hostname', v_node.hostname, 'os', v_node.os, 'agent_version', v_node.agent_version,
    'recipient', v_recipient, 'linked_at', v_node.created_at
  );
end;
$$;

create or replace function public.hyn_complete_device_linked_email(p_node_id uuid, p_provider_id text default null)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_admin();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text
     and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_request_relayer(p_relayer_id integer, p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  -- Serialize this owner's submissions so concurrent calls cannot evade limits.
  perform 1 from public.profiles where id=auth.uid() for update;
  if exists(select 1 from public.relayer_assignments where relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned. Ask an administrator to check its assignment';
  end if;
  select id into v_id from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id and status='pending';
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.relayer_requests where owner=auth.uid() and status='pending')>=10 then
    raise exception 'You already have 10 pending requests. Cancel one or wait for a review';
  end if;
  if not exists(select 1 from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id)
     and (select count(*) from public.relayer_requests where owner=auth.uid())>=50 then
    raise exception 'Request limit reached. Contact an administrator';
  end if;
  insert into public.relayer_requests(owner,relayer_id,relayer_name)
    values(auth.uid(),p_relayer_id,trim(p_relayer_name))
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name,status='pending',created_at=now(),reviewed_at=null,reviewed_by=null
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.hyn_cancel_relayer_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  update public.relayer_requests set status='cancelled',reviewed_at=now()
    where id=p_request_id and owner=auth.uid() and status='pending';
  if not found then raise exception 'Pending request not found'; end if;
end $$;

create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_created boolean := false;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  -- Separated from the authentication check: "not authenticated" sent a signed-in
  -- customer whose account had been suspended to look for a login problem.
  if not public.hyn_is_active() then
    raise exception 'this account is suspended, so it cannot send commands to its machines';
  end if;
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if p_command='update' and not public.hyn_is_super_admin() then raise exception 'super administrator role required'; end if;
  if not exists(select 1 from public.nodes where id=p_node_id and public.hyn_can_view_dashboard(owner)) then
    raise exception 'dashboard access required';
  end if;
  perform public._hyn_command_node(p_node_id, null);
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;

create or replace function public.hyn_claim_env_admin(p_caller_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_real_email text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select email into v_real_email from auth.users where id = v_uid;
  if v_real_email is null then
    return json_build_object('status', 'no_email');
  end if;
  -- p_caller_email is optional now that the list lives here; when supplied it
  -- must be the caller's own address.
  if p_caller_email is not null and p_caller_email <> ''
     and lower(v_real_email) <> lower(p_caller_email) then
    raise exception 'email does not match the authenticated session';
  end if;

  if not exists (
    select 1 from public.admin_allowlist a where lower(a.email) = lower(v_real_email)
  ) then
    return json_build_object('status', 'not_allowed');
  end if;

  perform pg_advisory_xact_lock(74821901);
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  delete from public.admin_allowlist where lower(email)=lower(v_real_email);
  if not found then return json_build_object('status','not_allowed'); end if;
  perform public._hyn_audit('client.role.super_admin',v_uid,null,jsonb_build_object('via','bootstrap_allowlist'));
  update public.profiles
     set role = 'super_admin', updated_at = now()
   where id = v_uid and role <> 'super_admin';

  return json_build_object('status', 'ok', 'role', 'super_admin');
end;
$$;

-- Remove Supabase's table-wide default UPDATE grant before column grants.
-- Otherwise a Super admin could bypass role auditing and the self-lockout guard.
revoke update on public.profiles from authenticated;
grant update(full_name) on public.profiles to authenticated;
revoke update on public.nodes from authenticated;
grant update(name,revoked,config) on public.nodes to authenticated;

-- Read grants contain telemetry only; node credential hashes remain ungranted.
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes for select to authenticated using(public.hyn_can_view_dashboard(owner));
drop policy if exists nodes_update_own on public.nodes;
create policy nodes_update_own on public.nodes for update to authenticated using(public.hyn_is_super_admin()) with check(public.hyn_is_super_admin());
drop policy if exists nodes_delete_own on public.nodes;
create policy nodes_delete_own on public.nodes for delete to authenticated using(public.hyn_is_super_admin());
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated using(id=auth.uid() and public.hyn_is_super_admin()) with check(id=auth.uid() and public.hyn_is_super_admin());


drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated using(exists(select 1 from public.nodes n where n.id=metrics.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated using(exists(select 1 from public.nodes n where n.id=speedtests.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated using(exists(select 1 from public.nodes n where n.id=alert_events.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands for select to authenticated using(exists(select 1 from public.nodes n where n.id=node_commands.node_id and public.hyn_can_view_dashboard(n.owner)));

drop policy if exists relayer_assignments_read on public.relayer_assignments;
create policy relayer_assignments_read on public.relayer_assignments for select to authenticated using(public.hyn_can_view_dashboard(owner));
drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log for select to authenticated using(public.hyn_is_active() and (owner=auth.uid() or public.hyn_is_admin()));


drop policy if exists email_preferences_insert_own on public.email_preferences;
create policy email_preferences_insert_own on public.email_preferences for insert to authenticated with check(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid()));

drop policy if exists email_preferences_update_own on public.email_preferences;
create policy email_preferences_update_own on public.email_preferences for update to authenticated using(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid())) with check(public.hyn_is_super_admin() and exists(select 1 from public.nodes where id=node_id and owner=auth.uid()));

revoke all on function public._hyn_require_staff() from public,anon,authenticated;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    revoke all on function public._hyn_require_staff() from service_role;
  end if;
end $$;

revoke all on function public.hyn_is_super_admin() from public,anon;
grant execute on function public.hyn_is_super_admin() to authenticated;

revoke all on function public.hyn_can_monitor() from public,anon;
grant execute on function public.hyn_can_monitor() to authenticated;

revoke all on function public.hyn_can_view_dashboard(uuid) from public,anon;
grant execute on function public.hyn_can_view_dashboard(uuid) to authenticated;

revoke all on function public.hyn_dashboard_accounts() from public,anon;
grant execute on function public.hyn_dashboard_accounts() to authenticated;

revoke all on function public.hyn_admin_set_dashboard_access(uuid,uuid,boolean) from public,anon;
grant execute on function public.hyn_admin_set_dashboard_access(uuid,uuid,boolean) to authenticated;

notify pgrst, 'reload schema';
commit;

-- HYN SERVER ACCESS AND BANDWIDTH V1
begin;
create table if not exists public.server_access (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  node_id uuid not null references public.nodes(id) on delete cascade,
  allowed boolean not null,
  notifications_allowed boolean not null default true,
  granted_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(viewer_id,node_id)
);
alter table public.server_access add column if not exists notifications_allowed boolean not null default true;
create index if not exists server_access_node_idx on public.server_access(node_id);
alter table public.server_access enable row level security;
revoke all on public.server_access from public,anon,authenticated;
grant select on public.server_access to authenticated;
drop policy if exists server_access_read on public.server_access;
create policy server_access_read on public.server_access for select to authenticated
using(public.hyn_is_super_admin() or (public.hyn_is_active() and viewer_id=auth.uid()));
create table if not exists public.server_access_events (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  actor uuid references public.profiles(id) on delete set null,
  viewer_id uuid references public.profiles(id) on delete set null,
  node_id uuid references public.nodes(id) on delete set null,
  allowed boolean not null
);
alter table public.server_access_events enable row level security;
revoke all on public.server_access_events from public,anon,authenticated;
grant select on public.server_access_events to authenticated;
drop policy if exists server_access_events_read on public.server_access_events;
create policy server_access_events_read on public.server_access_events for select to authenticated using(public.hyn_is_super_admin());

create or replace function public.hyn_can_view_node(p_node uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and exists(
    select 1 from public.nodes n join public.profiles p on p.id=n.owner
    where n.id=p_node and not n.revoked and (public.hyn_is_admin() or (p.status='active' and
      coalesce((select a.allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),
        public.hyn_can_view_dashboard(n.owner))))
  );
$$;
create or replace function public.hyn_admin_set_server_access(p_viewer uuid,p_node uuid,p_allow boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_old boolean;
begin
  perform public._hyn_require_admin();
  if p_allow is null then raise exception 'choose whether to allow access'; end if;
  perform 1 from public.profiles where id=p_viewer and status='active' and role in ('viewer','monitor') for update;
  if not found then raise exception 'choose an active Viewer or Monitor'; end if;
  perform 1 from public.nodes where id=p_node and revoked=false for update;
  if not found then raise exception 'server unavailable'; end if;
  select allowed into v_old from public.server_access where viewer_id=p_viewer and node_id=p_node;
  if v_old is not distinct from p_allow then return; end if;
  insert into public.server_access(viewer_id,node_id,allowed,granted_by) values(p_viewer,p_node,p_allow,auth.uid())
    on conflict(viewer_id,node_id) do update set allowed=excluded.allowed,granted_by=excluded.granted_by,updated_at=now();
  insert into public.server_access_events(actor,viewer_id,node_id,allowed) values(auth.uid(),p_viewer,p_node,p_allow);
end $$;
create or replace function public.hyn_dashboard_accounts()
returns json language sql stable security definer set search_path=public as $$
  select coalesce(json_agg(json_build_object('id',p.id,
    'name',case when p.id=auth.uid() then 'My dashboard' else coalesce(nullif(p.full_name,''),'Shared dashboard '||left(p.id::text,8)) end,
    'own',p.id=auth.uid(),'relayers',public.hyn_can_view_dashboard(p.id)) order by (p.id=auth.uid()) desc,p.full_name,p.id),'[]'::json)
  from public.profiles p where public.hyn_can_view_dashboard(p.id) or exists(
    select 1 from public.nodes n where n.owner=p.id and public.hyn_can_view_node(n.id));
$$;
drop policy if exists nodes_select_own on public.nodes;
create policy nodes_select_own on public.nodes for select to authenticated using(public.hyn_can_view_node(id));
drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists node_commands_select_own on public.node_commands;
create policy node_commands_select_own on public.node_commands for select to authenticated using(public.hyn_can_view_node(node_id));
create or replace function public.hyn_request_node_command(
  p_node_id uuid,
  p_command text
)
returns json language plpgsql security definer set search_path = public as $$
declare v_command public.node_commands; v_created boolean := false;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  -- Separated from the authentication check: "not authenticated" sent a signed-in
  -- customer whose account had been suspended to look for a login problem.
  if not public.hyn_is_active() then
    raise exception 'this account is suspended, so it cannot send commands to its machines';
  end if;
  if p_command not in ('update', 'sync') then raise exception 'invalid command'; end if;
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if p_command='update' and not public.hyn_is_super_admin() then raise exception 'super administrator role required'; end if;
  if not public.hyn_can_view_node(p_node_id) then
    raise exception 'dashboard access required';
  end if;
  perform public._hyn_command_node(p_node_id, null);
  select * into v_command from public.node_commands
   where node_id = p_node_id and command = p_command and status in ('queued', 'running')
   order by requested_at desc limit 1;
  if not found then
    insert into public.node_commands (node_id, requested_by, command, message)
    values (
      p_node_id, auth.uid(), p_command,
      case when p_command = 'sync' then 'Waiting for the machine to synchronize'
           else 'Waiting for the machine to check in' end
    ) returning * into v_command;
    v_created := true;
  end if;
  return json_build_object(
    'id', v_command.id, 'node_id', v_command.node_id,
    'action', v_command.command, 'status', v_command.status,
    'stage', v_command.stage, 'message', v_command.message,
    'target_version', v_command.target_version, 'result_version', v_command.result_version,
    'requested_at', v_command.requested_at, 'started_at', v_command.started_at,
    'finished_at', v_command.finished_at, 'updated_at', v_command.updated_at,
    'created', v_created
  );
end;
$$;


-- Only daily aggregates and the latest counter baseline are retained. Detailed
-- telemetry stays local. Values measure the selected WAN interface, not billing.
create table if not exists public.bandwidth_counters (
  node_id uuid primary key references public.nodes(id) on delete cascade,
  iface text not null, boot_id text not null,
  rx numeric(20,0) not null, tx numeric(20,0) not null,
  sampled_at timestamptz not null
);
create table if not exists public.bandwidth_daily (
  node_id uuid not null references public.nodes(id) on delete cascade,
  day date not null,
  ingress_bytes numeric(24,0) not null default 0 check(ingress_bytes>=0),
  egress_bytes numeric(24,0) not null default 0 check(egress_bytes>=0),
  samples integer not null default 0,
  incomplete boolean not null default false,
  estimated boolean not null default false,
  primary key(node_id,day)
);
alter table public.bandwidth_counters enable row level security;
alter table public.bandwidth_daily enable row level security;
revoke all on public.bandwidth_counters,public.bandwidth_daily from public,anon,authenticated;
grant select on public.bandwidth_counters,public.bandwidth_daily to authenticated;
drop policy if exists bandwidth_counters_read on public.bandwidth_counters;
create policy bandwidth_counters_read on public.bandwidth_counters for select to authenticated using(public.hyn_can_view_node(node_id));
drop policy if exists bandwidth_daily_read on public.bandwidth_daily;
create policy bandwidth_daily_read on public.bandwidth_daily for select to authenticated using(public.hyn_can_view_node(node_id));

create or replace function public.hyn_record_bandwidth(p_node_token text,p_iface text,p_boot_id text,p_rx numeric,p_tx numeric)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare n public.nodes; prev public.bandwidth_counters; t timestamptz:=clock_timestamp();
  rx numeric:=0; tx numeric:=0; bad boolean:=false; split boolean:=false;
  cursor_ts timestamptz; until_ts timestamptz; fraction numeric; part_rx numeric; part_tx numeric;
  remaining_rx numeric; remaining_tx numeric;
begin
  select * into n from public.nodes where token_hash=public._hyn_sha256(p_node_token) for update;
  if not found then raise exception 'invalid node token'; end if;
  if n.revoked then raise exception 'node revoked'; end if;
  if n.status<>'active' or not exists(select 1 from public.profiles where id=n.owner and status='active') then raise exception 'node or account suspended'; end if;
  if p_iface is null or p_iface !~ '^[a-zA-Z0-9_.:-]{1,64}$' or p_boot_id is null or p_boot_id !~ '^[a-zA-Z0-9-]{1,64}$'
    or p_rx is null or p_tx is null or p_rx<0 or p_tx<0 or p_rx>18446744073709551615 or p_tx>18446744073709551615
    or p_rx<>trunc(p_rx) or p_tx<>trunc(p_tx) then raise exception 'invalid network counters'; end if;
  select * into prev from public.bandwidth_counters where node_id=n.id;
  if not found or prev.iface<>p_iface or prev.boot_id<>p_boot_id or p_rx<prev.rx or p_tx<prev.tx then
    bad:=true;
  else
    rx:=p_rx-prev.rx; tx:=p_tx-prev.tx;
  end if;
  -- Ignore immediate duplicate/reordered requests rather than moving a baseline
  -- backwards. A changed boot/interface is a new baseline and counts no bytes.
  if prev.node_id is not null and prev.iface=p_iface and prev.boot_id=p_boot_id and (p_rx<prev.rx or p_tx<prev.tx)
     and t-prev.sampled_at<interval '30 seconds' then return json_build_object('status','ignored'); end if;
  if prev.node_id is not null and t-prev.sampled_at>interval '3 minutes' then bad:=true; end if;
  -- Very long gaps cannot be assigned to days reliably; retain a new baseline.
  if prev.node_id is not null and t-prev.sampled_at>interval '7 days' then rx:=0; tx:=0; end if;
  cursor_ts:=case when rx+tx>0 then prev.sampled_at else t end;
  split:=(cursor_ts at time zone 'UTC')::date<>(t at time zone 'UTC')::date;
  remaining_rx:=rx; remaining_tx:=tx;
  loop
    until_ts:=least(t,(((cursor_ts at time zone 'UTC')::date+1)::timestamp at time zone 'UTC'));
    fraction:=case when t=cursor_ts or prev.sampled_at is null then 1 else extract(epoch from until_ts-cursor_ts)/nullif(extract(epoch from t-prev.sampled_at),0) end;
    part_rx:=case when until_ts=t then remaining_rx else floor(rx*fraction) end;
    part_tx:=case when until_ts=t then remaining_tx else floor(tx*fraction) end;
    insert into public.bandwidth_daily(node_id,day,ingress_bytes,egress_bytes,samples,incomplete,estimated)
      values(n.id,(cursor_ts at time zone 'UTC')::date,part_rx,part_tx,1,bad,split)
      on conflict(node_id,day) do update set ingress_bytes=bandwidth_daily.ingress_bytes+excluded.ingress_bytes,
        egress_bytes=bandwidth_daily.egress_bytes+excluded.egress_bytes,samples=bandwidth_daily.samples+1,
        incomplete=bandwidth_daily.incomplete or excluded.incomplete,estimated=bandwidth_daily.estimated or excluded.estimated;
    exit when until_ts=t;
    remaining_rx:=remaining_rx-part_rx; remaining_tx:=remaining_tx-part_tx; cursor_ts:=until_ts;
  end loop;
  insert into public.bandwidth_counters values(n.id,p_iface,p_boot_id,p_rx,p_tx,t)
    on conflict(node_id) do update set iface=excluded.iface,boot_id=excluded.boot_id,rx=excluded.rx,tx=excluded.tx,sampled_at=excluded.sampled_at;
  return json_build_object('status','ok');
end $$;
create or replace function public.hyn_bandwidth_report(p_node uuid,p_days integer default 30)
returns json language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_can_view_node(p_node) then raise exception 'server access required'; end if;
  if p_days is null or p_days<1 or p_days>366 then raise exception 'choose 1 to 366 days'; end if;
  return json_build_object(
    'iface',(select iface from public.bandwidth_counters where node_id=p_node),
    'sampled_at',(select sampled_at from public.bandwidth_counters where node_id=p_node),
    'since',(select min(day) from public.bandwidth_daily where node_id=p_node),
    'ingress_bytes',(select coalesce(sum(ingress_bytes),0)::text from public.bandwidth_daily where node_id=p_node),
    'egress_bytes',(select coalesce(sum(egress_bytes),0)::text from public.bandwidth_daily where node_id=p_node),
    'days',(select coalesce(json_agg(json_build_object('day',day,'ingress_bytes',ingress_bytes::text,'egress_bytes',egress_bytes::text,
      'samples',samples,'incomplete',incomplete,'estimated',estimated) order by day desc),'[]'::json)
      from public.bandwidth_daily where node_id=p_node and day>=(now() at time zone 'UTC')::date-(p_days-1)));
end $$;
revoke all on function public.hyn_can_view_node(uuid) from public,anon;
grant execute on function public.hyn_can_view_node(uuid) to authenticated;
revoke all on function public.hyn_admin_set_server_access(uuid,uuid,boolean) from public,anon;
grant execute on function public.hyn_admin_set_server_access(uuid,uuid,boolean) to authenticated;
revoke all on function public.hyn_record_bandwidth(text,text,text,numeric,numeric) from public;
grant execute on function public.hyn_record_bandwidth(text,text,text,numeric,numeric) to anon,authenticated;
revoke all on function public.hyn_bandwidth_report(uuid,integer) from public,anon;
grant execute on function public.hyn_bandwidth_report(uuid,integer) to authenticated;
-- Batch assignment is atomic: one invalid account rolls back the entire grant.
create or replace function public.hyn_admin_share_server(p_viewers uuid[],p_node uuid,p_allow boolean,p_notify boolean default true)
returns json language plpgsql security definer set search_path=public as $$
declare v_viewer uuid; v_count integer:=0; v_previous boolean;
begin
  perform public._hyn_require_admin();
  if p_viewers is null or cardinality(p_viewers) not between 1 and 100 or p_notify is null then
    raise exception 'choose 1 to 100 users and a notification permission';
  end if;
  for v_viewer in select distinct unnest(p_viewers) order by 1 loop
    perform public.hyn_admin_set_server_access(v_viewer,p_node,p_allow);
    select notifications_allowed into v_previous from public.server_access where viewer_id=v_viewer and node_id=p_node;
    update public.server_access set notifications_allowed=p_notify where viewer_id=v_viewer and node_id=p_node;
    if v_previous is distinct from p_notify then
      perform public._hyn_audit('server_access.notifications',v_viewer,p_node,jsonb_build_object('allowed',p_notify));
    end if;
    v_count:=v_count+1;
  end loop;
  return json_build_object('updated',v_count);
end $$;

create or replace function public.hyn_fleet_bandwidth_report(p_days integer default 30)
returns json language plpgsql stable security definer set search_path=public as $$
declare result json;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  if p_days is null or p_days<1 or p_days>366 then raise exception 'choose 1 to 366 days'; end if;
  with visible as materialized (
    select id from public.nodes where not revoked and not is_demo and public.hyn_can_view_node(id)
  ), totals as (
    select min(day) since,coalesce(sum(ingress_bytes),0)::text ingress_bytes,
      coalesce(sum(egress_bytes),0)::text egress_bytes from public.bandwidth_daily where node_id in(select id from visible)
  ), days as (
    select day,sum(ingress_bytes)::text ingress_bytes,sum(egress_bytes)::text egress_bytes,
      sum(samples) samples,bool_or(incomplete) incomplete,bool_or(estimated) estimated
    from public.bandwidth_daily where node_id in(select id from visible)
      and day>=(now() at time zone 'UTC')::date-(p_days-1) group by day
  )
  select json_build_object('iface',null,'node_count',(select count(*) from visible),
    'reporting_count',(select count(*) from public.bandwidth_counters where node_id in(select id from visible)),
    'stale_count',(select count(*) from public.bandwidth_counters where node_id in(select id from visible) and sampled_at<now()-interval '3 minutes'),
    'sampled_at',(select max(sampled_at) from public.bandwidth_counters where node_id in(select id from visible)),
    'since',totals.since,'ingress_bytes',totals.ingress_bytes,'egress_bytes',totals.egress_bytes,
    'days',(select coalesce(json_agg(days order by day desc),'[]'::json) from days)) into result from totals;
  return result;
end $$;

-- The inbox exposes server events, never another user's delivery addresses.
-- Results are derived from current access on every read, including revocation.
create or replace function public.hyn_server_notifications(p_limit integer default 50)
returns json language plpgsql stable security definer set search_path=public as $$
declare result json;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'choose 1 to 100 notifications'; end if;
  with visible as materialized (
    select n.id,n.owner,n.name,n.status,n.config,n.agent_version,
      coalesce(n.last_heartbeat_at,n.last_config_pull_at,n.last_seen_at,n.created_at) heartbeat_at
    from public.nodes n where not n.revoked and not n.is_demo and public.hyn_can_view_node(n.id)
      and (public.hyn_is_admin() or coalesce((select a.notifications_allowed from public.server_access a
        where a.viewer_id=auth.uid() and a.node_id=n.id),true))
  ), events as (
    select 'alert:'||a.id::text id,n.id node_id,n.owner,n.name node_name,a.ts,a.severity,
      a.message,case when a.resolved then 'resolved' else 'alert' end kind
    from visible n cross join lateral (
      select * from public.alert_events where node_id=n.id and ts>now()-interval '7 days' order by ts desc limit 50
    ) a
    union all
    select 'command:'||c.id::text,n.id,n.owner,n.name,c.finished_at,
      case when c.status='failed' then 'warn' else 'info' end,
      case when c.command='update' then 'Agent update ' else 'Reading refresh ' end||c.status||coalesce(': '||c.message,''),'command'
    from visible n cross join lateral (
      select * from public.node_commands where node_id=n.id and status in('succeeded','failed')
        and finished_at>now()-interval '7 days' order by finished_at desc limit 20
    ) c
    union all
    select 'heartbeat:'||n.id::text||':'||n.heartbeat_at::text,n.id,n.owner,n.name,n.heartbeat_at,'crit',
      'No recent heartbeat. The server may be offline; displayed readings can be stale.','offline'
    from visible n where n.status='active' and n.heartbeat_at < now()-make_interval(secs=>
      case when coalesce(n.agent_version,'') ~ '^1\.[0-6]\.' or n.agent_version is null
        then greatest(900,case when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
          then least((n.config->>'cloud_push_min')::integer,1440)*180 else 1800 end)
        else 900 end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result
    from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;

revoke all on function public.hyn_admin_share_server(uuid[],uuid,boolean,boolean) from public,anon;
revoke all on function public.hyn_fleet_bandwidth_report(integer) from public,anon;
revoke all on function public.hyn_server_notifications(integer) from public,anon;
grant execute on function public.hyn_admin_share_server(uuid[],uuid,boolean,boolean) to authenticated;
grant execute on function public.hyn_fleet_bandwidth_report(integer) to authenticated;
grant execute on function public.hyn_server_notifications(integer) to authenticated;

notify pgrst,'reload schema';
commit;

-- HYN SELF-SERVICE OWNER LINKING
-- Self-service pairing establishes ownership. Sharing grants are for other users.
begin;
create or replace function public.hyn_can_link()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and status='active'
    and role in ('monitor','admin','super_admin'));
$$;
revoke all on function public.hyn_can_link() from public,anon;
grant execute on function public.hyn_can_link() to authenticated;

create or replace function public._hyn_require_linker()
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.hyn_can_link() then
    raise exception 'an active Monitor, Admin or Super admin account is required to link a server';
  end if;
end;
$$;
revoke all on function public._hyn_require_linker() from public,anon,authenticated;

create or replace function public.hyn_device_approve(
  p_user_code text,
  p_node_name text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_node_id uuid;
  v_node_token text;
  v_uid uuid := auth.uid();
begin
  perform public._hyn_require_linker();
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  -- Global cleanup always precedes the single-row approval lock. Purge workers
  -- use ordered SKIP LOCKED scans, eliminating cross-row lock cycles.
  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  v_node_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.nodes (owner, name, hostname, os, agent_version, token_hash)
  values (
    v_uid,
    coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node'),
    v.hostname, v.os, v.agent_version,
    public._hyn_sha256(v_node_token)
  )
  returning id into v_node_id;

  update public.device_codes
     set approved_by = v_uid,
         node_id = v_node_id,
         node_token_hash = public._hyn_sha256(v_node_token)
   where id = v.id;

  -- The plaintext token is handed to the polling server, not to this browser.
  -- Stashing it here (hashed) is what lets the poll succeed exactly once.
  return json_build_object(
    'status', 'approved',
    'node_id', v_node_id,
    'node_name', coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node')
  );
end;
$$;

create or replace function public.hyn_claim_device_linked_email(p_node_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_node public.nodes; v_recipient text; v_key text;
begin
  perform public._hyn_require_linker();
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_node from public.nodes
   where id = p_node_id and owner = auth.uid() and revoked = false and is_demo = false;
  if not found then raise exception 'node not found'; end if;
  select recipient into v_recipient from public.email_preferences where node_id = v_node.id;
  if not found then return json_build_object('status', 'skip', 'reason', 'email preference missing'); end if;
  v_key := 'device-linked:' || v_node.id::text;
  insert into public.cloud_email_dispatches (idempotency_key, node_id, kind)
  values (v_key, v_node.id, 'system') on conflict (idempotency_key) do nothing;
  if not found then return json_build_object('status', 'skip', 'reason', 'already sent'); end if;
  return json_build_object(
    'status', 'send', 'node_id', v_node.id, 'node_name', v_node.name,
    'hostname', v_node.hostname, 'os', v_node.os, 'agent_version', v_node.agent_version,
    'recipient', v_recipient, 'linked_at', v_node.created_at
  );
end;
$$;

create or replace function public.hyn_complete_device_linked_email(p_node_id uuid, p_provider_id text default null)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_linker();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  update public.cloud_email_dispatches set provider_id = left(nullif(p_provider_id, ''), 200)
   where idempotency_key = 'device-linked:' || p_node_id::text and node_id = p_node_id;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_release_device_linked_email(p_node_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform public._hyn_require_linker();
  if auth.uid() is null or not exists (
    select 1 from public.nodes where id = p_node_id and owner = auth.uid()
  ) then raise exception 'node not found'; end if;
  delete from public.cloud_email_dispatches
   where idempotency_key = 'device-linked:' || p_node_id::text
     and node_id = p_node_id and provider_id is null;
  return json_build_object('status', 'ok');
end;
$$;

create or replace function public.hyn_can_view_node(p_node uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.hyn_is_active() and exists(
    select 1 from public.nodes n join public.profiles p on p.id=n.owner
    where n.id=p_node and not n.revoked and (public.hyn_is_admin() or (p.status='active' and
      (n.owner=auth.uid() or coalesce(
        (select a.allowed from public.server_access a where a.viewer_id=auth.uid() and a.node_id=n.id),
        public.hyn_can_view_dashboard(n.owner)))))
  );
$$;

create or replace function public.hyn_admin_set_server_access(p_viewer uuid,p_node uuid,p_allow boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_old boolean;
begin
  perform public._hyn_require_admin();
  if p_allow is null then raise exception 'choose whether to allow access'; end if;
  perform 1 from public.profiles where id=p_viewer and status='active' and role in ('viewer','monitor') for update;
  if not found then raise exception 'choose an active Viewer or Monitor'; end if;
  perform 1 from public.nodes where id=p_node and revoked=false for update;
  if not found then raise exception 'server unavailable'; end if;
  if exists(select 1 from public.nodes where id=p_node and owner=p_viewer) then
    raise exception 'the owner already has access; choose another user';
  end if;
  select allowed into v_old from public.server_access where viewer_id=p_viewer and node_id=p_node;
  if v_old is not distinct from p_allow then return; end if;
  insert into public.server_access(viewer_id,node_id,allowed,granted_by) values(p_viewer,p_node,p_allow,auth.uid())
    on conflict(viewer_id,node_id) do update set allowed=excluded.allowed,granted_by=excluded.granted_by,updated_at=now();
  insert into public.server_access_events(actor,viewer_id,node_id,allowed) values(auth.uid(),p_viewer,p_node,p_allow);
end $$;
create or replace function public.hyn_server_notifications(p_limit integer default 50)
returns json language plpgsql stable security definer set search_path=public as $$
declare result json;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'choose 1 to 100 notifications'; end if;
  with visible as materialized (
    select n.id,n.owner,n.name,n.status,n.config,n.agent_version,
      coalesce(n.last_heartbeat_at,n.last_config_pull_at,n.last_seen_at,n.created_at) heartbeat_at
    from public.nodes n where not n.revoked and not n.is_demo and public.hyn_can_view_node(n.id)
      and (n.owner=auth.uid() or public.hyn_is_admin() or coalesce((select a.notifications_allowed from public.server_access a
        where a.viewer_id=auth.uid() and a.node_id=n.id),true))
  ), events as (
    select 'alert:'||a.id::text id,n.id node_id,n.owner,n.name node_name,a.ts,a.severity,
      a.message,case when a.resolved then 'resolved' else 'alert' end kind
    from visible n cross join lateral (
      select * from public.alert_events where node_id=n.id and ts>now()-interval '7 days' order by ts desc limit 50
    ) a
    union all
    select 'command:'||c.id::text,n.id,n.owner,n.name,c.finished_at,
      case when c.status='failed' then 'warn' else 'info' end,
      case when c.command='update' then 'Agent update ' else 'Reading refresh ' end||c.status||coalesce(': '||c.message,''),'command'
    from visible n cross join lateral (
      select * from public.node_commands where node_id=n.id and status in('succeeded','failed')
        and finished_at>now()-interval '7 days' order by finished_at desc limit 20
    ) c
    union all
    select 'heartbeat:'||n.id::text||':'||n.heartbeat_at::text,n.id,n.owner,n.name,n.heartbeat_at,'crit',
      'No recent heartbeat. The server may be offline; displayed readings can be stale.','offline'
    from visible n where n.status='active' and n.heartbeat_at < now()-make_interval(secs=>
      case when coalesce(n.agent_version,'') ~ '^1\.[0-6]\.' or n.agent_version is null
        then greatest(900,case when n.config->>'cloud_push_min' ~ '^[1-9][0-9]{0,3}$'
          then least((n.config->>'cloud_push_min')::integer,1440)*180 else 1800 end)
        else 900 end)
  )
  select coalesce(json_agg(e order by ts desc,id),'[]'::json) into result
    from (select * from events order by ts desc,id limit p_limit) e;
  return result;
end $$;
notify pgrst, 'reload schema';
commit;
-- Account assignment controls ownership; an explicit link identifies the server.
begin;

create unique index if not exists nodes_id_owner_key on public.nodes(id, owner);
create unique index if not exists relayer_assignments_id_owner_key on public.relayer_assignments(id, owner);

create table if not exists public.node_relayer_links (
  node_id uuid primary key,
  owner uuid not null,
  assignment_id uuid not null unique,
  linked_at timestamptz not null default now(),
  linked_by uuid references auth.users(id) on delete set null,
  foreign key (node_id, owner) references public.nodes(id, owner) on delete cascade,
  foreign key (assignment_id, owner) references public.relayer_assignments(id, owner) on delete cascade
);
create index if not exists node_relayer_links_owner_idx on public.node_relayer_links(owner);
alter table public.node_relayer_links enable row level security;
revoke all on public.node_relayer_links from public, anon, authenticated;
grant select (node_id, owner, assignment_id, linked_at) on public.node_relayer_links to authenticated;
drop policy if exists node_relayer_links_read on public.node_relayer_links;
create policy node_relayer_links_read on public.node_relayer_links
  for select to authenticated using (public.hyn_can_view_node(node_id));

create or replace function public.hyn_admin_set_node_relayer(p_node_id uuid, p_assignment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_owner uuid; v_previous uuid; v_relayer_id integer;
begin
  v_actor := public._hyn_require_admin();
  select owner into v_owner from public.nodes
    where id = p_node_id and not revoked and not is_demo for update;
  if not found then raise exception 'Choose an available, non-demo server'; end if;
  select assignment_id into v_previous from public.node_relayer_links where node_id = p_node_id;
  if v_previous is not distinct from p_assignment_id then return; end if;

  if p_assignment_id is null then
    delete from public.node_relayer_links where node_id = p_node_id;
  else
    if not exists(select 1 from public.profiles where id = v_owner and status = 'active') then
      raise exception 'Restore this account before linking a relayer';
    end if;
    -- Lock the assignment as well as the server so concurrent links cannot move it.
    select relayer_id into v_relayer_id from public.relayer_assignments
      where id = p_assignment_id and owner = v_owner for update;
    if not found then raise exception 'Choose a relayer assigned to this server''s account'; end if;
    if exists(select 1 from public.node_relayer_links where assignment_id = p_assignment_id and node_id <> p_node_id) then
      raise exception 'This relayer is linked to another server. Unlink it there first' using errcode = 'PT409';
    end if;
    insert into public.node_relayer_links(node_id, owner, assignment_id, linked_by)
      values (p_node_id, v_owner, p_assignment_id, v_actor)
      on conflict (node_id) do update set assignment_id = excluded.assignment_id,
        owner = excluded.owner, linked_by = excluded.linked_by, linked_at = now();
  end if;
  perform public._hyn_audit(
    case when p_assignment_id is null then 'node.relayer.unlink' else 'node.relayer.link' end,
    v_owner, p_node_id,
    jsonb_build_object('assignment_id', p_assignment_id, 'previous_assignment_id', v_previous, 'relayer_id', v_relayer_id)
  );
end;
$$;

-- A server share exposes exactly its linked relay, without granting access to
-- the owner's other relayers or changing account-level assignment policies.
create or replace function public.hyn_node_relayer(p_node uuid)
returns table(id uuid, owner uuid, relayer_id integer, relayer_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.hyn_can_view_node(p_node) then
    raise exception 'Server unavailable' using errcode = '42501';
  end if;
  return query select a.id, a.owner, a.relayer_id, a.relayer_name, a.created_at
    from public.node_relayer_links l
    join public.relayer_assignments a on a.id = l.assignment_id and a.owner = l.owner
    where l.node_id = p_node;
end;
$$;

revoke all on function public.hyn_admin_set_node_relayer(uuid, uuid) from public, anon;
revoke all on function public.hyn_node_relayer(uuid) from public, anon;
grant execute on function public.hyn_admin_set_node_relayer(uuid, uuid) to authenticated;
grant execute on function public.hyn_node_relayer(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
-- Save one user's explicit server set atomically, preserving other users.
begin;
create or replace function public.hyn_admin_set_user_servers(p_viewer uuid, p_nodes uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid; v_nodes uuid[]; v_previous uuid[]; v_shares integer;
begin
  v_actor := public._hyn_require_admin();
  perform 1 from public.profiles where id = p_viewer and status = 'active'
    and role in ('viewer', 'monitor') for update;
  if not found then raise exception 'Choose an active Viewer or Monitor'; end if;
  if p_nodes is null or array_position(p_nodes, null) is not null then
    raise exception 'Choose a valid list of servers';
  end if;
  select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_nodes from unnest(p_nodes) id;
  perform 1 from public.nodes where id = any(v_nodes) order by id for update;
  if (select count(*) from public.nodes n join public.profiles p on p.id = n.owner
      where n.id = any(v_nodes) and not n.revoked and not n.is_demo and p.status = 'active') <> cardinality(v_nodes) then
    raise exception 'One or more selected servers are unavailable. Refresh and try again';
  end if;
  -- Owners retain their own machines independently of additional assignments.
  select coalesce(array_agg(n.id order by n.id), '{}'::uuid[]) into v_nodes
    from public.nodes n where n.id = any(v_nodes) and n.owner <> p_viewer;
  select coalesce(array_agg(n.id order by n.id), '{}'::uuid[]) into v_previous
    from public.nodes n join public.profiles p on p.id = n.owner
    where n.owner <> p_viewer and not n.revoked and not n.is_demo and p.status = 'active'
      and coalesce((select a.allowed from public.server_access a where a.viewer_id = p_viewer and a.node_id = n.id),
        exists(select 1 from public.dashboard_access d where d.viewer_id = p_viewer and d.owner_id = n.owner));

  -- Convert inherited dashboard sharing into the exact selection shown in the
  -- editor, so unselected siblings and future servers do not remain visible.
  delete from public.dashboard_access where viewer_id = p_viewer;
  get diagnostics v_shares = row_count;
  delete from public.server_access where viewer_id = p_viewer and not (node_id = any(v_nodes));
  insert into public.server_access(viewer_id, node_id, allowed, granted_by)
    select p_viewer, id, true, v_actor from unnest(v_nodes) id
    on conflict (viewer_id, node_id) do update set allowed = true,
      granted_by = excluded.granted_by, updated_at = now();
  -- Updating an existing row leaves its notification preference untouched.
  insert into public.server_access_events(actor, viewer_id, node_id, allowed)
    select v_actor, p_viewer, id, true from unnest(v_nodes) id where not (id = any(v_previous))
    union all
    select v_actor, p_viewer, id, false from unnest(v_previous) id where not (id = any(v_nodes));
  if v_nodes is distinct from v_previous or v_shares > 0 then
    perform public._hyn_audit('user.servers.assign', p_viewer, null,
      jsonb_build_object('node_ids', v_nodes, 'previous_node_ids', v_previous, 'dashboard_shares_replaced', v_shares));
  end if;
  return jsonb_build_object('node_ids', v_nodes);
end;
$$;
revoke all on function public.hyn_admin_set_user_servers(uuid, uuid[]) from public, anon;
grant execute on function public.hyn_admin_set_user_servers(uuid, uuid[]) to authenticated;
notify pgrst, 'reload schema';
commit;
-- Managed email budgets, an append-only attempt history, and user digests.
-- Existing email preferences are not enabled, disabled, or deleted by this migration.
begin;

create table if not exists public.delivery_rules (
  scope text not null,
  owner uuid references public.profiles(id) on delete cascade,
  kind text not null check(kind in('all','daily','incident','system','command','signin','device','first_report','admin_report','other')),
  enabled boolean not null default true,
  daily_limit integer check(daily_limit between 0 and 100000),
  max_attempts integer not null default 3 check(max_attempts between 1 and 5),
  retry_minutes integer not null default 15 check(retry_minutes between 1 and 1440),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(scope,kind),
  check((scope='global' and owner is null) or (owner is not null and scope=owner::text))
);
insert into public.delivery_rules(scope,kind) values('global','all') on conflict do nothing;
create table if not exists public.delivery_digest_settings (
  scope text primary key,
  owner uuid references public.profiles(id) on delete cascade,
  configured boolean not null default false,
  enabled boolean not null default false,
  send_at time not null default '08:00',
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now(),
  check((scope='global' and owner is null) or (owner is not null and scope=owner::text))
);
insert into public.delivery_digest_settings(scope) values('global') on conflict do nothing;
create table if not exists public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique check(length(source_key) between 1 and 500),
  owner uuid not null references public.profiles(id) on delete cascade,
  node_id uuid references public.nodes(id) on delete set null,
  node_label text,
  kind text not null check(kind in('daily','incident','system','command','signin','device','first_report','admin_report','other')),
  recipient text not null,
  subject text not null,
  status text not null default 'pending' check(status in('pending','sending','sent','failed','suppressed','cancelled','unknown')),
  reason text,
  attempt_count integer not null default 0,
  attempt_limit integer not null default 3,
  retry_minutes integer not null default 15,
  terminal boolean not null default false,
  next_retry_at timestamptz,
  last_attempt uuid,
  provider_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.delivery_events(id) on delete cascade,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'sending' check(status in('sending','sent','failed','unknown')),
  provider_id text,
  error text
);
create index if not exists delivery_attempts_day_idx on public.delivery_attempts(started_at,event_id);
create index if not exists delivery_attempts_event_idx on public.delivery_attempts(event_id,started_at);
create index if not exists delivery_events_owner_idx on public.delivery_events(owner,updated_at desc);
create index if not exists delivery_events_updated_idx on public.delivery_events(updated_at desc);
alter table public.delivery_rules enable row level security;
alter table public.delivery_digest_settings enable row level security;
alter table public.delivery_events enable row level security;
alter table public.delivery_attempts enable row level security;
revoke all on public.delivery_rules,public.delivery_digest_settings,public.delivery_events,public.delivery_attempts from public,anon,authenticated;

create or replace function public._hyn_digest_setting(p_owner uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce((select to_jsonb(s) from public.delivery_digest_settings s where s.owner=p_owner),
    (select to_jsonb(s) from public.delivery_digest_settings s where s.scope='global'));
$$;

-- Equivalent to current server visibility, with the notification opt-out also
-- applied. Never adopt an arbitrary owner's entire fleet for a shared viewer.
create or replace function public._hyn_digest_nodes(p_owner uuid)
returns setof public.nodes language sql stable security definer set search_path=public as $$
  select n.* from public.profiles viewer cross join public.nodes n
    join public.profiles owner_profile on owner_profile.id=n.owner
  where viewer.id=p_owner and viewer.status='active' and not n.revoked and not n.is_demo
    and (viewer.role in('admin','super_admin') or (owner_profile.status='active' and
      (n.owner=p_owner or coalesce((select a.allowed from public.server_access a where a.viewer_id=p_owner and a.node_id=n.id),
        exists(select 1 from public.dashboard_access d where d.viewer_id=p_owner and d.owner_id=n.owner)))))
    and (n.owner=p_owner or viewer.role in('admin','super_admin') or coalesce(
      (select a.notifications_allowed from public.server_access a where a.viewer_id=p_owner and a.node_id=n.id),true));
$$;

create or replace function public.hyn_admin_set_delivery_rules(p_owner uuid,p_rules jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r jsonb; v_scope text:=coalesce(p_owner::text,'global');
begin
  perform public._hyn_require_admin();
  if p_owner is not null and not exists(select 1 from public.profiles where id=p_owner and status='active') then raise exception 'choose an active user'; end if;
  if p_rules is null or jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules) not between 1 and 10 then raise exception 'choose valid delivery rules'; end if;
  if (select count(*) from jsonb_array_elements(p_rules))<>(select count(distinct value->>'kind') from jsonb_array_elements(p_rules)) then raise exception 'duplicate delivery types'; end if;
  for r in select value from jsonb_array_elements(p_rules) loop
    if jsonb_typeof(r->'enabled') is distinct from 'boolean' or jsonb_typeof(r->'max_attempts') is distinct from 'number'
      or jsonb_typeof(r->'retry_minutes') is distinct from 'number'
      or coalesce(jsonb_typeof(r->'daily_limit'),'null') not in('null','number') then raise exception 'invalid delivery rule fields'; end if;
    insert into public.delivery_rules(scope,owner,kind,enabled,daily_limit,max_attempts,retry_minutes)
    values(v_scope,p_owner,r->>'kind',(r->>'enabled')::boolean,(r->>'daily_limit')::integer,(r->>'max_attempts')::integer,(r->>'retry_minutes')::integer)
    on conflict(scope,kind) do update set enabled=excluded.enabled,daily_limit=excluded.daily_limit,
      max_attempts=excluded.max_attempts,retry_minutes=excluded.retry_minutes,updated_at=now();
  end loop;
  perform public._hyn_audit('delivery.rules',p_owner,null,jsonb_build_object('rules',p_rules));
end $$;

create or replace function public.hyn_admin_set_digest(p_owner uuid,p_enabled boolean,p_at text,p_timezone text,p_inherit boolean default false,p_confirm_all boolean default false)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public._hyn_require_admin();
  if p_owner is null and p_confirm_all is distinct from true then raise exception 'confirm the global daily email change'; end if;
  if p_owner is not null and not exists(select 1 from public.profiles where id=p_owner and status='active') then raise exception 'choose an active user'; end if;
  if p_inherit then
    if p_owner is null then raise exception 'global settings cannot inherit'; end if;
    delete from public.delivery_digest_settings where owner=p_owner;
  else
    if p_enabled is null or p_at is null or p_at !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'choose a valid time and timezone'; end if;
    insert into public.delivery_digest_settings(scope,owner,configured,enabled,send_at,timezone)
    values(coalesce(p_owner::text,'global'),p_owner,true,p_enabled,p_at::time,p_timezone)
    on conflict(scope) do update set configured=true,enabled=excluded.enabled,send_at=excluded.send_at,timezone=excluded.timezone,updated_at=now();
  end if;
  perform public._hyn_audit('delivery.daily_digest',p_owner,null,jsonb_build_object('enabled',p_enabled,'at',p_at,'timezone',p_timezone,'inherit',p_inherit));
end $$;

create or replace function public.hyn_reserve_delivery(p_key text,p_kind text,p_owner uuid,p_node uuid,p_recipient text,p_subject text,p_nodes uuid[] default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid:=p_owner; v_node public.nodes; e public.delivery_events; r public.delivery_rules;
  v_start timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
  v_reason text; v_retry timestamptz; v_limit integer:=5; v_wait integer:=1; v_used bigint;
  v_attempt uuid; v_allowed uuid[]; v_requested uuid[]; v_setting jsonb;
begin
  if p_key is null or length(p_key) not between 1 and 500 or p_kind is null or p_kind not in('daily','incident','system','command','signin','device','first_report','admin_report','other')
    or p_recipient is null or length(p_recipient)>320 or p_recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_subject is null or length(p_subject) not between 1 and 500 then raise exception 'invalid managed delivery'; end if;
  if p_node is not null then
    select * into v_node from public.nodes where id=p_node and not revoked and not is_demo;
    if not found or (v_owner is not null and v_owner<>v_node.owner) then return jsonb_build_object('allowed',false,'reason','Server access changed. No email was sent.'); end if;
    v_owner:=v_node.owner;
  end if;
  if not exists(select 1 from public.profiles where id=v_owner and status='active') then return jsonb_build_object('allowed',false,'reason','Recipient account is unavailable.'); end if;
  -- Serialize reservations across the provider for exact global and user caps,
  -- even when many telemetry uploads and the cron run concurrently.
  perform pg_advisory_xact_lock(hashtextextended('hyn-delivery:'||v_start::text,0));
  insert into public.delivery_events(source_key,owner,node_id,node_label,kind,recipient,subject)
    values(p_key,v_owner,p_node,v_node.name,p_kind,p_recipient,p_subject) on conflict(source_key) do nothing;
  select * into e from public.delivery_events where source_key=p_key for update;
  if e.owner<>v_owner or e.kind<>p_kind or e.recipient<>p_recipient then raise exception 'delivery identity changed'; end if;
  if e.status='sent' then return jsonb_build_object('allowed',false,'already_sent',true,'provider_id',e.provider_id); end if;
  if e.terminal then return jsonb_build_object('allowed',false,'reason',coalesce(e.reason,'Automatic retries have stopped.')); end if;
  if e.status='sending' then
    if e.updated_at<now()-interval '5 minutes' then
      update public.delivery_attempts set status='unknown',finished_at=now(),error='Worker outcome is unknown; review provider before resending.' where id=e.last_attempt and status='sending';
      update public.delivery_events set status='unknown',terminal=true,reason='Worker outcome is unknown; review provider before resending.',updated_at=now() where id=e.id;
    end if;
    return jsonb_build_object('allowed',false,'reason','A delivery attempt is already in progress or requires provider review.');
  end if;
  if e.next_retry_at>now() then return jsonb_build_object('allowed',false,'reason',coalesce(e.reason,'Waiting before retrying.')); end if;
  if p_kind='daily' then
    v_setting:=public._hyn_digest_setting(v_owner);
    if p_nodes is not null then
      select coalesce(array_agg(n.id order by n.id),'{}'::uuid[]) into v_allowed from public._hyn_digest_nodes(v_owner) n;
      select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_requested from (select distinct unnest(p_nodes) id) x;
      if not coalesce((v_setting->>'configured')::boolean,false) or not coalesce((v_setting->>'enabled')::boolean,false)
        or cardinality(v_allowed)=0 or v_allowed<>v_requested
        or p_recipient is distinct from (select email from public.profiles where id=v_owner) then
        v_reason:='Daily digest permissions or settings changed. Rebuild before sending.'; v_retry:=now()+interval '15 minutes';
      end if;
    elsif coalesce((v_setting->>'configured')::boolean,false) then
      v_reason:='Per-server daily email is replaced by this user''s combined-digest setting.';
    end if;
  end if;
  for r in select * from public.delivery_rules where scope in('global',v_owner::text) and kind in('all',p_kind) loop
    v_limit:=least(v_limit,r.max_attempts); v_wait:=greatest(v_wait,r.retry_minutes);
    if not r.enabled then v_reason:='Sending is paused by an administrator.'; v_retry:=now()+interval '15 minutes'; end if;
    if r.daily_limit is not null then
      select count(*) into v_used from public.delivery_attempts a join public.delivery_events d on d.id=a.event_id
        where a.started_at>=v_start and (r.owner is null or d.owner=r.owner) and (r.kind='all' or d.kind=r.kind);
      if v_used>=r.daily_limit then v_reason:='Daily sending cap reached. Resets at midnight UTC.'; v_retry:=v_start+interval '1 day'; end if;
    end if;
  end loop;
  if e.attempt_count>=v_limit then
    update public.delivery_events set terminal=true,status='suppressed',reason='Retry limit reached. Automatic sending stopped.',updated_at=now() where id=e.id;
    return jsonb_build_object('allowed',false,'reason','Retry limit reached. Automatic sending stopped.');
  end if;
  if v_reason is not null then
    update public.delivery_events set status='suppressed',reason=v_reason,next_retry_at=v_retry,updated_at=now() where id=e.id;
    return jsonb_build_object('allowed',false,'reason',v_reason);
  end if;
  insert into public.delivery_attempts(event_id) values(e.id) returning id into v_attempt;
  update public.delivery_events set status='sending',attempt_count=attempt_count+1,attempt_limit=v_limit,retry_minutes=v_wait,
    last_attempt=v_attempt,next_retry_at=null,reason=null,updated_at=now() where id=e.id;
  return jsonb_build_object('allowed',true,'attempt_id',v_attempt);
end $$;

create or replace function public.hyn_complete_delivery(p_attempt uuid,p_status text,p_provider_id text default null,p_error text default null)
returns void language plpgsql security definer set search_path=public as $$
declare a public.delivery_attempts; e public.delivery_events;
begin
  if p_status is null or p_status not in('sent','failed','unknown') then raise exception 'invalid delivery result'; end if;
  select * into a from public.delivery_attempts where id=p_attempt;
  if not found then raise exception 'delivery attempt not found'; end if;
  select * into e from public.delivery_events where id=a.event_id for update;
  if e.last_attempt is distinct from p_attempt or e.status<>'sending' then return; end if;
  update public.delivery_attempts set status=p_status,finished_at=now(),provider_id=left(p_provider_id,200),error=left(p_error,1000) where id=p_attempt;
  update public.delivery_events set status=p_status,provider_id=left(p_provider_id,200),
    reason=case when p_status='unknown' then 'Provider outcome is unknown. Review before resending.' when p_status='failed' and attempt_count>=attempt_limit then 'Retry limit reached. '||coalesce(left(p_error,900),'Provider rejected the message.') else left(p_error,1000) end,
    terminal=(p_status in('sent','unknown') or attempt_count>=attempt_limit),
    next_retry_at=case when p_status='failed' and attempt_count<attempt_limit then now()+make_interval(mins=>retry_minutes) else null end,
    updated_at=now() where id=e.id;
end $$;

create or replace function public.hyn_admin_stop_delivery(p_event uuid)
returns void language plpgsql security definer set search_path=public as $$
declare e public.delivery_events;
begin
  perform public._hyn_require_admin();
  select * into e from public.delivery_events where id=p_event for update;
  if not found then raise exception 'delivery not found'; end if;
  if e.status in('sending','sent') then raise exception 'a message already sending or accepted cannot be recalled'; end if;
  update public.delivery_events set status='cancelled',terminal=true,next_retry_at=null,reason='Further attempts stopped by administrator.',updated_at=now() where id=e.id;
  perform public._hyn_audit('delivery.stop',e.owner,e.node_id,jsonb_build_object('event',e.id));
end $$;

create or replace function public.hyn_due_user_digests(p_trigger_node uuid default null)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
    select p.id owner,((now() at time zone (s->>'timezone'))::date)::text local_date
    from public.profiles p cross join lateral (select public._hyn_digest_setting(p.id) s) settings
    left join public.delivery_events e on e.source_key='user-digest:'||p.id::text||':'||((now() at time zone (s->>'timezone'))::date)::text
    where p.status='active' and p.email is not null and (s->>'configured')::boolean and (s->>'enabled')::boolean
      and (now() at time zone (s->>'timezone'))::time >= (s->>'send_at')::time
      and (e.id is null or (not e.terminal and e.status<>'sending' and (e.next_retry_at is null or e.next_retry_at<=now())))
      and exists(select 1 from public._hyn_digest_nodes(p.id) n where p_trigger_node is null or n.id=p_trigger_node)
    order by e.updated_at nulls first,p.id limit 25
  ) x;
$$;

create or replace function public.hyn_user_digest_content(p_owner uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('name',coalesce(nullif(p.full_name,''),p.email,'Portal user'),'recipient',p.email,
    'nodes',coalesce((select jsonb_agg(to_jsonb(x) order by x.name,x.id) from (
      select n.id,n.name,n.hostname,n.status,n.telemetry_mode,coalesce(n.last_heartbeat_at,n.last_seen_at) last_heartbeat_at,
        m.sample_count,m.cpu_average,m.cpu_peak,m.memory_average,m.temperature_peak,m.download_average,m.upload_average,m.latency_average,m.uptime
      from public._hyn_digest_nodes(p_owner) n cross join lateral (
        select count(*) sample_count,avg(cpu_pct) cpu_average,max(cpu_pct) cpu_peak,avg(mem_pct) memory_average,
          max(cpu_temp_c) temperature_peak,avg(net_rx_bps) download_average,avg(net_tx_bps) upload_average,
          avg(latency_ms) latency_average,(array_agg(uptime_s order by ts desc))[1] uptime
        from public.metrics where node_id=n.id and ts>=now()-interval '24 hours' and n.telemetry_mode<>'local'
      ) m
    ) x),'[]'::jsonb)) from public.profiles p where p.id=p_owner and p.status='active';
$$;

-- Legacy jobs keep their own five-attempt ceiling; a budget deferral is not a
-- provider attempt, so do not exhaust that ceiling while sending is paused.
create or replace function public.hyn_defer_web_delivery(p_job uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.web_notification_jobs set status='queued',attempts=greatest(0,attempts-1),error=left(p_reason,1000),updated_at=now()
  where id=p_job and status='sending';
end $$;
create or replace function public.hyn_claim_web_notification(p_job_id uuid default null)
returns json language plpgsql security definer set search_path=public as $$
declare v_job public.web_notification_jobs; v_node public.nodes; v_recipient text;
begin
  with candidate as (
    select j.id from public.web_notification_jobs j
    where (p_job_id is null or j.id=p_job_id) and (j.status='queued' or (j.status='failed' and j.attempts<5))
      and not exists(select 1 from public.delivery_events e where e.source_key='web-notification:'||j.id::text
        and ((e.terminal and e.status<>'sent') or e.status='sending' or e.next_retry_at>now()))
    order by j.created_at for update of j skip locked limit 1
  ) update public.web_notification_jobs j set status='sending',attempts=j.attempts+1,updated_at=now(),error=null
    from candidate where j.id=candidate.id returning j.* into v_job;
  if not found then return json_build_object('status','idle'); end if;
  select * into v_node from public.nodes where id=v_job.node_id;
  select recipient into v_recipient from public.email_preferences where node_id=v_job.node_id;
  return json_build_object('status','send','id',v_job.id,'node_id',v_job.node_id,'node_name',v_node.name,'hostname',v_node.hostname,
    'owner',v_node.owner,'recipient',v_recipient,'fingerprint',v_job.fingerprint,'category',v_job.category,'severity',v_job.severity,
    'subject',v_job.subject,'text_body',v_job.text_body,'html_body',v_job.html_body,'attempts',v_job.attempts);
end $$;

create or replace function public.hyn_admin_delivery_dashboard(p_owner uuid default null,p_kind text default 'all',p_status text default 'all',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; v_day timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
begin
  perform public._hyn_require_staff();
  if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid history page'; end if;
  select jsonb_build_object('as_of',now(),'day_start',v_day,'started_at',(select created_at from public.delivery_rules where scope='global' and kind='all'),
    'rules',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.delivery_rules r where r.scope='global' or r.owner=p_owner),
    'digest_settings',(select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.delivery_digest_settings s where s.scope='global' or s.owner=p_owner),
    'users',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.email,'Portal user'),'email',p.email,'status',p.status) order by coalesce(p.full_name,p.email)),'[]'::jsonb) from public.profiles p),
    'usage',(select coalesce(jsonb_agg(to_jsonb(u)),'[]'::jsonb) from (select e.kind,count(*) attempts,count(*) filter(where a.status='sent') sent,count(*) filter(where a.status='failed') failed,count(*) filter(where a.status in('sending','unknown')) unknown from public.delivery_attempts a join public.delivery_events e on e.id=a.event_id where a.started_at>=v_day and (p_owner is null or e.owner=p_owner) group by e.kind) u),
    'global_usage',(select coalesce(jsonb_agg(to_jsonb(u)),'[]'::jsonb) from (select e.kind,count(*) attempts,count(*) filter(where a.status='sent') sent,count(*) filter(where a.status='failed') failed,count(*) filter(where a.status in('sending','unknown')) unknown from public.delivery_attempts a join public.delivery_events e on e.id=a.event_id where a.started_at>=v_day group by e.kind) u),
    'total',(select count(*) from public.delivery_events e where (p_owner is null or e.owner=p_owner) and (p_kind='all' or e.kind=p_kind) and (p_status='all' or e.status=p_status)),
    'events',(select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]'::jsonb) from (
      select e.id,e.owner,coalesce(nullif(p.full_name,''),p.email,'Portal user') owner_name,p.email owner_email,e.node_label node_name,
        e.kind,e.subject,e.recipient,e.status,e.reason,e.attempt_count,e.attempt_limit,e.terminal,e.updated_at,e.next_retry_at,
        coalesce((select jsonb_agg(to_jsonb(a) order by a.started_at) from public.delivery_attempts a where a.event_id=e.id),'[]'::jsonb) attempts
      from public.delivery_events e join public.profiles p on p.id=e.owner
      where (p_owner is null or e.owner=p_owner) and (p_kind='all' or e.kind=p_kind) and (p_status='all' or e.status=p_status)
      order by e.updated_at desc,e.id offset p_offset limit 25) x),
    'legacy',(select coalesce(jsonb_agg(to_jsonb(x) order by x.ts desc),'[]'::jsonb) from (
      select l.id,l.ts,coalesce(nullif(p.full_name,''),p.email,'Portal user') owner_name,n.name node_name,l.kind,l.status,l.subject,l.error
      from public.notification_log l left join public.profiles p on p.id=l.owner left join public.nodes n on n.id=l.node_id
      where p_owner is null or l.owner=p_owner order by l.ts desc limit 50) x)
  ) into result;
  return result;
end $$;

revoke all on function public._hyn_digest_setting(uuid),public._hyn_digest_nodes(uuid) from public,anon,authenticated;
revoke all on function public.hyn_admin_set_delivery_rules(uuid,jsonb),public.hyn_admin_set_digest(uuid,boolean,text,text,boolean,boolean),public.hyn_admin_stop_delivery(uuid),public.hyn_admin_delivery_dashboard(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.hyn_admin_set_delivery_rules(uuid,jsonb),public.hyn_admin_set_digest(uuid,boolean,text,text,boolean,boolean),public.hyn_admin_stop_delivery(uuid),public.hyn_admin_delivery_dashboard(uuid,text,text,integer) to authenticated;
revoke all on function public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[]),public.hyn_complete_delivery(uuid,text,text,text),public.hyn_due_user_digests(uuid),public.hyn_user_digest_content(uuid),public.hyn_defer_web_delivery(uuid,text),public.hyn_claim_web_notification(uuid) from public,anon,authenticated;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant select on public.delivery_rules,public.delivery_digest_settings to service_role;
    grant execute on function public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[]),public.hyn_complete_delivery(uuid,text,text,text),public.hyn_due_user_digests(uuid),public.hyn_user_digest_content(uuid),public.hyn_defer_web_delivery(uuid,text),public.hyn_claim_web_notification(uuid) to service_role;
  end if;
end $$;
notify pgrst,'reload schema';
commit;
-- A physical relayer has one priority assignment and any number of view grants.
-- Keep the existing three-argument admin API and all portal UI unchanged.
begin;

-- Existing, previously exclusive assignments retain their priority and IDs.
alter table public.relayer_assignments
  add column if not exists assignment_role text not null default 'primary';
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.relayer_assignments'::regclass and conname='relayer_assignments_assignment_role_check') then
    alter table public.relayer_assignments add constraint relayer_assignments_assignment_role_check
      check (assignment_role in ('primary','view'));
  end if;
end $$;
create unique index if not exists relayer_assignments_owner_relayer_key
  on public.relayer_assignments(owner,relayer_id);
create unique index if not exists relayer_assignments_primary_relayer_key
  on public.relayer_assignments(relayer_id) where assignment_role='primary';
create unique index if not exists relayer_assignments_id_owner_role_key
  on public.relayer_assignments(id,owner,assignment_role);
alter table public.relayer_assignments drop constraint if exists relayer_assignments_relayer_id_key;

-- Only the priority relationship can back a Highway Node link. A composite FK
-- also enforces this for direct privileged writes and concurrent role changes.
-- Removing one assignment cannot revoke any other user's independent view grant.
alter table public.node_relayer_links
  add column if not exists assignment_role text not null default 'primary';
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.node_relayer_links'::regclass and conname='node_relayer_links_primary_role_check') then
    alter table public.node_relayer_links add constraint node_relayer_links_primary_role_check
      check (assignment_role='primary');
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.node_relayer_links'::regclass and conname='node_relayer_links_primary_assignment_fkey') then
    alter table public.node_relayer_links add constraint node_relayer_links_primary_assignment_fkey
      foreign key (assignment_id,owner,assignment_role)
      references public.relayer_assignments(id,owner,assignment_role)
      on update restrict on delete cascade;
  end if;
end $$;

create or replace function public.hyn_admin_assign_relayer(p_owner uuid,p_relayer_id integer,p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_role text;
begin
  perform public._hyn_require_admin();
  if p_owner is null or p_relayer_id is null or p_relayer_id<=0
    or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A user, positive relayer ID and name are required';
  end if;
  if not exists(select 1 from public.profiles where id=p_owner and status='active') then
    raise exception 'Select an active portal account';
  end if;
  -- Serialize first-assignment selection across different users of this relay.
  perform pg_advisory_xact_lock(hashtext('hyn.relayer.assignment'),p_relayer_id);
  select assignment_role into v_role from public.relayer_assignments
    where owner=p_owner and relayer_id=p_relayer_id;
  if v_role is null then
    v_role:=case when exists(select 1 from public.relayer_assignments
      where relayer_id=p_relayer_id and assignment_role='primary') then 'view' else 'primary' end;
  end if;
  insert into public.relayer_assignments(owner,relayer_id,relayer_name,assignment_role)
    values(p_owner,p_relayer_id,trim(p_relayer_name),v_role)
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name
    returning id,assignment_role into v_id,v_role;
  perform public._hyn_audit('relayer.assign',p_owner,null,
    jsonb_build_object('relayer_id',p_relayer_id,'relayer_name',trim(p_relayer_name),'assignment_role',v_role));
  return v_id;
end $$;

-- Priority changes are explicit, never a side effect of adding a viewer.
-- A linked priority assignment must be unlinked before transferring priority;
-- no existing server association is silently moved or removed.
create or replace function public.hyn_admin_set_relayer_priority(p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_relayer_id integer; v_assignment public.relayer_assignments; v_previous uuid;
begin
  perform public._hyn_require_admin();
  select relayer_id into v_relayer_id from public.relayer_assignments where id=p_assignment_id;
  if not found then raise exception 'Assignment no longer exists'; end if;
  perform pg_advisory_xact_lock(hashtext('hyn.relayer.assignment'),v_relayer_id);
  select * into v_assignment from public.relayer_assignments where id=p_assignment_id for update;
  if not found then raise exception 'Assignment no longer exists'; end if;
  if not exists(select 1 from public.profiles where id=v_assignment.owner and status='active') then
    raise exception 'Select an active portal account';
  end if;
  if v_assignment.assignment_role='primary' then return; end if;
  select id into v_previous from public.relayer_assignments
    where relayer_id=v_relayer_id and assignment_role='primary' for update;
  if exists(select 1 from public.node_relayer_links where assignment_id=v_previous) then
    raise exception 'Unlink this relayer from its Highway Node server before changing priority' using errcode='PT409';
  end if;
  update public.relayer_assignments set assignment_role='view' where id=v_previous;
  update public.relayer_assignments set assignment_role='primary' where id=p_assignment_id;
  perform public._hyn_audit('relayer.priority',v_assignment.owner,null,
    jsonb_build_object('relayer_id',v_relayer_id,'assignment_id',p_assignment_id,'previous_assignment_id',v_previous));
end $$;

create or replace function public.hyn_request_relayer(p_relayer_id integer,p_relayer_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.hyn_can_monitor() then raise exception 'monitor or super administrator role required'; end if;
  if auth.uid() is null or not public.hyn_is_active() then raise exception 'An active account is required'; end if;
  if p_relayer_id is null or p_relayer_id<=0 or p_relayer_name is null or length(trim(p_relayer_name)) not between 1 and 160 then
    raise exception 'A positive relayer ID and name are required';
  end if;
  perform 1 from public.profiles where id=auth.uid() for update;
  -- Another user's priority or view assignment does not prevent a request.
  -- A request itself still grants no access; an admin must approve it.
  if exists(select 1 from public.relayer_assignments where owner=auth.uid() and relayer_id=p_relayer_id) then
    raise exception 'This relayer is already assigned to your account';
  end if;
  select id into v_id from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id and status='pending';
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.relayer_requests where owner=auth.uid() and status='pending')>=10 then
    raise exception 'You already have 10 pending requests. Cancel one or wait for a review';
  end if;
  if not exists(select 1 from public.relayer_requests where owner=auth.uid() and relayer_id=p_relayer_id)
    and (select count(*) from public.relayer_requests where owner=auth.uid())>=50 then
    raise exception 'Request limit reached. Contact an administrator';
  end if;
  insert into public.relayer_requests(owner,relayer_id,relayer_name)
    values(auth.uid(),p_relayer_id,trim(p_relayer_name))
    on conflict(owner,relayer_id) do update set relayer_name=excluded.relayer_name,status='pending',created_at=now(),reviewed_at=null,reviewed_by=null
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.hyn_admin_set_node_relayer(p_node_id uuid,p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_owner uuid; v_previous uuid; v_relayer_id integer; v_role text;
begin
  v_actor:=public._hyn_require_admin();
  select owner into v_owner from public.nodes where id=p_node_id and not revoked and not is_demo for update;
  if not found then raise exception 'Choose an available, non-demo server'; end if;
  select assignment_id into v_previous from public.node_relayer_links where node_id=p_node_id;
  if v_previous is not distinct from p_assignment_id then return; end if;
  if p_assignment_id is null then
    delete from public.node_relayer_links where node_id=p_node_id;
  else
    if not exists(select 1 from public.profiles where id=v_owner and status='active') then
      raise exception 'Restore this account before linking a relayer';
    end if;
    select relayer_id,assignment_role into v_relayer_id,v_role from public.relayer_assignments
      where id=p_assignment_id and owner=v_owner for update;
    if not found then raise exception 'Choose a relayer assigned to this server''s account'; end if;
    if v_role<>'primary' then
      raise exception 'This is view-only relay access. Only the priority assignment can link to a Highway Node server' using errcode='PT409';
    end if;
    if exists(select 1 from public.node_relayer_links where assignment_id=p_assignment_id and node_id<>p_node_id) then
      raise exception 'This relayer is linked to another server. Unlink it there first' using errcode='PT409';
    end if;
    insert into public.node_relayer_links(node_id,owner,assignment_id,linked_by)
      values(p_node_id,v_owner,p_assignment_id,v_actor)
      on conflict(node_id) do update set assignment_id=excluded.assignment_id,owner=excluded.owner,linked_by=excluded.linked_by,linked_at=now();
  end if;
  perform public._hyn_audit(case when p_assignment_id is null then 'node.relayer.unlink' else 'node.relayer.link' end,
    v_owner,p_node_id,jsonb_build_object('assignment_id',p_assignment_id,'previous_assignment_id',v_previous,'relayer_id',v_relayer_id));
end $$;

-- Preserve existing read visibility and admin-only writes. No dashboard or
-- server access is granted merely by adding a relayer view assignment.
revoke all on function public.hyn_admin_assign_relayer(uuid,integer,text) from public,anon;
revoke all on function public.hyn_admin_set_relayer_priority(uuid) from public,anon;
revoke all on function public.hyn_request_relayer(integer,text) from public,anon;
revoke all on function public.hyn_admin_set_node_relayer(uuid,uuid) from public,anon;
grant execute on function public.hyn_admin_assign_relayer(uuid,integer,text) to authenticated;
grant execute on function public.hyn_admin_set_relayer_priority(uuid) to authenticated;
grant execute on function public.hyn_request_relayer(integer,text) to authenticated;
grant execute on function public.hyn_admin_set_node_relayer(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
-- Primary monitoring history is a rolling 48 hours; local archives remain independent.
-- Bounded cleanup also covers idle/deleted-from-fleet sources, with portal cron as fallback.
begin;

alter table public.nodes add column if not exists last_metric_at timestamptz;
alter table public.nodes add column if not exists last_telemetry_prune_at timestamptz;
grant select (last_metric_at) on public.nodes to authenticated;
-- Backfill once, preserving the newest observed capture time across outbox replay.
update public.nodes n set last_metric_at = latest.ts
from (select node_id, max(ts) as ts from public.metrics where isfinite(ts) and ts<=now()+interval '5 minutes' group by node_id) latest
where n.id = latest.node_id and n.last_metric_at is null;
update public.nodes set last_metric_at=null where not isfinite(last_metric_at) or last_metric_at>now()+interval '5 minutes';

-- New event fingerprints deduplicate repeated alert events across distinct
-- snapshot envelopes without rewriting legacy alert rows during migration.
alter table public.alert_events add column if not exists event_fingerprint text;
create unique index if not exists alert_events_fingerprint_idx on public.alert_events(node_id,event_fingerprint)
  where event_fingerprint is not null;

create index if not exists metrics_retention_idx on public.metrics(ts, id);
create index if not exists speedtests_retention_idx on public.speedtests(ts, id);
create index if not exists alert_events_retention_idx on public.alert_events(ts, id);

-- Pick only known scalar fields. Never store arbitrary nested objects, commands,
-- environment variables, credentials, raw service journal messages or filesystem logs.
create or replace function public._hyn_monitoring_fields(p_value jsonb, p_keys text[])
returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_object_agg(key, case when jsonb_typeof(value) = 'string'
    then to_jsonb(left(value #>> '{}', 256)) else value end), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(p_value) = 'object' then p_value else '{}'::jsonb end)
  where key = any(p_keys) and jsonb_typeof(value) in ('number','string','boolean','null')
    and (jsonb_typeof(value) <> 'number' or length(value::text) <= 32)
$$;
revoke all on function public._hyn_monitoring_fields(jsonb,text[]) from public, anon, authenticated;

create or replace function public._hyn_monitoring_payload(p_payload jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v jsonb; g record; items jsonb; item jsonb;
begin
  v := public._hyn_monitoring_fields(p_payload, array['ts','host','agent_version','os','kernel','uptime_s','latency_ms']);
  for g in select * from (values
    ('cpu', array['pct','user','sys','iowait','steal','cores','model','mhz','mhz_avg','mhz_min','mhz_max','governor','temp_c']),
    ('memory', array['total','used','pct','swap_used']),
    ('disk', array['pct']),
    ('network', array['iface','local_ip','public_ip','connection','gateway','dns','rx_bps','tx_bps','rx_total','tx_total','rx_err','tx_err','rx_drop','tx_drop','retrans_permille','conntrack_pct','link_mbps','duplex','mtu','state','driver','tcp_estab','tcp_timewait','listen_drops']),
    ('psi', array['cpu','memory','io']),
    ('processes', array['count','running','blocked']),
    ('agent_update', array['latest','available','checked_at']),
    ('speedtest', array['ts','down_bps','up_bps','latency_us','note']),
    ('power', array['input_w','input_src','cpu_w','dram_w','ac_online','battery_pct','battery_status','battery_w']),
    ('highway', array['present','health','version','units_active','units_failed','journal_err_1h','tracked','health_why','version_src','latest','update_available','bin_size','bin_mtime','units_total','journal_warn_1h','pid','cpu_tenths','rss','threads','fds','proc_uptime_s','mesh_iface','mesh_rx_bps','mesh_tx_bps','mesh_rx_total','mesh_tx_total','mesh_drops','qdisc','qdisc_drops','congestion','nft_tables']),
    ('platform', array['provider','provider_source','provider_confidence','virtualization','environment','metrics_scope','host_cpu_count','host_memory_bytes','cgroup_version','cpu_limit_cores','memory_limit_bytes','memory_current_bytes','cpu_throttled_usec','cpu_throttled_periods'])
  ) as groups(name, keys) loop
    if jsonb_typeof(p_payload->g.name) = 'object' then
      v := v || jsonb_build_object(g.name, public._hyn_monitoring_fields(p_payload->g.name, g.keys));
    end if;
  end loop;
  if jsonb_typeof(p_payload#>'{cpu,cores_mhz}')='array' then
    select coalesce(jsonb_agg(value),'[]'::jsonb) into items
      from (select value from jsonb_array_elements(p_payload#>'{cpu,cores_mhz}') with ordinality
        where ordinality<=128 and jsonb_typeof(value)='number' and length(value::text)<=32) a;
    v := jsonb_set(v,'{cpu,cores_mhz}',items);
  end if;
  if jsonb_typeof(p_payload#>'{power,rails}')='object' then
    select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into items
      from (select key,value from jsonb_each(p_payload#>'{power,rails}')
        where length(key)<=80 and jsonb_typeof(value) in ('number','null') and length(value::text)<=32
        order by key limit 16) a;
    v := jsonb_set(v,'{power,rails}',items);
  end if;
  if jsonb_typeof(p_payload#>'{processes,top}')='array' then
    select coalesce(jsonb_agg(public._hyn_monitoring_fields(value,array['pid','name','cpu_tenths','rss','threads'])),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload#>'{processes,top}') with ordinality
        where ordinality<=16 and jsonb_typeof(value)='object') a;
    v := jsonb_set(v,'{processes,top}',items);
  end if;

  if jsonb_typeof(p_payload->'load') = 'array' then
    select coalesce(jsonb_agg(value), '[]'::jsonb) into items
    from (select value from jsonb_array_elements(p_payload->'load') with ordinality
      where ordinality <= 3 and jsonb_typeof(value) = 'number' and length(value::text) <= 32) a;
    v := v || jsonb_build_object('load', items);
  end if;
  -- Numeric maps have bounded cardinality and labels; values cannot carry log text.
  for g in select * from (values ('sensors',32), ('latency_us',16)) as maps(name, cap) loop
    if jsonb_typeof(p_payload->g.name) = 'object' then
      select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into items
      from (select key,value from jsonb_each(p_payload->g.name)
        where length(key) <= 80 and jsonb_typeof(value) in ('number','null')
          and length(value::text) <= 32 order by key limit g.cap) a;
      v := v || jsonb_build_object(g.name,items);
    end if;
  end loop;
  if jsonb_typeof(p_payload#>'{disk,mounts}') = 'array' then
    select coalesce(jsonb_agg(public._hyn_monitoring_fields(value, array['mount','pct','used','size','avail','fstype'])),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload#>'{disk,mounts}') with ordinality
        where ordinality <= 16 and jsonb_typeof(value)='object') a;
    v := jsonb_set(v,'{disk,mounts}',items);
  end if;
  if jsonb_typeof(p_payload#>'{highway,units}') = 'array' then
    select coalesce(jsonb_agg(public._hyn_monitoring_fields(value, array['name','state','sub','restarts','memory','active_s'])),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload#>'{highway,units}') with ordinality
        where ordinality <= 32 and jsonb_typeof(value)='object') a;
    v := jsonb_set(v,'{highway,units}',items);
  end if;
  if jsonb_typeof(p_payload->'alerts') = 'array' then
    select coalesce(jsonb_agg(public._hyn_monitoring_fields(value,array['ts','rule','severity','message','resolved'])),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload->'alerts') with ordinality
        where ordinality <= 32 and jsonb_typeof(value)='object') a;
    v := v || jsonb_build_object('alerts',items);
  end if;
  items := '[]'::jsonb;
  if jsonb_typeof(p_payload->'monitoring_logs') = 'array' then
    for item in select value from jsonb_array_elements(p_payload->'monitoring_logs') with ordinality
      where ordinality <= 12 and jsonb_typeof(value)='object'
    loop
      if item->>'code' = any(array['sample_collected','heartbeat_ok','heartbeat_failed','cloud_upload_ok','cloud_upload_failed','cloud_upload_paused','cloud_upload_suspended','agent_restarts','service_failed','service_warning','service_error','alerts_active'])
        and item->>'level' = any(array['info','warn','crit'])
        and coalesce(item->>'count','1') ~ '^[0-9]{1,9}$' then
        items := items || jsonb_build_array(public._hyn_monitoring_fields(item,array['ts','level','code','count']));
      end if;
    end loop;
    v := v || jsonb_build_object('monitoring_logs',items);
  end if;
  return v;
end $$;
revoke all on function public._hyn_monitoring_payload(jsonb) from public, anon, authenticated;

create or replace function public.hyn_prune_telemetry(p_batch integer default 5000)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cutoff timestamptz := now() - interval '48 hours';
  v_batch integer := greatest(1, least(coalesce(p_batch,5000),5000));
  v_metrics integer := 0; v_speedtests integer := 0; v_alerts integer := 0;
begin
  if not pg_try_advisory_xact_lock(1876901121,48) then
    return jsonb_build_object('status','busy','cutoff',v_cutoff);
  end if;
  with expired as (
    select id from public.metrics where ts < v_cutoff or ts > now()+interval '5 minutes'
    order by ts,id for update skip locked limit v_batch
  ) delete from public.metrics m using expired e where m.id=e.id;
  get diagnostics v_metrics = row_count;
  with expired as (
    select id from public.speedtests where ts < v_cutoff or ts > now()+interval '5 minutes'
    order by ts,id for update skip locked limit v_batch
  ) delete from public.speedtests m using expired e where m.id=e.id;
  get diagnostics v_speedtests = row_count;
  with expired as (
    select id from public.alert_events where ts < v_cutoff or ts > now()+interval '5 minutes'
    order by ts,id for update skip locked limit v_batch
  ) delete from public.alert_events m using expired e where m.id=e.id;
  get diagnostics v_alerts = row_count;
  return jsonb_build_object('status','ok','cutoff',v_cutoff,'retention_hours',48,
    'metrics_deleted',v_metrics,'speedtests_deleted',v_speedtests,'alerts_deleted',v_alerts,
    'has_more',exists(select 1 from public.metrics where ts<v_cutoff or ts>now()+interval '5 minutes')
      or exists(select 1 from public.speedtests where ts<v_cutoff or ts>now()+interval '5 minutes')
      or exists(select 1 from public.alert_events where ts<v_cutoff or ts>now()+interval '5 minutes'));
end $$;
revoke all on function public.hyn_prune_telemetry(integer) from public, anon, authenticated;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant execute on function public.hyn_prune_telemetry(integer) to service_role;
    revoke all on function public._hyn_monitoring_fields(jsonb,text[]), public._hyn_monitoring_payload(jsonb) from service_role;
  end if;
end $$;

create or replace function public.hyn_ingest(
  p_node_token text,
  p_payload jsonb
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_ts timestamptz;
  v_alert jsonb;
  v_st jsonb;
  v_written integer := 0;
  v_inserted integer := 0;
  v_alerts jsonb;
  v_detail text;
  v_alert_written integer;
  v_event_ts timestamptz;
  v_cutoff timestamptz := now() - interval '48 hours';
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token)
     and revoked = false for update;

  if not found then
    raise exception 'invalid node token';
  end if;

  if not exists(select 1 from public.profiles where id=v_node.owner and status='active') then
    raise exception 'account suspended';
  end if;

  -- A pause with an elapsed deadline resolves itself before the status check, so
  -- a temporary pause really is temporary even if nobody comes back to clear it.
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  -- Distinct messages: the agent backs off quietly on a pause and says so
  -- loudly on a suspension, because one is expected and the other needs a human.
  if v_node.status = 'paused' then
    raise exception 'node paused%', coalesce(' until ' || v_node.paused_until::text, '');
  end if;
  if v_node.status = 'suspended' then
    raise exception 'node suspended: %', coalesce(v_node.status_reason, 'contact your administrator');
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'monitoring payload must be an object';
  end if;
  if octet_length(p_payload::text) > 65536 then raise exception 'monitoring payload exceeds 64 KiB'; end if;
  v_ts := coalesce((p_payload->>'ts')::timestamptz, now());
  if not isfinite(v_ts) or v_ts > now() + interval '5 minutes' then
    raise exception 'monitoring timestamp is in the future or invalid';
  end if;
  if v_ts < v_cutoff then
    return json_build_object('status','ok','node_id',v_node.id,'discarded','expired','alerts_written',0);
  end if;
  p_payload := public._hyn_monitoring_payload(p_payload);
  -- Cached children retain their own collection time, never the envelope time.
  v_st := p_payload->'speedtest';
  if v_st is not null and coalesce((v_st->>'ts')::bigint,0)>0
     and to_timestamp((v_st->>'ts')::bigint) not between v_cutoff and now()+interval '5 minutes' then
    p_payload := p_payload-'speedtest';
  end if;
  if p_payload ? 'alerts' then
    select jsonb_set(p_payload,'{alerts}',coalesce(jsonb_agg(a),'[]'::jsonb)) into p_payload
    from jsonb_array_elements(p_payload->'alerts') a
    where coalesce((a->>'ts')::timestamptz,v_ts) between v_cutoff and now()+interval '5 minutes';
  end if;
  if p_payload ? 'monitoring_logs' then
    select jsonb_set(p_payload,'{monitoring_logs}',coalesce(jsonb_agg(a),'[]'::jsonb)) into p_payload
    from jsonb_array_elements(p_payload->'monitoring_logs') a
    where coalesce((a->>'ts')::timestamptz,v_ts) between v_cutoff and now()+interval '5 minutes';
  end if;
  -- Alert event rows remain complete within their own bound when large hardware
  -- inventories require a smaller latest-snapshot payload.
  v_alerts := coalesce(p_payload->'alerts','[]'::jsonb);
  if octet_length(p_payload::text)>16384 then
    p_payload := p_payload || '{"monitoring_truncated":true}'::jsonb;
    -- Discard supplemental inventories deterministically; headline readings and
    -- structured status logs continue uploading on large/core-dense servers.
    foreach v_detail in array array['highway.units','disk.mounts','processes.top','cpu.cores_mhz','power.rails','sensors','latency_us','alerts'] loop
      exit when octet_length(p_payload::text)<=16384;
      p_payload := p_payload #- string_to_array(v_detail,'.');
    end loop;
  end if;
  if octet_length(p_payload::text)>16384 then raise exception 'stored monitoring payload exceeds 16 KiB'; end if;

  insert into public.metrics (
    node_id, ts, cpu_pct, cpu_temp_c, cpu_mhz, cpu_model, cpu_steal, cpu_iowait, cpu_cores,
    load1, mem_pct, mem_total, mem_used, swap_used, disk_pct, uptime_s,
    net_iface, net_rx_bps, net_tx_bps, net_retrans_pm, latency_ms,
    net_link_mbps, psi_cpu, psi_mem, psi_io, tcp_estab, conntrack_pct, proc_count,
    sensors, payload
  ) values (
    v_node.id, v_ts,
    (p_payload#>>'{cpu,pct}')::numeric,
    (p_payload#>>'{cpu,temp_c}')::numeric,
    (p_payload#>>'{cpu,mhz}')::numeric,
    nullif(p_payload#>>'{cpu,model}', ''),
    (p_payload#>>'{cpu,steal}')::numeric,
    (p_payload#>>'{cpu,iowait}')::numeric,
    (p_payload#>>'{cpu,cores}')::integer,
    (p_payload#>>'{load,0}')::numeric,
    (p_payload#>>'{memory,pct}')::numeric,
    (p_payload#>>'{memory,total}')::bigint,
    (p_payload#>>'{memory,used}')::bigint,
    (p_payload#>>'{memory,swap_used}')::bigint,
    (p_payload#>>'{disk,pct}')::numeric,
    (p_payload->>'uptime_s')::bigint,
    (p_payload#>>'{network,iface}'),
    (p_payload#>>'{network,rx_bps}')::bigint,
    (p_payload#>>'{network,tx_bps}')::bigint,
    (p_payload#>>'{network,retrans_permille}')::numeric,
    (p_payload->>'latency_ms')::numeric,
    (p_payload#>>'{network,link_mbps}')::numeric,
    (p_payload#>>'{psi,cpu}')::numeric,
    (p_payload#>>'{psi,memory}')::numeric,
    (p_payload#>>'{psi,io}')::numeric,
    (p_payload#>>'{network,tcp_estab}')::integer,
    (p_payload#>>'{network,conntrack_pct}')::numeric,
    (p_payload#>>'{processes,count}')::integer,
    p_payload->'sensors',
    p_payload
  )
  on conflict (node_id, ts) do nothing;
  get diagnostics v_inserted = row_count;
  -- Replay of an acknowledged snapshot cannot duplicate alert rows or mutate
  -- last-observed host/version information.
  if v_inserted = 0 then
    return json_build_object('status','ok','node_id',v_node.id,'duplicate',true,'alerts_written',0);
  end if;

  -- A speed test only happens a few times a day, so the agent sends its last
  -- known result on every push. Dedupe on (node, ts) rather than re-inserting.
  v_st := p_payload->'speedtest';
  if v_st is not null and coalesce((v_st->>'ts')::bigint, 0) > 0
     and to_timestamp((v_st->>'ts')::bigint) between v_cutoff and now() + interval '5 minutes' then
    insert into public.speedtests (node_id, ts, down_bps, up_bps, latency_ms, note)
    values (
      v_node.id,
      to_timestamp((v_st->>'ts')::bigint),
      (v_st->>'down_bps')::bigint,
      (v_st->>'up_bps')::bigint,
      round(coalesce((v_st->>'latency_us')::numeric, 0) / 1000.0, 2),
      nullif(v_st->>'note', '')
    )
    on conflict (node_id, ts) do nothing;
  end if;

  for v_alert in select * from jsonb_array_elements(v_alerts)
  loop
    v_event_ts := coalesce((v_alert->>'ts')::timestamptz, v_ts);
    if not isfinite(v_event_ts) or v_event_ts < v_cutoff or v_event_ts > now() + interval '5 minutes' then continue; end if;
    insert into public.alert_events (node_id, ts, rule, severity, message, resolved, event_fingerprint)
    values (
      v_node.id,
      v_event_ts,
      v_alert->>'rule',
      case when v_alert->>'severity' in ('info','warn','crit') then v_alert->>'severity' else 'info' end,
      left(coalesce(v_alert->>'message', 'alert'), 500),
      coalesce((v_alert->>'resolved')::boolean, false),
      public._hyn_sha256(jsonb_build_array(extract(epoch from v_event_ts),v_alert->>'rule',
        case when v_alert->>'severity' in ('info','warn','crit') then v_alert->>'severity' else 'info' end,
        left(coalesce(v_alert->>'message','alert'),500),coalesce((v_alert->>'resolved')::boolean,false))::text)
    ) on conflict(node_id,event_fingerprint) where event_fingerprint is not null do nothing;
    get diagnostics v_alert_written = row_count;
    v_written := v_written + v_alert_written;
  end loop;

  update public.nodes
     set last_seen_at = greatest(last_seen_at, least(v_ts,now())),
         last_metric_at = v_ts,
         agent_version = coalesce(nullif(p_payload->>'agent_version', ''), agent_version),
         hostname = coalesce(nullif(p_payload->>'host', ''), hostname)
   where id = v_node.id and (last_metric_at is null or last_metric_at < v_ts);

  -- Avoid unbounded per-reading DELETEs. Global scheduled cleanup covers every
  -- node, including servers that are offline and no longer send readings.
  if v_node.last_telemetry_prune_at is null or v_node.last_telemetry_prune_at<now()-interval '5 minutes' then
    perform public.hyn_prune_telemetry(100);
    update public.nodes set last_telemetry_prune_at=now() where id=v_node.id;
  end if;

  return json_build_object('status', 'ok', 'node_id', v_node.id, 'alerts_written', v_written);
end;
$$;

revoke all on function public.hyn_ingest(text,jsonb) from public;
grant execute on function public.hyn_ingest(text,jsonb) to anon, authenticated;

-- Hide expired monitoring immediately even while a bounded cleanup drains backlog.
-- The existing owner/shared-server authorization remains the read boundary.
drop policy if exists metrics_select_own on public.metrics;
create policy metrics_select_own on public.metrics for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));
drop policy if exists speedtests_select_own on public.speedtests;
create policy speedtests_select_own on public.speedtests for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));
drop policy if exists alert_events_select_own on public.alert_events;
create policy alert_events_select_own on public.alert_events for select to authenticated
  using(ts between now()-interval '48 hours' and now()+interval '5 minutes' and public.hyn_can_view_node(node_id));


-- Cloud history is now the managed default. The policy marker makes this a
-- one-time upgrade; subsequent explicit local choices survive reapplication.
create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  e record;
  v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_enabled', 'report_enabled', 'keep_awake') then
        if v not in ('on', 'off') then return false; end if;
      when e.key in ('alert_interval_min', 'record_interval_min') then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'speedtest_per_day' then
        if v !~ '^[1-9][0-9]?$' then return false; end if;
        if v::integer > 24 then return false; end if;
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' then return false; end if;
        if v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' then return false; end if;
        if v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'cloud_storage' then
        if v not in ('cloud','local') then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'cloud_checkin_min' then
        if v !~ '^[1-9][0-9]{0,2}$' then return false; end if;
        if v::integer > 60 then return false; end if;
      when e.key = 'heartbeat_sec' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer < 5 or v::integer > 3600 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'dashboard_view' then
        if v not in ('dash', 'simple') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;

$$;
alter table public.nodes add column if not exists telemetry_policy_version integer not null default 0;
update public.nodes set
 config = config || jsonb_build_object('cloud_storage','cloud',
   'cloud_push_min','5','cloud_checkin_min','5','heartbeat_sec','300','record_interval_min','1'),
 telemetry_policy_version=2
where telemetry_policy_version=0 and not is_demo;
alter table public.nodes alter column telemetry_policy_version set default 2;
alter table public.nodes alter column config set default '{"auto_update":"install","cloud_storage":"cloud","cloud_push_min":"5","cloud_checkin_min":"5","heartbeat_sec":"300","record_interval_min":"1"}'::jsonb;

-- Fetch at most one scalar reading per five-minute bucket; the page fetches the
-- latest full snapshot separately. RLS is evaluated with the requesting user.
create or replace function public.hyn_metric_history(p_node uuid)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(h) || '{"payload":null,"sensors":null}'::jsonb order by h.ts),'[]'::jsonb)
  from (
    select distinct on (floor(extract(epoch from m.ts)/300))
      m.id,m.node_id,m.ts,m.cpu_pct,m.cpu_temp_c,m.cpu_mhz,m.cpu_model,m.cpu_steal,m.cpu_iowait,m.cpu_cores,
      m.load1,m.mem_pct,m.mem_total,m.mem_used,m.swap_used,m.disk_pct,m.uptime_s,
      m.net_iface,m.net_rx_bps,m.net_tx_bps,m.net_retrans_pm,m.latency_ms,
      m.net_link_mbps,m.psi_cpu,m.psi_mem,m.psi_io,m.tcp_estab,m.conntrack_pct,m.proc_count
    from public.metrics m where m.node_id=p_node and m.ts>=now()-interval '48 hours' and m.ts<=now()+interval '5 minutes'
    order by floor(extract(epoch from m.ts)/300) desc,m.ts desc limit 600
  ) h
$$;
revoke all on function public.hyn_metric_history(uuid) from public, anon;
grant execute on function public.hyn_metric_history(uuid) to authenticated;


-- Admin fleet activity is aggregated in the database to avoid truncating an
-- arbitrary first 5,000 samples as installations grow. Ordinary users get no rows.
create or replace function public.hyn_fleet_metric_history()
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(h) order by h.ts),'[]'::jsonb)
  from (
    select to_timestamp(floor(extract(epoch from m.ts)/1800)*1800) as ts,
      avg(m.cpu_pct) as cpu_pct,avg(m.net_rx_bps) as net_rx_bps,avg(m.net_tx_bps) as net_tx_bps
    from public.metrics m join public.nodes n on n.id=m.node_id
    where public.hyn_is_admin() and not n.is_demo
      and m.ts>=now()-interval '24 hours' and m.ts<=now()
    group by floor(extract(epoch from m.ts)/1800)
    order by floor(extract(epoch from m.ts)/1800) desc limit 49
  ) h
$$;
revoke all on function public.hyn_fleet_metric_history() from public,anon;
grant execute on function public.hyn_fleet_metric_history() to authenticated;

-- Scheduling is installed only when pg_cron is already enabled. This migration
-- never changes shared_preload_libraries or requires a database restart.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron')
     and to_regprocedure('cron.schedule(text,text,text)') is not null then
    perform cron.schedule('hyn-telemetry-retention','*/5 * * * *',
      'select public.hyn_prune_telemetry(5000)');
  else
    raise notice 'pg_cron is unavailable: configure the portal telemetry retention cron every five minutes';
  end if;
end $$;
notify pgrst,'reload schema';
commit;
