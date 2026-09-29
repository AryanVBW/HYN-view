-- The fleet view reads one latest reading per server in one call.
--
-- The maintainer page fetched the newest 2,000 metrics rows of the last 24
-- hours (every column, including the payload) plus 500 speed tests and kept the
-- newest per server. On production on 2026-09-29 that was 7.5 MB and 409 ms per
-- page load, repeated by the page's live refresh, and it still missed any server
-- whose last reading was older than the newest 2,000 rows: at one-minute
-- uploads, about three hours for ten servers.
--
-- hyn_fleet_latest_readings() returns, for every non-revoked server, its newest
-- metrics row (scalar columns only, no payload or sensors) and newest speed test
-- from the last 24 hours. It uses the (node_id, ts desc) indexes and checks
-- fleet access once. Callers without fleet access get empty lists.
begin;

create or replace function public.hyn_fleet_latest_readings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'metrics', coalesce(jsonb_agg(to_jsonb(m) || '{"payload":null,"sensors":null}'::jsonb) filter (where m.id is not null), '[]'::jsonb),
    'speedtests', coalesce(jsonb_agg(to_jsonb(s)) filter (where s.id is not null), '[]'::jsonb))
  from public.nodes n
  left join lateral (
    select m.id,m.node_id,m.ts,m.cpu_pct,m.cpu_temp_c,m.cpu_mhz,m.cpu_model,m.cpu_steal,m.cpu_iowait,m.cpu_cores,
      m.load1,m.mem_pct,m.mem_total,m.mem_used,m.swap_used,m.disk_pct,m.uptime_s,
      m.net_iface,m.net_rx_bps,m.net_tx_bps,m.net_retrans_pm,m.latency_ms,
      m.net_link_mbps,m.psi_cpu,m.psi_mem,m.psi_io,m.tcp_estab,m.conntrack_pct,m.proc_count
    from public.metrics m
    where m.node_id = n.id and m.ts >= now() - interval '24 hours' and m.ts <= now() + interval '5 minutes'
    order by m.ts desc limit 1
  ) m on true
  left join lateral (
    select s.* from public.speedtests s
    where s.node_id = n.id and s.ts >= now() - interval '24 hours' and s.ts <= now() + interval '5 minutes'
    order by s.ts desc limit 1
  ) s on true
  where (select public.hyn_can_view_fleet()) and not n.revoked;
$$;
revoke all on function public.hyn_fleet_latest_readings() from public, anon;
grant execute on function public.hyn_fleet_latest_readings() to authenticated;

notify pgrst, 'reload schema';
commit;
