-- hyn-view: Highway telemetry in the demo node's payload.
--
-- The dashboard's Highway section reads metrics.payload->'highway', so a demo
-- node seeded before that section existed shows the honest "no Highway telemetry
-- in this push" empty state. This replaces hyn_demo_seed so `Load demo data`
-- produces a node with services, a mesh tunnel and a journal, exactly as a
-- paired relay would. Body is copied verbatim from supabase/schema.sql; the two
-- must stay identical.
--
-- Existing demo nodes are patched in place below rather than reseeded, so a
-- dashboard someone is already looking at fills in without a click.

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

-- Backfill any demo node already in the database. Real nodes are untouched:
-- their payloads are what their agent sent, and inventing telemetry for a real
-- machine would be a lie about a machine someone relies on.
update public.metrics m
   set payload = coalesce(m.payload, '{}'::jsonb) || jsonb_build_object(
         'highway', jsonb_build_object(
           'present', 1, 'tracked', true, 'health', 'ok',
           'health_why', '2 unit(s) active',
           'version', 'v0.1.75', 'version_src', 'file',
           'latest', 'v0.1.80', 'update_available', 1,
           'bin_path', '/usr/local/bin/highway', 'bin_size', 48234496,
           'units_total', 2, 'units_active', 2, 'units_failed', 0,
           'units', jsonb_build_array(
             jsonb_build_object('name', 'highway.service', 'state', 'active',
               'sub', 'running', 'restarts', 1, 'memory', 402653184, 'active_s', 1900800),
             jsonb_build_object('name', 'nebula.service', 'state', 'active',
               'sub', 'running', 'restarts', 0, 'memory', 18874368, 'active_s', 1900800)
           ),
           'pid', 1471, 'cpu_tenths', 63, 'rss', 402653184, 'threads', 19, 'fds', 48,
           'proc_uptime_s', 1900800,
           'mesh_iface', 'nebula1', 'mesh_rx_bps', 1100000, 'mesh_tx_bps', 850000,
           'mesh_rx_total', 88000000000::bigint, 'mesh_tx_total', 44000000000::bigint,
           'mesh_drops', 0,
           'qdisc', 'fq_codel', 'qdisc_drops', 0, 'congestion', 'bbr', 'nft_tables', 3,
           'journal_err_1h', 0, 'journal_warn_1h', 2,
           'journal_tail', jsonb_build_array('demo: peer handshake retry', 'demo: lighthouse reconnect')
         ))
 where exists (select 1 from public.nodes n where n.id = m.node_id and n.is_demo)
   and not (coalesce(m.payload, '{}'::jsonb) ? 'highway');
