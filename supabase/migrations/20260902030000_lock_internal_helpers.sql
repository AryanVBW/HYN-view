-- ===========================================================================
-- the internal helpers are actually unreachable, not merely revoked from PUBLIC
-- ===========================================================================
-- Every internal in this schema is followed by `revoke all on function ... from
-- public`, and on a plain PostgreSQL install that is the whole story: the only
-- grant a new function carries is the implicit one to PUBLIC. On a Supabase
-- project it is not. The project's default privileges grant EXECUTE on every new
-- function to `anon`, `authenticated` and `service_role` **by name**, and
-- revoking PUBLIC does not touch a grant made to a role. So each of these was
-- callable over /rest/v1/rpc with nothing but the public anon key.
--
-- Measured, not theorised. Against the live project:
--
--   POST /rest/v1/rpc/_hyn_audit  ->  204, and a row in admin_audit
--
-- which is an unauthenticated write into the one table whose entire value is
-- being trustworthy after the fact. `_hyn_command_node` answered
-- `_hyn_sha256` computed hashes, and `_hyn_require_admin` was reachable too.
-- The probe row is removed below.
--
-- The test harness never caught it because it was stricter than production: it
-- created anon and authenticated but not Supabase's default privileges, so
-- "revoked from PUBLIC" really was unreachable there. supabase/test-harness.sql
-- now sets those defaults, and supabase/flow-test.sql asserts this property for
-- every `_hyn_` function, so the next helper cannot reintroduce it quietly.
--
-- _hyn_portal_config_valid is deliberately left reachable: it backs a CHECK
-- constraint on public.nodes, and a check constraint is evaluated as the role
-- performing the write, so revoking it from `authenticated` would break the
-- direct `grant update (config) on nodes` path with "permission denied for
-- function". Reading it back tells a caller nothing it did not already supply.

delete from public.admin_audit where action = 'probe.anon';

do $$
declare
  v_sig text;
  v_role text;
begin
  foreach v_sig in array array[
    'public._hyn_audit(text, uuid, uuid, jsonb)',
    'public._hyn_require_admin()',
    'public._hyn_sha256(text)',
    'public._hyn_command_node(uuid, uuid)',
    'public._hyn_node_ever_connected(public.nodes)',
    'public._hyn_delete_expired_device_code(uuid)',
    'public._hyn_purge_expired_device_codes()',
    -- Trigger functions and the pairing-code generator: reachable is reachable,
    -- even where calling one outside its trigger only produces an error.
    'public._hyn_user_code()',
    'public._hyn_on_auth_user_created()',
    'public._hyn_create_email_preferences()'
  ] loop
    if to_regprocedure(v_sig) is null then continue; end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = v_role) then
        execute format('revoke all on function %s from %I', v_sig, v_role);
      end if;
    end loop;
    execute format('revoke all on function %s from public', v_sig);
  end loop;
end;
$$;
