begin;
insert into auth.users(id,email) values
 ('e1000000-0000-4000-8000-000000000001','super@node-relay.test'),
 ('e1000000-0000-4000-8000-000000000002','owner@node-relay.test'),
 ('e1000000-0000-4000-8000-000000000003','other@node-relay.test'),
 ('e1000000-0000-4000-8000-000000000004','viewer@node-relay.test'),
 ('e1000000-0000-4000-8000-000000000005','admin@node-relay.test');
update public.profiles set role=case
  when email='super@node-relay.test' then 'super_admin'
  when email='admin@node-relay.test' then 'admin'
  when email='viewer@node-relay.test' then 'viewer' else 'monitor' end
  where email like '%@node-relay.test';
insert into public.nodes(id,owner,name,is_demo,revoked) values
 ('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000002','Gateway',false,false),
 ('e2000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002','Backup',false,false),
 ('e2000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-000000000003','Other owner',false,false),
 ('e2000000-0000-4000-8000-000000000004','e1000000-0000-4000-8000-000000000002','Demo',true,false),
 ('e2000000-0000-4000-8000-000000000005','e1000000-0000-4000-8000-000000000002','Revoked',false,true);
insert into public.relayer_assignments(id,owner,relayer_id,relayer_name) values
 ('e3000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000002',1457,'Gateway relay'),
 ('e3000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002',1458,'Backup relay'),
 ('e3000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-000000000003',1459,'Other relay');
