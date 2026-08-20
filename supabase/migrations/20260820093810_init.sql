-- hyn-view <-> web portal integration schema
--
-- Apply this in the Supabase SQL editor (or `supabase db push`) before pairing
-- any node. Everything below is idempotent, so re-running it is safe.
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
--   * Tokens (device codes and node tokens) are stored as SHA-256 hashes, never
--     plaintext. A database dump therefore does not let anyone impersonate a
--     node. The plaintext token is returned exactly once, at the moment it is
--     minted, and never again.

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

-- Short-lived pairing codes. `user_code` is what a human retypes, so it uses a
-- reduced alphabet; `device_code` is the server's secret and is hashed.
create table if not exists public.device_codes (
  id               uuid primary key default gen_random_uuid(),
  user_code        text not null unique,
  device_code_hash text not null unique,
  hostname         text,
  os               text,
  agent_version    text,
  approved_by      uuid references auth.users (id) on delete cascade,
  node_id          uuid references public.nodes (id) on delete set null,
  node_token_hash  text,
  token_claimed    boolean not null default false,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null
);

create index if not exists device_codes_expiry_idx on public.device_codes (expires_at);

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
  out text := '';
  i integer;
begin
  for i in 1..8 loop
    out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    if i = 4 then
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
  -- Opportunistic cleanup. ponytail: piggybacking on this call instead of a
  -- pg_cron job keeps the deploy to one SQL file; if pairing volume ever gets
  -- high enough that this scan matters, move it to a scheduled job.
  delete from public.device_codes where expires_at < now() - interval '1 hour';

  v_device_code := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + interval '15 minutes';

  -- Retry on the astronomically unlikely user_code collision rather than
  -- failing the operator's pairing attempt.
  loop
    v_try := v_try + 1;
    v_user_code := public._hyn_user_code();
    begin
      insert into public.device_codes (
        user_code, device_code_hash, hostname, os, agent_version, expires_at
      ) values (
        v_user_code, public._hyn_sha256(v_device_code),
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

  select * into v from public.device_codes
   where user_code = upper(trim(p_user_code));

  if not found then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at < now() then
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

  select * into v from public.device_codes
   where user_code = upper(trim(p_user_code))
   for update;

  if not found then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at < now() then
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
   where device_code_hash = public._hyn_sha256(p_device_code)
   for update;

  if not found then
    return json_build_object('status', 'not_found');
  end if;
  if v.node_id is null then
    if v.expires_at < now() then
      return json_build_object('status', 'expired');
    end if;
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
      jsonb_build_object('demo', true)
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
--   * the dashboard becomes the source of truth for configuration, so the agent
--     on the box holds nothing but bootstrap credentials and pulls the rest;
--   * a client's email, channels and notification history live here rather than
--     in a text file on a server nobody logs into;
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
-- notification channels
-- ---------------------------------------------------------------------------
-- Configured in the browser and pulled by the agent, which is the point of the
-- exercise: nobody should have to ssh in to change where alerts go.
--
-- TRADEOFF, stated plainly: provider credentials live in this table so the
-- agent can fetch them. That means a database compromise exposes them, where
-- previously they only sat in a 0600 file on one box. The mitigations are that
-- `secret` is not selectable by any browser session (column grants below, so it
-- is write-only from the dashboard) and is returned only to a caller presenting
-- that node's token. If you would rather keep keys on the box, leave these rows
-- unset and configure notify_* in /etc/hyn-view/secrets as before -- the agent
-- treats a local secret as an override.
create table if not exists public.notification_channels (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null references auth.users (id) on delete cascade,
  -- null means "every node this client owns"
  node_id    uuid references public.nodes (id) on delete cascade,
  kind       text not null check (kind in ('resend', 'brevo', 'smtp', 'ntfy', 'telegram', 'webhook')),
  target     text not null,
  secret     text,
  extra      jsonb not null default '{}'::jsonb,
  enabled    boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists notification_channels_owner_idx on public.notification_channels (owner);

alter table public.notification_channels enable row level security;

drop policy if exists channels_select_own on public.notification_channels;
create policy channels_select_own on public.notification_channels
  for select using (owner = auth.uid() or public.hyn_is_admin());

drop policy if exists channels_insert_own on public.notification_channels;
create policy channels_insert_own on public.notification_channels
  for insert with check (owner = auth.uid() and public.hyn_is_active());

drop policy if exists channels_update_own on public.notification_channels;
create policy channels_update_own on public.notification_channels
  for update using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists channels_delete_own on public.notification_channels;
create policy channels_delete_own on public.notification_channels
  for delete using (owner = auth.uid());

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
  v_channels json;
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

  select coalesce(json_agg(json_build_object(
           'kind', c.kind, 'target', c.target, 'secret', c.secret, 'extra', c.extra
         )), '[]'::json)
    into v_channels
    from public.notification_channels c
   where c.owner = v_node.owner
     and c.enabled = true
     and (c.node_id is null or c.node_id = v_node.id);

  update public.nodes set last_config_pull_at = now() where id = v_node.id;

  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_name', v_node.name,
    'node_status', v_node.status,
    'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason,
    'config', v_node.config,
    'channels', v_channels
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
                             and (last_seen_at is null or last_seen_at < now() - interval '15 minutes')),
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
             n.created_at, n.last_seen_at, n.last_config_pull_at,
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
grant execute on function public.hyn_fetch_config(text) to anon, authenticated;
grant execute on function public.hyn_report_notification(text, jsonb) to anon, authenticated;

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
revoke all on function public.hyn_admin_set_node_status(uuid, text, integer, text) from public;
revoke all on function public.hyn_admin_set_node_revoked(uuid, boolean, text) from public;
revoke all on function public.hyn_admin_set_user_status(uuid, text, text) from public;
revoke all on function public.hyn_admin_set_role(uuid, text) from public;

grant execute on function public.hyn_admin_overview() to authenticated;
grant execute on function public.hyn_admin_nodes() to authenticated;
grant execute on function public.hyn_admin_clients() to authenticated;
grant execute on function public.hyn_admin_notifications(integer) to authenticated;
grant execute on function public.hyn_admin_audit(integer) to authenticated;
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

-- Table privileges for signed-in users are granted explicitly rather than
-- inherited from the project's default privileges, so this schema works on a
-- fresh or a hardened project without a surprise "permission denied for table
-- nodes" on the first dashboard load. RLS above is what limits WHICH rows.
grant select on public.nodes        to authenticated;
grant select on public.metrics      to authenticated;
grant select on public.speedtests   to authenticated;
grant select on public.alert_events to authenticated;

-- Renaming a node and revoking one are browser actions; inserting telemetry is
-- not, which is why there is no insert grant here for any of the data tables.
grant update (name, revoked) on public.nodes to authenticated;
grant delete on public.nodes to authenticated;

-- The client's own settings for a node are edited in the dashboard.
grant update (config) on public.nodes to authenticated;

grant select on public.profiles          to authenticated;
grant select on public.notification_log  to authenticated;
grant select on public.admin_audit       to authenticated;

-- A client may edit their display name only. role and status are deliberately
-- absent: changing those goes through the admin RPCs so it lands in the audit
-- trail, and a column grant is a harder guarantee than a policy alone.
grant update (full_name) on public.profiles to authenticated;

-- Channel secrets are WRITE-ONLY from the browser. The dashboard can set an API
-- key and can show that one exists, but cannot read it back; only a caller
-- presenting the node token gets the value, via hyn_fetch_config. Listing the
-- columns individually is what enforces this -- `grant select` on the table
-- would include `secret`.
grant select (id, owner, node_id, kind, target, extra, enabled, created_at)
  on public.notification_channels to authenticated;
grant insert on public.notification_channels to authenticated;
grant update (node_id, kind, target, secret, extra, enabled)
  on public.notification_channels to authenticated;
grant delete on public.notification_channels to authenticated;

-- Sequences behind the bigserial keys, needed for the inserts granted above.
grant usage, select on all sequences in schema public to authenticated;

revoke all on public.profiles              from anon;
revoke all on public.notification_channels from anon;
revoke all on public.notification_log      from anon;
revoke all on public.admin_audit           from anon;
