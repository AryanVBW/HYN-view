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
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
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
        'alert_repeat_hours', 'report_at', 'notify_max_per_day', 'cloud_push_min',
        'auto_update'
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
            then n.last_heartbeat_at is null or n.last_heartbeat_at <= now() - interval '3 minutes'
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
