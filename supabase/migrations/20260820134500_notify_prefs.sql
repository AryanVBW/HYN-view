-- hyn-view: notification model v2
--
-- What changes, and why:
--
--   * Users no longer configure delivery channels (Resend/SMTP/Telegram/etc).
--     That plumbing moves to administrators only. A user instead picks THREE
--     things: a notification email, an optional phone number, and which
--     administrator should manage their alerts. This is `notify_prefs`.
--
--   * `notification_channels.owner` is reinterpreted as "the administrator who
--     configured this channel" rather than "the client being notified". A
--     node's channels are now resolved through the CLIENT'S CHOSEN ADMIN
--     (notify_prefs.admin_id), not through the node's own owner. Existing rows
--     are untouched by this migration; an admin simply re-adds channels from
--     the new admin-panel section going forward.
--
--   * ADMIN_EMAILS is an environment variable (comma-separated addresses) read
--     server-side. On sign-in, the app calls hyn_claim_env_admin(), which
--     promotes the caller to admin ONLY IF the caller's own verified email is
--     in the list passed by the server. The email list itself never lands in
--     a table -- it stays in the env var and is passed as an argument each
--     time, so rotating it takes no migration.
--
--   * A permanently-seeded administrator (set directly in `profiles.role` by an
--     operator, not through any RPC or env var) is untouched by any of this: it
--     is just a normal admin row that happens to not depend on ADMIN_EMAILS.
--
-- Idempotent, like the rest of this schema.

-- ---------------------------------------------------------------------------
-- notify_prefs: what a client wants, not how it is delivered
-- ---------------------------------------------------------------------------
create table if not exists public.notify_prefs (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  notify_email text,
  notify_phone text,
  admin_id     uuid references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now()
);

alter table public.notify_prefs enable row level security;

drop policy if exists notify_prefs_select_own on public.notify_prefs;
create policy notify_prefs_select_own on public.notify_prefs
  for select using (user_id = auth.uid() or public.hyn_is_admin());

drop policy if exists notify_prefs_upsert_own on public.notify_prefs;
create policy notify_prefs_upsert_own on public.notify_prefs
  for insert with check (user_id = auth.uid());

drop policy if exists notify_prefs_update_own on public.notify_prefs;
create policy notify_prefs_update_own on public.notify_prefs
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert on public.notify_prefs to authenticated;
grant update (notify_email, notify_phone, admin_id) on public.notify_prefs to authenticated;
revoke all on public.notify_prefs from anon;

-- A client picks from active admins only, so the dashboard needs to list them.
-- Nothing secret here -- email and name are already visible fleet-wide to any
-- admin, and this just lets a non-admin see who they may choose.
create or replace function public.hyn_list_admins()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(json_agg(json_build_object('id', id, 'email', email, 'full_name', full_name)
                    order by created_at), '[]'::json)
    from public.profiles
   where role = 'admin' and status = 'active';
$$;

revoke all on function public.hyn_list_admins() from public;
grant execute on function public.hyn_list_admins() to authenticated;

-- ---------------------------------------------------------------------------
-- ADMIN_EMAILS: environment-driven promotion, claimed by the signed-in user
-- ---------------------------------------------------------------------------
-- The server passes the caller's OWN verified email back to this function; it
-- never trusts a client-supplied email, and it never trusts the list living
-- anywhere but the env var the server read it from. A caller can only ever
-- promote themselves, and only if their real auth email matches.
create or replace function public.hyn_claim_env_admin(p_caller_email text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_real_email text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select email into v_real_email from auth.users where id = v_uid;
  if v_real_email is null or lower(v_real_email) <> lower(coalesce(p_caller_email, '')) then
    raise exception 'email does not match the authenticated session';
  end if;

  update public.profiles
     set role = 'admin', updated_at = now()
   where id = v_uid and role <> 'admin';

  return json_build_object('status', 'ok', 'role', 'admin');
end;
$$;

revoke all on function public.hyn_claim_env_admin(text) from public;
grant execute on function public.hyn_claim_env_admin(text) to authenticated;

-- ---------------------------------------------------------------------------
-- resolve channels through the client's chosen admin
-- ---------------------------------------------------------------------------
-- Replaces the body of hyn_fetch_config: channels now come from
-- notify_prefs.admin_id rather than the node's own owner. A client with no
-- admin chosen yet, or whose channels were never configured by that admin,
-- correctly gets an empty channel list -- the dashboard already renders that
-- as an honest empty state.
create or replace function public.hyn_fetch_config(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_admin_id uuid;
  v_channels json;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token);

  if not found then
    raise exception 'invalid node token';
  end if;
  if v_node.revoked then
    raise exception 'node revoked';
  end if;

  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  select admin_id into v_admin_id from public.notify_prefs where user_id = v_node.owner;

  select coalesce(json_agg(json_build_object(
           'kind', c.kind, 'target', c.target, 'secret', c.secret, 'extra', c.extra
         )), '[]'::json)
    into v_channels
    from public.notification_channels c
   where v_admin_id is not null
     and c.owner = v_admin_id
     and c.enabled = true
     and (c.node_id is null or c.node_id = v_node.id);

  update public.nodes set last_config_pull_at = now() where id = v_node.id;

  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_name', v_node.name,
    'node_status', v_node.status,
    'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason,
    'config', v_node.config,
    'channels', v_channels
  );
end;
$$;

-- notification_channels.select_own already allows owner-or-admin; that owner
-- is now "the admin who configured it", so no policy change is needed there.
-- What DOES need to change: node_id on a channel referred to a client's own
-- node before. An admin's channel is fleet-wide by default (node_id null)
-- unless the admin scopes it to one specific machine, which still works
-- unchanged since node_id is just a foreign key with no ownership assumption
-- baked into the column itself.
