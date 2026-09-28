-- One alert_events row per incident, closed when the agent stops reporting it.
--
-- hyn_ingest inserted a new alert_events row for every firing rule on every
-- upload and never resolved anything: in production 572 rows an hour for 21
-- real alerts, 0 of 26,686 rows resolved, so open-alert counts, fleet
-- attention lists and event logs were all inflated noise. Agents from 2.0.1
-- also report rules that just cleared and each incident's start time ("since").
--
-- Lifecycle, newest reading only (outbox replays of older readings change
-- nothing):
--   * firing rule with an open incident  -> keep it (ts/severity/message are
--     refreshed at most every 10 minutes or on a severity change)
--   * firing rule, same start seen before -> reopen it, unless a maintainer
--     dismissed it, in which case it stays closed
--   * firing rule otherwise               -> new incident
--   * rule reported as cleared            -> close it
--   * open incident missing from a complete list (<= 32 alerts) -> close it
begin;
-- ===========================================================================
-- alert incidents (supabase/migrations/20260928120000_alert_incidents.sql)
-- ===========================================================================
-- One alert_events row per incident instead of one per upload. started_at is
-- when the incident began, ts when it was last observed, resolved_at when it
-- ended, dismissed_at when a maintainer called it a false alarm (a dismissed
-- incident is not reopened while the agent keeps reporting it).
alter table public.alert_events add column if not exists started_at timestamptz;
alter table public.alert_events add column if not exists resolved_at timestamptz;
alter table public.alert_events add column if not exists dismissed_at timestamptz;

-- Collapse rows written one-per-upload into incidents: consecutive rows of the
-- same rule on the same node, less than 15 minutes apart, are one incident. The
-- newest row of each run is kept. Only the most recent run of a rule can still
-- be open, and only if it was seen in the last 15 minutes; the next reading
-- closes it if the rule is no longer firing. Demo data is left as seeded.
-- Idempotent: rows that already have a started_at are not touched.
with ordered as (
  select a.id, a.node_id, a.rule, a.ts,
         case when lag(a.ts) over w is null or a.ts - lag(a.ts) over w > interval '15 minutes'
              then 1 else 0 end as brk
    from public.alert_events a join public.nodes n on n.id = a.node_id
   where a.started_at is null and not n.is_demo
  window w as (partition by a.node_id, a.rule order by a.ts, a.id)
), grouped as (
  select id, node_id, rule, ts, sum(brk) over (partition by node_id, rule order by ts, id) as grp
    from ordered
), incidents as (
  select node_id, rule, grp, min(ts) as first_ts, max(ts) as last_ts,
         (array_agg(id order by ts desc, id desc))[1] as keep_id, array_agg(id) as ids
    from grouped group by node_id, rule, grp
), latest as (
  select distinct on (node_id, rule) node_id, rule, grp
    from incidents order by node_id, rule, last_ts desc
), removed as (
  delete from public.alert_events a using incidents i
   where a.id = any(i.ids) and a.id <> i.keep_id
)
update public.alert_events a
   set started_at = i.first_ts,
       event_fingerprint = null,
       resolved = a.resolved or not open_now.v,
       resolved_at = case when a.resolved or not open_now.v then coalesce(a.resolved_at, i.last_ts) end
  from incidents i
  cross join lateral (
    select exists(select 1 from latest l where l.node_id = i.node_id and l.rule is not distinct from i.rule
                    and l.grp = i.grp)
           and i.last_ts >= now() - interval '15 minutes' as v
  ) open_now
 where a.id = i.keep_id;

create unique index if not exists alert_events_incident_idx
  on public.alert_events (node_id, rule, started_at) where started_at is not null;