set local role authenticated;
set local "test.uid"='e1000000-0000-4000-8000-000000000001';
do $$ declare v_node uuid; begin
  if exists(select 1 from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001')) then raise exception 'account assignment auto-linked a server'; end if;
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001');
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001');
  if (select count(*) from public.admin_audit where action='node.relayer.link' and target_node='e2000000-0000-4000-8000-000000000001')<>1 then raise exception 'link must be audited once'; end if;
  if (select relayer_id from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'))<>1457 then raise exception 'wrong server link'; end if;
  if exists(select 1 from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000002')) then raise exception 'link spread to another server'; end if;
  begin
    perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000001');
    raise exception 'linked the same relay twice';
  exception when sqlstate 'PT409' then null; end;
  begin
    perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000003');
    raise exception 'linked a foreign assignment';
  exception when raise_exception then if sqlerrm<>'Choose a relayer assigned to this server''s account' then raise; end if; end;
  foreach v_node in array array['e2000000-0000-4000-8000-000000000004','e2000000-0000-4000-8000-000000000005']::uuid[] loop
    begin
      perform public.hyn_admin_set_node_relayer(v_node,'e3000000-0000-4000-8000-000000000002');
      raise exception 'linked an unavailable server';
    exception when raise_exception then if sqlerrm<>'Choose an available, non-demo server' then raise; end if; end;
  end loop;
  raise notice 'PASS  explicit server relay links are unique, same-owner, idempotent and audited';
end $$;
do $$ declare actor text; begin
  foreach actor in array array['e1000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000004','e1000000-0000-4000-8000-000000000005'] loop
    perform set_config('test.uid',actor,true);
    begin perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001',null); raise exception 'non-super-admin changed a link';
    exception when raise_exception then if sqlerrm<>'super administrator role required' then raise; end if; end;
    begin delete from public.node_relayer_links; raise exception 'direct link deletion succeeded'; exception when insufficient_privilege then null; end;
    begin update public.node_relayer_links set assignment_id='e3000000-0000-4000-8000-000000000002'; raise exception 'direct link update succeeded'; exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'PASS  owners, Viewers and Admins cannot change server relay links';
end $$;
set local "test.uid"='e1000000-0000-4000-8000-000000000002';
do $$ begin
  if (select relayer_id from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'))<>1457 then raise exception 'owner cannot read link'; end if;
  begin perform * from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000003'); raise exception 'foreign server readable'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  owners see their server links without access to another owner''s server';
end $$;
set local "test.uid"='e1000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_server_access('e1000000-0000-4000-8000-000000000004','e2000000-0000-4000-8000-000000000001',true);
set local "test.uid"='e1000000-0000-4000-8000-000000000004';
do $$ begin
  if (select count(*) from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'))<>1 then raise exception 'shared relay missing'; end if;
  if exists(select 1 from public.relayer_assignments) then raise exception 'server share granted account relay access'; end if;
  if (select count(*) from public.node_relayer_links)<>1 then raise exception 'shared link visibility'; end if;
  begin perform * from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000002'); raise exception 'unshared server readable'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  server-only shares expose exactly the linked relay without account-wide access';
end $$;
set local "test.uid"='e1000000-0000-4000-8000-000000000001';
select public.hyn_admin_set_server_access('e1000000-0000-4000-8000-000000000004','e2000000-0000-4000-8000-000000000001',false);
set local "test.uid"='e1000000-0000-4000-8000-000000000004';
do $$ begin
  if exists(select 1 from public.node_relayer_links) then raise exception 'revoked share retains link'; end if;
  begin perform * from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'); raise exception 'revoked share retains relay'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  revoking server access removes relay visibility';
end $$;
reset role;
do $$ begin
  begin
    insert into public.node_relayer_links(node_id,owner,assignment_id) values
      ('e2000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000003','e3000000-0000-4000-8000-000000000003');
    raise exception 'cross-owner link bypassed constraints';
  exception when foreign_key_violation then null; end;
  raise notice 'PASS  composite foreign keys enforce matching server and relay ownership';
end $$;
update public.profiles set status='suspended' where id='e1000000-0000-4000-8000-000000000002';
set local role authenticated;
set local "test.uid"='e1000000-0000-4000-8000-000000000002';
do $$ begin
  begin perform * from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'); raise exception 'suspended owner reads link'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  suspended sessions lose linked relay access';
end $$;
reset role;
update public.profiles set status='active' where id='e1000000-0000-4000-8000-000000000002';
set local role authenticated;
set local "test.uid"='e1000000-0000-4000-8000-000000000001';
do $$ begin
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002');
  if (select relayer_id from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'))<>1458 then raise exception 'replacement failed'; end if;
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001',null);
  if exists(select 1 from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001')) then raise exception 'unlink failed'; end if;
  if (select count(*) from public.relayer_assignments where owner='e1000000-0000-4000-8000-000000000002')<>2 then raise exception 'unlink deleted account assignment'; end if;
  if not exists(select 1 from public.admin_audit where action='node.relayer.unlink' and target_node='e2000000-0000-4000-8000-000000000001') then raise exception 'unlink not audited'; end if;
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002');
  perform public.hyn_admin_remove_relayer('e3000000-0000-4000-8000-000000000002');
  if exists(select 1 from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001')) then raise exception 'removed assignment left link'; end if;
  perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000001');
  raise notice 'PASS  replacing and unlinking preserve account assignments; assignment removal clears the link';
end $$;
reset role;
delete from public.nodes where id='e2000000-0000-4000-8000-000000000002';
do $$ begin
  if exists(select 1 from public.node_relayer_links where node_id='e2000000-0000-4000-8000-000000000002') then raise exception 'deleted server left a link'; end if;
  raise notice 'PASS  deleting a server removes its relay link';
end $$;
set local role anon;
set local "test.uid"='';
do $$ begin
  begin perform * from public.hyn_node_relayer('e2000000-0000-4000-8000-000000000001'); raise exception 'anonymous relay read'; exception when insufficient_privilege then null; end;
  begin perform public.hyn_admin_set_node_relayer('e2000000-0000-4000-8000-000000000001',null); raise exception 'anonymous link write'; exception when insufficient_privilege then null; end;
  raise notice 'PASS  anonymous sessions cannot read or change server relay links';
end $$;
rollback;
