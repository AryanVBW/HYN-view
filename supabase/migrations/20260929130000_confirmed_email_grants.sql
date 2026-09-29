-- Administrator grants made by email address require a confirmed address.
--
-- hyn_claim_env_admin (the admin_allowlist bootstrap: Super admin on sign-in)
-- and hyn_admin_promote_by_email (an admin typing an address) grant a role to
-- whichever account holds that address. Supabase Auth can hold an account for an
-- address nobody has proved they own: an unconfirmed email sign-up, or any
-- sign-up while email auto-confirm is on. Registering an address before its
-- owner did was therefore enough to receive the grant meant for them.
--
-- Both now require auth.users.email_confirmed_at. Promotion by email also
-- matches the account's current Auth address instead of the copy saved in
-- profiles at sign-up, and refuses an unconfirmed account with an error so that
-- older portals do not report it as promoted.
-- email_confirmed_at proves mailbox ownership only while GoTrue email
-- auto-confirm is off (ENABLE_EMAIL_AUTOCONFIRM=false in the self-hosted .env).
begin;

create or replace function public.hyn_claim_env_admin(p_caller_email text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_real_email text;
  v_confirmed timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select email, email_confirmed_at into v_real_email, v_confirmed from auth.users where id = v_uid;
  if v_real_email is null then
    return json_build_object('status', 'no_email');
  end if;
  -- p_caller_email is optional now that the list lives here; when supplied it
  -- must be the caller's own address.
  if p_caller_email is not null and p_caller_email <> ''
     and lower(v_real_email) <> lower(p_caller_email) then
    raise exception 'email does not match the authenticated session';
  end if;

  if not exists (
    select 1 from public.admin_allowlist a where lower(a.email) = lower(v_real_email)
  ) then
    return json_build_object('status', 'not_allowed');
  end if;
  -- The entry stays on the list until its owner confirms the address.
  if v_confirmed is null then
    return json_build_object('status', 'unconfirmed');
  end if;

  perform pg_advisory_xact_lock(74821901);
  if not public.hyn_is_active() then raise exception 'active account required'; end if;
  delete from public.admin_allowlist where lower(email)=lower(v_real_email);
  if not found then return json_build_object('status','not_allowed'); end if;
  perform public._hyn_audit('client.role.super_admin',v_uid,null,jsonb_build_object('via','bootstrap_allowlist'));
  update public.profiles
     set role = 'super_admin', updated_at = now()
   where id = v_uid and role <> 'super_admin';

  return json_build_object('status', 'ok', 'role', 'super_admin');
end;
$$;

create or replace function public.hyn_admin_promote_by_email(p_email text)
returns json language plpgsql security definer set search_path = public as $$
declare v_target uuid; v_role text; v_confirmed timestamptz;
begin
  perform public._hyn_require_staff();
  select p.id, p.role, u.email_confirmed_at into v_target, v_role, v_confirmed
    from auth.users u join public.profiles p on p.id = u.id
   where lower(u.email) = lower(trim(p_email));
  if not found then return json_build_object('status','not_found'); end if;
  if v_confirmed is null then
    raise exception 'that account has not confirmed its email address yet';
  end if;
  if v_role='super_admin' then raise exception 'this account is already a super admin'; end if;
  perform public.hyn_admin_set_role(v_target,'admin');
  return json_build_object('status','ok','user_id',v_target);
end $$;

notify pgrst, 'reload schema';
commit;
