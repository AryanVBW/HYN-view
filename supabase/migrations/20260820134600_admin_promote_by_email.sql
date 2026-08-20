-- Promote an existing client to administrator by email, for the "add another
-- admin" action in the admin panel. See supabase/schema.sql for the full
-- rationale; kept in a separate migration because it depends on
-- _hyn_require_admin and _hyn_audit already existing.

create or replace function public.hyn_admin_promote_by_email(p_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  perform public._hyn_require_admin();

  select id into v_target from public.profiles where lower(email) = lower(trim(p_email));
  if v_target is null then
    return json_build_object('status', 'not_found');
  end if;

  update public.profiles set role = 'admin', updated_at = now() where id = v_target;

  perform public._hyn_audit('client.role.admin', v_target, null,
    jsonb_build_object('via', 'promote_by_email'));

  return json_build_object('status', 'ok', 'user_id', v_target);
end;
$$;

revoke all on function public.hyn_admin_promote_by_email(text) from public;
grant execute on function public.hyn_admin_promote_by_email(text) to authenticated;
