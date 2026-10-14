-- Keep the Highway operations section of an agent push.
--
-- The agent now reports `operations`: which option of Highway's own installer menu
-- (UPDATE & REPAIR, REPAIR CONNECT, REACTIVATE, CREATE BACKUP, START RELAYER) the
-- box needs, the state behind that choice (overlay and API certificate lifetime,
-- renew gate, kill switch, held-down marker, network and version files), and the
-- state of the local recovery backup file (present, age, size, permissions,
-- header, stale after a key change). Scalars only; the sanitiser drops anything
-- it does not list, so without this the section is silently discarded.
--
-- This replaces the function as 20261014120000 left it, plus the one new group.
-- Apply BEFORE deploying the portal change that renders it and before agents that
-- send it are rolled out. Safe to re-run: it only replaces one function.
begin;

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
    ('system', array['tracked','units_total','units_active','units_failed']),
    ('operations', array['box_state','action','action_why','renew_gate','overlay_left_s','cert_days','killswitch','held_down','network','os_version','relayer_version','config_version','backup_present','backup_age_s','backup_size','backup_stale','backup_perms_ok','backup_magic_ok','maintenance','maintenance_why']),
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
        where ordinality <= 48 and jsonb_typeof(value)='object') a;
    v := jsonb_set(v,'{highway,units}',items);
  end if;
  -- Base-system services (sshd, cron, network, time sync, journal): same bounded
  -- scalar fields as the Highway units, kept in their own section.
  if jsonb_typeof(p_payload#>'{system,units}') = 'array' then
    select coalesce(jsonb_agg(public._hyn_monitoring_fields(value, array['name','state','sub','restarts','memory','active_s'])),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload#>'{system,units}') with ordinality
        where ordinality <= 48 and jsonb_typeof(value)='object') a;
    v := jsonb_set(v,'{system,units}',items);
  end if;
  -- Names of every unit systemd reports as failed, listed or not. Strings only,
  -- truncated, capped; never log text.
  if jsonb_typeof(p_payload#>'{system,failed_units}') = 'array' then
    select coalesce(jsonb_agg(to_jsonb(left(value #>> '{}', 128))),'[]'::jsonb)
      into items from (select value from jsonb_array_elements(p_payload#>'{system,failed_units}') with ordinality
        where ordinality <= 16 and jsonb_typeof(value)='string') a;
    v := jsonb_set(v,'{system,failed_units}',items);
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

commit;
