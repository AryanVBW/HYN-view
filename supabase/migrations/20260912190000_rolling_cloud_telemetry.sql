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
   'cloud_push_min',case when coalesce(config->>'cloud_push_min','10')='10' then '1' else config->>'cloud_push_min' end),
 telemetry_policy_version=1
where telemetry_policy_version=0 and not is_demo;
alter table public.nodes alter column telemetry_policy_version set default 1;
alter table public.nodes alter column config set default '{"auto_update":"install","cloud_storage":"cloud","cloud_push_min":"1"}'::jsonb;

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
