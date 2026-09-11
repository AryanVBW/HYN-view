begin;
create function pg_temp.check_delivery(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok,false) then raise exception 'FAIL delivery: %',label; end if;
  raise notice 'PASS delivery: %',label;
end $$;

insert into auth.users(id,email) values
 ('c1000000-0000-4000-8000-000000000001','super@delivery.test'),
 ('c1000000-0000-4000-8000-000000000002','admin@delivery.test'),
 ('c1000000-0000-4000-8000-000000000003','owner@delivery.test'),
 ('c1000000-0000-4000-8000-000000000004','viewer@delivery.test'),
 ('c1000000-0000-4000-8000-000000000005','other@delivery.test');
update public.profiles set status='active',full_name=split_part(email,'@',1),
 role=case right(id::text,1) when '1' then 'super_admin' when '2' then 'admin' when '3' then 'monitor' else 'viewer' end
 where email like '%@delivery.test';
insert into public.nodes(id,owner,name,token_hash,telemetry_mode) values
 ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003','Mumbai gateway',null,'cloud'),
 ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000003','Private sibling',null,'cloud'),
 ('c2000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','Local server',null,'local'),
 ('c2000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000005','Quiet server',null,'cloud');
insert into public.metrics(node_id,ts,cpu_pct) values
 ('c2000000-0000-4000-8000-000000000001',now(),25),
 ('c2000000-0000-4000-8000-000000000003',now(),95);
-- Metric ingestion intentionally marks a server cloud-managed. Switch it to
-- local after that historical sample, as an actual mode change would do.
update public.nodes set telemetry_mode='local' where id='c2000000-0000-4000-8000-000000000003';

select pg_temp.check_delivery(not (public._hyn_digest_setting('c1000000-0000-4000-8000-000000000004')->>'configured')::boolean,'combined digests default to unconfigured, not bulk opt-in');
select pg_temp.check_delivery(not has_table_privilege('authenticated','public.delivery_attempts','SELECT') and not has_table_privilege('anon','public.delivery_events','SELECT'),'private delivery tables reject direct client access');
select pg_temp.check_delivery(not has_function_privilege('authenticated','public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[])','EXECUTE') and not has_function_privilege('anon','public.hyn_due_user_digests(uuid)','EXECUTE'),'reservation and recipient enumeration are service-only');

set local role authenticated;
set local "test.uid"='c1000000-0000-4000-8000-000000000002';
do $$ begin
  begin perform public.hyn_admin_set_delivery_rules(null,'[{"kind":"all","enabled":false,"daily_limit":0,"max_attempts":1,"retry_minutes":1}]');
    raise exception 'ordinary admin changed budgets';
  exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
  perform public.hyn_admin_delivery_dashboard();
  raise notice 'PASS delivery: ordinary admin is read-only';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000004';
do $$ begin
  begin perform public.hyn_admin_delivery_dashboard(); raise exception 'viewer read delivery history';
  exception when raise_exception then if sqlerrm<>'administrator role required' then raise; end if; end;
  raise notice 'PASS delivery: viewer cannot enumerate delivery history';
end $$;
set local "test.uid"='c1000000-0000-4000-8000-000000000001';
do $$ begin
  begin perform public.hyn_admin_set_digest(null,true,'00:00','UTC',false,false); raise exception 'global confirmation bypass';
  exception when others then if sqlerrm='global confirmation bypass' then raise; end if; end;
  begin perform public.hyn_admin_set_digest(null,true,'00:00','Not/A_Timezone',false,true); raise exception 'invalid timezone accepted';
  exception when others then if sqlerrm='invalid timezone accepted' then raise; end if; end;
  raise notice 'PASS delivery: global schedule requires explicit confirmation and valid timezone';
