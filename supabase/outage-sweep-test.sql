-- Database outage sweep (migrations/20260929150000_outage_sweep.sql): records
-- online/offline per server and queues one email per real transition, only for
-- servers whose owner turned incident alerts on. Rolled back.
\set ON_ERROR_STOP on
begin;
-- Other suites leave servers behind; keep them out of this one's counts.
update public.nodes set is_demo = true;
insert into auth.users(id,email) values ('4f100000-0000-4000-8000-000000000001','owner@outage.test');
insert into public.nodes(id,owner,name,last_heartbeat_at,status,paused_until,is_demo,config) values
  ('4f100000-0000-4000-8000-0000000000a1','4f100000-0000-4000-8000-000000000001','steady',     now()-interval '30 seconds','active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a2','4f100000-0000-4000-8000-000000000001','goes quiet', now()-interval '10 minutes','active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a3','4f100000-0000-4000-8000-000000000001','long gone',  now()-interval '9 days','active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a4','4f100000-0000-4000-8000-000000000001','comes back', now()-interval '5 seconds','active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a5','4f100000-0000-4000-8000-000000000001','paused',     now()-interval '1 hour','paused',now()+interval '1 hour',false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a6','4f100000-0000-4000-8000-000000000001','pause over', now()-interval '1 hour','paused',now()-interval '1 minute',false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a7','4f100000-0000-4000-8000-000000000001','no beats',   null,'active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a8','4f100000-0000-4000-8000-000000000001','opted out',  now()-interval '10 minutes','active',null,false,'{}'),
  ('4f100000-0000-4000-8000-0000000000a9','4f100000-0000-4000-8000-000000000001','slow beat',  now()-interval '5 minutes','active',null,false,'{"heartbeat_sec":"120"}');
insert into public.email_preferences(node_id,recipient,incident_enabled)
  select id, 'owner@outage.test', name <> 'opted out' from public.nodes where owner = '4f100000-0000-4000-8000-000000000001'
on conflict (node_id) do update set recipient = excluded.recipient, incident_enabled = excluded.incident_enabled;
-- What the sweep saw last time: steady, goes quiet, opted out, slow beat and
-- pause over were online; comes back was offline; long gone is new.
insert into public.node_watchdogs(node_id,state,last_alert_state)
  select id, 'starting', case name when 'comes back' then 'offline' else 'online' end
    from public.nodes where owner = '4f100000-0000-4000-8000-000000000001' and name <> 'long gone' and name <> 'no beats';

create function pg_temp.state(p_name text) returns text language sql as $$
  select w.state || '/' || w.last_alert_state from public.node_watchdogs w join public.nodes n on n.id = w.node_id
   where n.name = p_name and n.owner = '4f100000-0000-4000-8000-000000000001';
$$;

do $$ declare r jsonb; v_subjects text; begin
  r := public._hyn_outage_sweep();
  if pg_temp.state('steady') <> 'running/online' or pg_temp.state('goes quiet') <> 'running/offline'
     or pg_temp.state('long gone') <> 'running/offline' or pg_temp.state('comes back') <> 'running/online'
     or pg_temp.state('pause over') <> 'running/offline' or pg_temp.state('opted out') <> 'running/offline'
     or pg_temp.state('slow beat') <> 'running/online' or pg_temp.state('paused') <> 'stopped/online'
     or pg_temp.state('no beats') is not null then
    raise exception 'sweep recorded the wrong states: %', (select jsonb_object_agg(n.name, w.state || '/' || w.last_alert_state)
      from public.node_watchdogs w join public.nodes n on n.id = w.node_id where n.owner = '4f100000-0000-4000-8000-000000000001');
  end if;
  select string_agg(j.severity || ' ' || j.subject, ' | ' order by j.subject) into v_subjects
    from public.web_notification_jobs j join public.nodes n on n.id = j.node_id
   where n.owner = '4f100000-0000-4000-8000-000000000001';
  if v_subjects is distinct from
     'crit [HYN CRIT] goes quiet missed three heartbeats | crit [HYN CRIT] pause over missed three heartbeats | info [HYN RECOVERED] comes back is reporting again' then
    raise exception 'sweep queued the wrong emails: % (%)', v_subjects, r;
  end if;
  if r->>'transitions' <> '5' or r->>'emails_queued' <> '3' then raise exception 'sweep summary is wrong: %', r; end if;
  raise notice 'PASS  the sweep marks servers offline after three missed beats and emails only real transitions to opted-in owners';
end $$;

do $$ declare r jsonb; begin
  r := public._hyn_outage_sweep();
  if r->>'transitions' <> '0' or r->>'emails_queued' <> '0'
     or (select count(*) from public.web_notification_jobs j join public.nodes n on n.id = j.node_id
          where n.owner = '4f100000-0000-4000-8000-000000000001') <> 3 then
    raise exception 'a second sweep repeated the alerts: %', r;
  end if;
  update public.nodes set last_heartbeat_at = now() where name = 'goes quiet' and owner = '4f100000-0000-4000-8000-000000000001';
  r := public._hyn_outage_sweep();
  if r->>'emails_queued' <> '1' or not exists(select 1 from public.web_notification_jobs
       where subject = '[HYN RECOVERED] goes quiet is reporting again' and category = 'alert' and severity = 'info') then
    raise exception 'recovery was not reported: %', r;
  end if;
  raise notice 'PASS  a repeated sweep sends nothing new, and a server that beats again is reported recovered once';
end $$;

do $$ declare r json; begin
  update public.web_notification_jobs set status = 'sent' where node_id not in (select id from public.nodes where owner = '4f100000-0000-4000-8000-000000000001');
  r := public.hyn_claim_web_notification(null);
  if r->>'status' <> 'send' or r->>'recipient' <> 'owner@outage.test' or r->>'fingerprint' not like 'outage:%' then
    raise exception 'the portal cannot claim an outage email: %', r;
  end if;
  raise notice 'PASS  outage emails go out through the normal notification queue';
end $$;
rollback;
