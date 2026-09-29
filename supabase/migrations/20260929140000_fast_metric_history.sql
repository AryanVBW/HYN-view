-- Metric history charts check access once per call, not once per row.
--
-- hyn_metric_history and hyn_fleet_metric_history ran as the caller, so row
-- level security on metrics called hyn_can_view_node() for every row. Measured
-- on production on 2026-09-29: 105 ms for one server's 1,181 rows and 378 ms for
-- the fleet's 4,193. Both now run as the function owner and check access once:
--   hyn_metric_history(node)   hyn_can_view_node(node), the rule the metrics
--                              policy applies to every row
--   hyn_fleet_metric_history() hyn_is_admin(), as before
-- Callers without access still get an empty list. Rows outside the 48-hour
-- window the policy enforces are still excluded by the queries themselves.
begin;

create or replace function public.hyn_metric_history(p_node uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(h) || '{"payload":null,"sensors":null}'::jsonb order by h.ts),'[]'::jsonb)
  from (
    select distinct on (floor(extract(epoch from m.ts)/300))
      m.id,m.node_id,m.ts,m.cpu_pct,m.cpu_temp_c,m.cpu_mhz,m.cpu_model,m.cpu_steal,m.cpu_iowait,m.cpu_cores,
      m.load1,m.mem_pct,m.mem_total,m.mem_used,m.swap_used,m.disk_pct,m.uptime_s,
      m.net_iface,m.net_rx_bps,m.net_tx_bps,m.net_retrans_pm,m.latency_ms,
      m.net_link_mbps,m.psi_cpu,m.psi_mem,m.psi_io,m.tcp_estab,m.conntrack_pct,m.proc_count
    from public.metrics m
    where (select public.hyn_can_view_node(p_node))
      and m.node_id=p_node and m.ts>=now()-interval '48 hours' and m.ts<=now()+interval '5 minutes'
    order by floor(extract(epoch from m.ts)/300) desc,m.ts desc limit 600
  ) h
$$;
revoke all on function public.hyn_metric_history(uuid) from public, anon;
grant execute on function public.hyn_metric_history(uuid) to authenticated;

create or replace function public.hyn_fleet_metric_history()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(h) order by h.ts),'[]'::jsonb)
  from (
    select to_timestamp(floor(extract(epoch from m.ts)/1800)*1800) as ts,
      avg(m.cpu_pct) as cpu_pct,avg(m.net_rx_bps) as net_rx_bps,avg(m.net_tx_bps) as net_tx_bps
    from public.metrics m join public.nodes n on n.id=m.node_id join public.profiles o on o.id=n.owner
    where (select public.hyn_is_admin()) and not n.is_demo and not n.revoked
      and m.ts>=now()-interval '24 hours' and m.ts<=now()
    group by floor(extract(epoch from m.ts)/1800)
    order by floor(extract(epoch from m.ts)/1800) desc limit 49
  ) h
$$;
revoke all on function public.hyn_fleet_metric_history() from public, anon;
grant execute on function public.hyn_fleet_metric_history() to authenticated;

notify pgrst, 'reload schema';
commit;