end $$;
select public.hyn_admin_set_dashboard_access('c1000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000003',true);
select public.hyn_admin_set_server_access('c1000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000001',true);
select public.hyn_admin_set_server_access('c1000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000002',false);
select public.hyn_admin_set_server_access('c1000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000003',true);
select public.hyn_admin_set_server_access('c1000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000004',true);
select public.hyn_admin_set_digest('c1000000-0000-4000-8000-000000000004',true,'00:00','UTC');
reset role;
update public.server_access set notifications_allowed=node_id in ('c2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000003') where viewer_id='c1000000-0000-4000-8000-000000000004';
do $$ declare content jsonb; begin
  content:=public.hyn_user_digest_content('c1000000-0000-4000-8000-000000000004');
  perform pg_temp.check_delivery(jsonb_array_length(content->'nodes')=2,'one combined digest includes the exact permitted notification-enabled server set');
  perform pg_temp.check_delivery(not exists(select 1 from jsonb_array_elements(content->'nodes') n where n->>'name' in ('Private sibling','Quiet server')),'explicit denial and shared notification opt-out exclude servers');
  perform pg_temp.check_delivery(exists(select 1 from jsonb_array_elements(content->'nodes') n where n->>'name'='Local server' and coalesce((n->>'sample_count')::integer,0)=0),'local-only telemetry is not leaked from old cloud history');
end $$;
update public.profiles set status='suspended' where id='c1000000-0000-4000-8000-000000000004';
select pg_temp.check_delivery(not exists(select 1 from public._hyn_digest_nodes('c1000000-0000-4000-8000-000000000004')),'suspended recipients have no digest scope');
update public.profiles set status='active' where id='c1000000-0000-4000-8000-000000000004';
update public.server_access set allowed=false where viewer_id='c1000000-0000-4000-8000-000000000004' and node_id='c2000000-0000-4000-8000-000000000001';
do $$ declare r jsonb; begin
  r:=public.hyn_reserve_delivery('digest-stale','daily','c1000000-0000-4000-8000-000000000004',null,'viewer@delivery.test','Combined',array['c2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000003']::uuid[]);
  perform pg_temp.check_delivery(not (r->>'allowed')::boolean,'revoked server access is rechecked before reserving the email');
end $$;
update public.server_access set allowed=true where viewer_id='c1000000-0000-4000-8000-000000000004' and node_id='c2000000-0000-4000-8000-000000000001';

set local role authenticated;
select public.hyn_admin_set_delivery_rules(null,'[{"kind":"all","enabled":true,"daily_limit":3,"max_attempts":2,"retry_minutes":1}]');
select public.hyn_admin_set_delivery_rules('c1000000-0000-4000-8000-000000000005','[{"kind":"all","enabled":true,"daily_limit":0,"max_attempts":5,"retry_minutes":1}]');
reset role;
do $$ declare a jsonb; b jsonb; c jsonb; id uuid; begin
  a:=public.hyn_reserve_delivery('quota-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Signed in');
  perform pg_temp.check_delivery((a->>'allowed')::boolean,'first email reserves an attempt');
  b:=public.hyn_reserve_delivery('quota-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Signed in');
  perform pg_temp.check_delivery(not (b->>'allowed')::boolean,'in-flight duplicate cannot reserve another attempt');
  perform public.hyn_complete_delivery((a->>'attempt_id')::uuid,'sent','provider-fixture',null);
  b:=public.hyn_reserve_delivery('quota-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Signed in');
  perform pg_temp.check_delivery((b->>'already_sent')::boolean,'accepted idempotency key is reused without provider dispatch');
  a:=public.hyn_reserve_delivery('quota-2','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Another sign in');
  perform public.hyn_complete_delivery((a->>'attempt_id')::uuid,'failed',null,'Definite rejection');
  b:=public.hyn_reserve_delivery('quota-2','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Another sign in');
  perform pg_temp.check_delivery(not (b->>'allowed')::boolean,'failed sends respect the retry backoff');
  update public.delivery_events set next_retry_at=now()-interval '1 minute' where source_key='quota-2';
  b:=public.hyn_reserve_delivery('quota-2','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Another sign in');
  perform pg_temp.check_delivery((b->>'allowed')::boolean,'definite failure may reserve a bounded retry');
  perform public.hyn_complete_delivery((b->>'attempt_id')::uuid,'failed',null,'Second rejection');
  perform pg_temp.check_delivery((select terminal and attempt_count=2 from public.delivery_events where source_key='quota-2'),'maximum attempt count terminates retries');
  c:=public.hyn_reserve_delivery('quota-3','incident','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Heartbeat');
  perform pg_temp.check_delivery(not (c->>'allowed')::boolean and (select count(*) from public.delivery_attempts)=3,'global cap counts failed attempts and blocks a different type');
  c:=public.hyn_reserve_delivery('user-zero','signin','c1000000-0000-4000-8000-000000000005',null,'other@delivery.test','Signed in');
  perform pg_temp.check_delivery(not (c->>'allowed')::boolean,'zero user cap never bypasses global policy');
