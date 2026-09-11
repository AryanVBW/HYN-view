-- Read-only release check. Does not reserve deliveries, alter schedules, or send email.
begin read only;
do $$ declare name text; fn text; begin
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20260911150000') then raise exception 'delivery migration is missing'; end if;
  foreach name in array array['delivery_rules','delivery_digest_settings','delivery_events','delivery_attempts'] loop
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=name and c.relrowsecurity) then raise exception 'RLS missing on %',name; end if;
    if has_table_privilege('anon','public.'||name,'SELECT') or has_table_privilege('authenticated','public.'||name,'SELECT') then raise exception 'private delivery table exposed: %',name; end if;
  end loop;
  foreach fn in array array[
    'public.hyn_reserve_delivery(text,text,uuid,uuid,text,text,uuid[])',
    'public.hyn_complete_delivery(uuid,text,text,text)',
    'public.hyn_due_user_digests(uuid)',
    'public.hyn_user_digest_content(uuid)',
    'public.hyn_defer_web_delivery(uuid,text)'
  ] loop
    if not has_function_privilege('service_role',fn,'EXECUTE') then raise exception 'service permission missing: %',fn; end if;
    if has_function_privilege('anon',fn,'EXECUTE') or has_function_privilege('authenticated',fn,'EXECUTE') then raise exception 'service function exposed: %',fn; end if;
  end loop;
  if not has_table_privilege('service_role','public.delivery_digest_settings','SELECT') then raise exception 'scheduler cannot read digest settings'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claims','{}',true);
do $$ begin
  begin
    perform public.hyn_admin_delivery_dashboard();
    raise exception 'dashboard accepted an unauthenticated context';
  exception when raise_exception then
    if sqlerrm not in ('not authenticated','administrator role required') then raise; end if;
  end;
  begin
    perform public.hyn_admin_set_delivery_rules(null,'[]');
    raise exception 'policy mutation accepted an unauthenticated context';
  exception when raise_exception then
    if sqlerrm not in ('not authenticated','super administrator role required') then raise; end if;
  end;
end $$;
reset role;
select 'delivery production checks passed' as result,
  (select count(*) from public.delivery_digest_settings where configured and enabled) as explicitly_enabled_digest_settings,
  (select count(*) from public.delivery_events) as tracked_messages,
  (select count(*) from public.delivery_attempts) as tracked_attempts;
commit;
