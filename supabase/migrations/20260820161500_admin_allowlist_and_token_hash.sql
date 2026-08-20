-- hyn-view: two authorisation fixes. Apply this to any project already running
-- an earlier schema.
--
-- 1. ADMIN SELF-PROMOTION (privilege escalation).
--
--    hyn_claim_env_admin() is granted to `authenticated` and previously checked
--    only that the email passed to it was the caller's own. The ADMIN_EMAILS
--    allow list lived in the Next.js server component that called it — so any
--    signed-in user could skip the app entirely, POST to
--    /rest/v1/rpc/hyn_claim_env_admin with the public anon key and their own
--    address, and be promoted to administrator: read every client's telemetry,
--    every notification channel, and the audit trail.
--
--    The list now lives in public.admin_allowlist, a table with RLS on and no
--    policies, revoked from both session roles. It is managed in the SQL editor.
--    Existing administrators are seeded into it so nobody is locked out.
--
-- 2. token_hash WAS READABLE BY BROWSER SESSIONS.
--
--    `grant select on public.nodes to authenticated` included token_hash, and the
--    portal selected `*`. It is a SHA-256 verifier rather than the token, so it
--    could not be used to write telemetry, but no page needs it. Now granted by
--    column. NOTE: after this, `select *` on nodes fails for a session — the
--    portal must select an explicit column list (web-portal ships this as
--    NODE_COLUMNS). Deploy the portal alongside this migration.

create table if not exists public.admin_allowlist (
  email    text primary key,
  note     text,
  added_at timestamptz not null default now()
);

alter table public.admin_allowlist enable row level security;
revoke all on public.admin_allowlist from anon, authenticated;

-- Keep the current administrators working. Anyone promoted by hand stays an
-- admin regardless; this is so the sign-in claim path still recognises them.
insert into public.admin_allowlist (email, note)
select lower(p.email), 'seeded from an existing administrator during migration'
  from public.profiles p
 where p.role = 'admin' and p.email is not null
on conflict (email) do nothing;

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
  if v_real_email is null then
    return json_build_object('status', 'no_email');
  end if;
  if p_caller_email is not null and p_caller_email <> ''
     and lower(v_real_email) <> lower(p_caller_email) then
    raise exception 'email does not match the authenticated session';
  end if;

  if not exists (
    select 1 from public.admin_allowlist a where lower(a.email) = lower(v_real_email)
  ) then
    return json_build_object('status', 'not_allowed');
  end if;

  update public.profiles
     set role = 'admin', updated_at = now()
   where id = v_uid and role <> 'admin';

  return json_build_object('status', 'ok', 'role', 'admin');
end;
$$;

revoke all on function public.hyn_claim_env_admin(text) from public;
grant execute on function public.hyn_claim_env_admin(text) to authenticated;

revoke select on public.nodes from authenticated;
grant select (id, owner, name, hostname, os, agent_version, is_demo, revoked,
              created_at, last_seen_at, status, paused_until, status_reason,
              config, last_config_pull_at)
  on public.nodes to authenticated;


-- 3. THE HUMAN PAIRING CODE CAME FROM random().
--
--    The device code and node token already came from gen_random_bytes;
--    _hyn_user_code did not. It is a 15-minute single-use code, and approving one
--    needs a signed-in session, so this was never the weakest link — but it is
--    the value a stranger would have to guess to bind someone else's server to
--    their own account, and there is no reason for it to come from a
--    non-cryptographic PRNG. Body copied verbatim from supabase/schema.sql.

create or replace function public._hyn_user_code()
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  n constant integer := 30;             -- length(alphabet)
  -- Largest multiple of n below 256. Bytes at or above it are discarded so the
  -- draw is uniform; taking v % n over the whole byte range would make the first
  -- 16 symbols ~7% likelier than the rest.
  limit_b constant integer := 240;
  out text := '';
  buf bytea;
  i integer := 0;
  v integer;
begin
  -- gen_random_bytes, not random(): random() is a fast non-cryptographic PRNG,
  -- and this code is the only thing standing between a pending pairing request
  -- and whoever types it in first. The device code and node token already come
  -- from here; this one was the odd exception.
  buf := extensions.gen_random_bytes(64);
  while length(out) < 9 loop
    if i >= 64 then
      buf := extensions.gen_random_bytes(64);
      i := 0;
    end if;
    v := get_byte(buf, i);
    i := i + 1;
    continue when v >= limit_b;
    out := out || substr(alphabet, 1 + (v % n), 1);
    if length(out) = 4 then
      out := out || '-';
    end if;
  end loop;
  return out;
end;
$$;