end $$;

set local role authenticated;
select public.hyn_admin_set_delivery_rules(null,'[{"kind":"all","enabled":true,"daily_limit":null,"max_attempts":3,"retry_minutes":1},{"kind":"incident","enabled":true,"daily_limit":0,"max_attempts":3,"retry_minutes":1}]');
reset role;
do $$ declare r jsonb; begin
  r:=public.hyn_reserve_delivery('kind-zero','incident','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Incident');
  perform pg_temp.check_delivery(not (r->>'allowed')::boolean,'type-specific cap blocks while the overall budget is unlimited');
  r:=public.hyn_reserve_delivery('unknown-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Sign in');
  perform public.hyn_complete_delivery((r->>'attempt_id')::uuid,'unknown',null,'No provider response');
  r:=public.hyn_reserve_delivery('unknown-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Sign in');
  perform pg_temp.check_delivery(not (r->>'allowed')::boolean and (select terminal from public.delivery_events where source_key='unknown-1'),'ambiguous outcomes are terminal and cannot send duplicates');
  r:=public.hyn_reserve_delivery('stop-1','signin','c1000000-0000-4000-8000-000000000003',null,'owner@delivery.test','Sign in');
  perform public.hyn_complete_delivery((r->>'attempt_id')::uuid,'failed',null,'Provider busy');
end $$;
set local role authenticated;
do $$ declare d jsonb; event_id uuid; begin
  d:=public.hyn_admin_delivery_dashboard('c1000000-0000-4000-8000-000000000003');
  select (e->>'id')::uuid into event_id from jsonb_array_elements(d->'events') e where e->>'subject'='Sign in' and e->>'status'='failed' limit 1;
  perform public.hyn_admin_stop_delivery(event_id);
  raise notice 'PASS delivery: super admin can stop a pending retry';
end $$;
reset role;
select pg_temp.check_delivery((select terminal and status='cancelled' and attempt_count=1 from public.delivery_events where source_key='stop-1') and exists(select 1 from public.delivery_attempts a join public.delivery_events e on e.id=a.event_id where e.source_key='stop-1'),'stopping retries retains the immutable attempt history');

do $$ declare r jsonb; key text; begin
  key:='user-digest:c1000000-0000-4000-8000-000000000004:'||(now() at time zone 'UTC')::date;
  r:=public.hyn_reserve_delivery(key,'daily','c1000000-0000-4000-8000-000000000004',null,'viewer@delivery.test','Combined',array['c2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000003']::uuid[]);
  perform pg_temp.check_delivery((r->>'allowed')::boolean,'one user-level reservation covers multiple permitted servers');
  perform public.hyn_complete_delivery((r->>'attempt_id')::uuid,'sent','digest-fixture',null);
  r:=public.hyn_reserve_delivery(key,'daily','c1000000-0000-4000-8000-000000000004',null,'viewer@delivery.test','Combined',array['c2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000003']::uuid[]);
  perform pg_temp.check_delivery((r->>'already_sent')::boolean,'same user/date produces only one accepted digest');
end $$;
set local role authenticated;
select public.hyn_admin_set_digest(null,true,'00:00','UTC',false,true);
select public.hyn_admin_set_digest('c1000000-0000-4000-8000-000000000004',false,'00:00','UTC');
reset role;
select pg_temp.check_delivery(not (public._hyn_digest_setting('c1000000-0000-4000-8000-000000000004')->>'enabled')::boolean,'individual digest opt-out overrides a globally enabled schedule');
rollback;