create index if not exists alert_events_open_idx
  on public.alert_events (node_id, rule) where not resolved;

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
  -- Alert incidents (see the alert-incident comment below).
  v_raw_alerts jsonb;
  v_complete boolean := false;
  v_newest boolean;
  v_since_map jsonb := '{}'::jsonb;
  v_seen text[] := '{}';
  v_rule text;
  v_sev text;
  v_msg text;
  v_since timestamptz;
  v_open public.alert_events;
  v_prev public.alert_events;
  v_gap interval;
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
  -- The agent sends every firing rule (and, from 2.0.1, the rules that just
  -- cleared). A list that fits the 32-element bound below is therefore complete,
  -- which is what allows an incident missing from it to be closed.
  v_raw_alerts := p_payload->'alerts';
  if jsonb_typeof(v_raw_alerts) = 'array' then
    v_complete := jsonb_array_length(v_raw_alerts) <= 32;
    select coalesce(jsonb_object_agg(a->>'rule', a->'since'), '{}'::jsonb) into v_since_map
      from jsonb_array_elements(v_raw_alerts) with ordinality e(a, n)
     where n <= 32 and jsonb_typeof(a) = 'object' and jsonb_typeof(a->'rule') = 'string'
       and jsonb_typeof(a->'since') = 'number' and (a->>'since') ~ '^[1-9][0-9]{0,11}$';
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

  -- Alert incidents. One alert_events row is one incident: started_at is when
  -- it began, ts when it was last observed (bumped at most every ten minutes, or
  -- when its severity changes), resolved/resolved_at when it ended. This used to
  -- insert a new row for every firing rule on every upload -- 572 rows an hour
  -- for 21 real alerts, none of them ever resolved.
  --
  -- Only the newest reading drives the lifecycle. An older reading replayed from
  -- the agent's outbox describes a state that has already been superseded, so it
  -- neither opens nor closes anything.
  v_newest := v_node.last_metric_at is null or v_ts > v_node.last_metric_at;
  v_gap := greatest(interval '15 minutes',
    make_interval(mins => 2 * coalesce(nullif(v_node.config->>'cloud_push_min', '')::integer, 5)));
  if v_newest then
    for v_alert in select * from jsonb_array_elements(v_alerts)
    loop
      if jsonb_typeof(v_alert) <> 'object' then continue; end if;
      v_event_ts := coalesce((v_alert->>'ts')::timestamptz, v_ts);
      if not isfinite(v_event_ts) or v_event_ts < v_cutoff or v_event_ts > now() + interval '5 minutes' then continue; end if;
      v_rule := coalesce(nullif(left(v_alert->>'rule', 120), ''), 'unnamed');
      v_sev := case when v_alert->>'severity' in ('info','warn','crit') then v_alert->>'severity' else 'info' end;
      v_msg := left(coalesce(v_alert->>'message', 'alert'), 500);
      v_since := null;
      if v_since_map ? v_rule then
        v_since := to_timestamp((v_since_map->>v_rule)::bigint);
        if v_since < timestamptz '2020-01-01' or v_since > now() + interval '5 minutes' then v_since := null; end if;
      end if;

      if jsonb_typeof(v_alert->'resolved') = 'boolean' and (v_alert->'resolved')::boolean then
        -- Cleared. Close whatever is open for the rule; an incident that began
        -- and ended between two uploads is recorded closed so the log still has it.
        update public.alert_events set resolved = true, resolved_at = v_ts, ts = greatest(ts, v_ts)
         where node_id = v_node.id and rule = v_rule and not resolved;
        if not found and v_since is not null then
          insert into public.alert_events (node_id, ts, rule, severity, message, resolved, started_at, resolved_at)
          values (v_node.id, v_ts, v_rule, v_sev, v_msg, true, v_since, v_ts)
          on conflict (node_id, rule, started_at) where started_at is not null do nothing;
        end if;
        continue;
      end if;

      v_seen := v_seen || v_rule;
      select * into v_open from public.alert_events
       where node_id = v_node.id and rule = v_rule and not resolved
       order by id desc limit 1;
      if found then
        if v_open.severity <> v_sev or v_open.ts < v_ts - interval '10 minutes' then
          update public.alert_events set severity = v_sev, message = v_msg, ts = greatest(ts, v_ts)
           where id = v_open.id;
        end if;
        continue;
      end if;

      -- Not open. Either the same incident was closed (by an earlier reading that
      -- did not include it, or dismissed by a maintainer), or this is a new one.
      if v_since is not null then
        select * into v_prev from public.alert_events
         where node_id = v_node.id and rule = v_rule and started_at = v_since;
      else
        -- Agents before 2.0.1 send no start time; a dismissal still covers a
        -- report that continues it without a gap.
        select * into v_prev from public.alert_events
         where node_id = v_node.id and rule = v_rule and dismissed_at is not null and ts >= v_ts - v_gap
         order by ts desc limit 1;
      end if;
      if found then
        if v_prev.dismissed_at is not null then
          -- A maintainer called it a false alarm: stay closed, stay visible.
          if v_prev.ts < v_ts - interval '5 minutes' then
            update public.alert_events set ts = v_ts where id = v_prev.id;
          end if;
        else
          update public.alert_events
             set resolved = false, resolved_at = null, severity = v_sev, message = v_msg, ts = greatest(ts, v_ts)
           where id = v_prev.id;
        end if;
        continue;
      end if;

      insert into public.alert_events (node_id, ts, rule, severity, message, resolved, started_at)
      values (v_node.id, v_ts, v_rule, v_sev, v_msg, false, coalesce(v_since, v_ts))
      on conflict (node_id, rule, started_at) where started_at is not null do nothing;
      get diagnostics v_alert_written = row_count;
      v_written := v_written + v_alert_written;
    end loop;

    -- Resolve by absence: the list is complete, so an open incident the agent no
    -- longer reports has ended.
    if v_complete then
      update public.alert_events set resolved = true, resolved_at = v_ts
       where node_id = v_node.id and not resolved and (rule is null or not (rule = any(v_seen)));
    end if;
  end if;

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

create or replace function public.hyn_maintainer_resolve_alert(p_alert_id bigint, p_reason text default null)
returns json language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid;
  v_node uuid;
  v_was_resolved boolean;
begin
  v_actor := public._hyn_require_fleet();

  select node_id, resolved into v_node, v_was_resolved
    from public.alert_events where id = p_alert_id for update;
  if not found then
    raise exception 'no such alert';
  end if;
  if not public.hyn_can_view_node(v_node) then
    raise exception 'that alert is not visible to this account';
  end if;

  if not v_was_resolved then
    -- Dismissed, not merely resolved: ingest keeps a dismissed incident closed
    -- while the agent goes on reporting the same condition.
    update public.alert_events set resolved = true, resolved_at = now(), dismissed_at = now()
     where id = p_alert_id;
    perform public._hyn_audit(
      'alert.resolve.manual', null, v_node,
      jsonb_build_object('alert_id', p_alert_id, 'reason', coalesce(p_reason, ''))
    );
  end if;
  return json_build_object('status', 'ok', 'alert_id', p_alert_id, 'resolved', true);
end $$;

notify pgrst, 'reload schema';
commit;
