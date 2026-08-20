-- Store the short human pairing credential as a slow, independently salted
-- bcrypt verifier. Expired rows are removed on the next pairing RPC.

alter table public.device_codes
  add column if not exists user_code_verifier text;

-- Preserve in-flight pairings during the upgrade. Dynamic SQL keeps this
-- migration safe to inspect/replay after the legacy plaintext column is gone.
do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'device_codes'
       and column_name = 'user_code'
  ) then
    execute $sql$
      update public.device_codes
         set user_code_verifier = extensions.crypt(
               upper(trim(user_code)), extensions.gen_salt('bf', 10)
             )
       where user_code_verifier is null
    $sql$;
  end if;
end;
$$;

alter table public.device_codes
  alter column user_code_verifier set not null;

drop index if exists public.device_codes_user_code_hash_idx;
alter table public.device_codes drop column if exists user_code_hash;

-- Dropping the legacy column also removes its unique constraint and plaintext
-- values after the salted verifiers above have been written.
alter table public.device_codes drop column if exists user_code;

create or replace function public._hyn_delete_expired_device_code(p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_node_id uuid;
  v_token_claimed boolean;
begin
  delete from public.device_codes
   where id = p_id and expires_at <= now()
   returning node_id, token_claimed into v_node_id, v_token_claimed;

  if not found then
    return false;
  end if;

  if v_node_id is not null and not v_token_claimed then
    delete from public.nodes
     where id = v_node_id
       and not exists (
         select 1 from public.device_codes where node_id = v_node_id
       );
  end if;

  return true;
end;
$$;

create or replace function public._hyn_purge_expired_device_codes()
returns bigint
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_deleted bigint := 0;
  v_id uuid;
begin
  for v_id in
    select id
      from public.device_codes
     where expires_at <= now()
     order by id
     for update skip locked
  loop
    if public._hyn_delete_expired_device_code(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

revoke all on function public._hyn_delete_expired_device_code(uuid) from public;
revoke all on function public._hyn_purge_expired_device_codes() from public;

create or replace function public.hyn_device_start(
  p_hostname text default null,
  p_os text default null,
  p_agent_version text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_device_code text;
  v_user_code text;
  v_expires timestamptz;
  v_try integer := 0;
begin
  perform public._hyn_purge_expired_device_codes();

  v_expires := now() + interval '15 minutes';
  perform pg_advisory_xact_lock(482791360);

  loop
    v_try := v_try + 1;
    v_device_code := encode(extensions.gen_random_bytes(32), 'hex');
    v_user_code := public._hyn_user_code();

    if exists (
      select 1
        from public.device_codes d
       where d.user_code_verifier = extensions.crypt(
               v_user_code, d.user_code_verifier
             )
    ) then
      if v_try >= 5 then
        raise exception 'could not allocate a pairing code, try again';
      end if;
      continue;
    end if;

    begin
      insert into public.device_codes (
        user_code_verifier, device_code_hash, hostname, os, agent_version, expires_at
      ) values (
        extensions.crypt(v_user_code, extensions.gen_salt('bf', 10)),
        public._hyn_sha256(v_device_code),
        left(coalesce(p_hostname, ''), 200),
        left(coalesce(p_os, ''), 200),
        left(coalesce(p_agent_version, ''), 50),
        v_expires
      );
      exit;
    exception when unique_violation then
      if v_try >= 5 then
        raise exception 'could not allocate a pairing code, try again';
      end if;
    end;
  end loop;

  return json_build_object(
    'user_code', v_user_code,
    'device_code', v_device_code,
    'expires_at', v_expires,
    'interval', 5
  );
end;
$$;

create or replace function public.hyn_device_lookup(p_user_code text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  return json_build_object(
    'status', 'pending',
    'hostname', v.hostname,
    'os', v.os,
    'agent_version', v.agent_version,
    'requested_at', v.created_at
  );
end;
$$;

create or replace function public.hyn_device_approve(
  p_user_code text,
  p_node_name text default null
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_node_id uuid;
  v_node_token text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v
    from public.device_codes d
   where d.user_code_verifier = extensions.crypt(
           upper(trim(p_user_code)), d.user_code_verifier
         )
   order by d.created_at desc
   limit 1;

  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is not null then
    return json_build_object('status', 'already_approved');
  end if;

  v_node_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.nodes (owner, name, hostname, os, agent_version, token_hash)
  values (
    v_uid,
    coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node'),
    v.hostname, v.os, v.agent_version,
    public._hyn_sha256(v_node_token)
  )
  returning id into v_node_id;

  update public.device_codes
     set approved_by = v_uid,
         node_id = v_node_id,
         node_token_hash = public._hyn_sha256(v_node_token)
   where id = v.id;

  return json_build_object(
    'status', 'approved',
    'node_id', v_node_id,
    'node_name', coalesce(nullif(trim(p_node_name), ''), nullif(v.hostname, ''), 'node')
  );
end;
$$;

create or replace function public.hyn_device_poll(p_device_code text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v device_codes;
  v_token text;
begin
  select * into v from public.device_codes
   where device_code_hash = public._hyn_sha256(p_device_code);

  perform public._hyn_purge_expired_device_codes();

  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    return json_build_object('status', 'expired');
  end if;

  select * into v from public.device_codes where id = v.id for update;
  if v.id is null then
    return json_build_object('status', 'not_found');
  end if;
  if v.expires_at <= now() then
    perform public._hyn_delete_expired_device_code(v.id);
    return json_build_object('status', 'expired');
  end if;
  if v.node_id is null then
    return json_build_object('status', 'pending', 'interval', 5);
  end if;
  if v.token_claimed then
    return json_build_object('status', 'claimed');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update public.nodes
     set token_hash = public._hyn_sha256(v_token)
   where id = v.node_id;
  update public.device_codes
     set token_claimed = true, node_token_hash = public._hyn_sha256(v_token)
   where id = v.id;

  return json_build_object(
    'status', 'approved',
    'node_id', v.node_id,
    'node_token', v_token,
    'node_name', (select name from public.nodes where id = v.node_id)
  );
end;
$$;
