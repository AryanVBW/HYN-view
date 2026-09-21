-- The 2026-09-20 D1 -> self-hosted Supabase cutover (see
-- docs/selfhost-supabase-migration.md) was a config-only switch: unsetting
-- HYN_DATA_API_URL makes every one of the 23 call sites in lib/hyn-data.ts
-- fall through to its existing `supabase.rpc(...)` branch. That branch
-- assumed a matching Postgres function already existed for every RPC name
-- the client calls. It did not for this one: `hyn_upsert_email_preferences`
-- was only ever implemented as a case in the Cloudflare Worker's
-- `handlePortalMore` switch (cloudflare/src/portal-more.ts), operating on a
-- D1 table -- never as a Postgres function here. Post-cutover, every save
-- from components/account/email-preferences.tsx fails with PostgREST's
-- "Could not find the function public.hyn_upsert_email_preferences(...) in
-- the schema cache", because that function genuinely does not exist yet.
--
-- This mirrors the D1 handler's own logic: the node must exist, the caller
-- must own it or be a super admin, and the row is upserted with the same
-- column defaults the client already sends when a toggle is off.
create or replace function public.hyn_upsert_email_preferences(
  p_node_id uuid,
  p_recipient text,
  p_timezone text default 'UTC',
  p_incident_enabled boolean default false,
  p_daily_enabled boolean default false,
  p_daily_at time default '08:00',
  p_system_enabled boolean default false,
  p_system_at time default '09:00'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select owner into v_owner from public.nodes where id = p_node_id and revoked = false;
  if not found then raise exception 'no such server'; end if;
  if v_owner <> auth.uid() and not public.hyn_is_super_admin() then
    raise exception 'server access required';
  end if;
  if p_recipient is null or p_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'a valid recipient email is required';
  end if;

  insert into public.email_preferences (
    node_id, recipient, timezone, incident_enabled, daily_enabled, daily_at,
    system_enabled, system_at, updated_at
  ) values (
    p_node_id, p_recipient, coalesce(p_timezone, 'UTC'), coalesce(p_incident_enabled, false),
    coalesce(p_daily_enabled, false), coalesce(p_daily_at, '08:00'),
    coalesce(p_system_enabled, false), coalesce(p_system_at, '09:00'), now()
  )
  on conflict (node_id) do update set
    recipient = excluded.recipient,
    timezone = excluded.timezone,
    incident_enabled = excluded.incident_enabled,
    daily_enabled = excluded.daily_enabled,
    daily_at = excluded.daily_at,
    system_enabled = excluded.system_enabled,
    system_at = excluded.system_at,
    updated_at = excluded.updated_at;

  return json_build_object('status', 'ok');
end;
$$;

revoke all on function public.hyn_upsert_email_preferences(uuid, text, text, boolean, boolean, time, boolean, time) from public, anon;
grant execute on function public.hyn_upsert_email_preferences(uuid, text, text, boolean, boolean, time, boolean, time) to authenticated;
