\set ON_ERROR_STOP on
begin;
do $$
begin
  if not public._hyn_portal_config_valid('{"keep_awake":"on","alert_enabled":"off","report_enabled":"on","record_interval_min":"5","alert_interval_min":"2","speedtest_per_day":"4"}') then
    raise exception 'valid unattended configuration refused';
  end if;
  raise notice 'PASS  bounded unattended settings are accepted';
  if public._hyn_portal_config_valid('{"keep_awake":"on;reboot"}')
     or public._hyn_portal_config_valid('{"record_interval_min":"0"}')
     or public._hyn_portal_config_valid('{"alert_interval_min":"1441"}')
     or public._hyn_portal_config_valid('{"speedtest_per_day":"25"}') then
    raise exception 'unsafe unattended value accepted';
  end if;
  raise notice 'PASS  invalid unattended settings are refused';
  -- Storage is now a managed local/cloud choice. An unknown storage mode and
  -- an arbitrary destination must still fail in both legacy and current schemas.
  if public._hyn_portal_config_valid('{"keep_awake":"on","cloud_storage":"offsite"}')
     or public._hyn_portal_config_valid('{"keep_awake":"on","cloud_api_url":"https://example.com"}') then
    raise exception 'unattended configuration accepted an unknown storage mode or endpoint';
  end if;
  raise notice 'PASS  unattended settings reject unknown storage modes and custom endpoints';
end $$;
rollback;
