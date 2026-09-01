-- Test harness: recreates just enough of Supabase's environment to run
-- supabase/schema.sql unmodified against a plain Postgres, so the pairing and
-- ingest logic can be exercised for real instead of reviewed by eye.
--
-- Not shipped to production; Supabase provides all of this itself.

create schema if not exists extensions;
create schema if not exists auth;

do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;

grant usage on schema public, extensions to anon, authenticated;

-- Supabase's own default privileges, which are the difference between "revoked
-- from PUBLIC" and actually unreachable. A project grants EXECUTE on every new
-- function -- and DML on every new table -- to anon and authenticated *by name*,
-- and `revoke ... from public` does not touch a grant made to a role. Without
-- these three lines the harness was strictly more locked down than production, so
-- an internal helper that was callable with the public anon key looked unreachable
-- in every test. That is how _hyn_audit ended up accepting anonymous writes into
-- the audit trail with the schema's `revoke all ... from public` sitting right
-- under it. schema.sql revokes each internal from these roles by name; this is
-- what makes the test suite able to tell whether it worked.
alter default privileges in schema public grant execute on functions to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique
);

-- Supabase derives auth.uid() from the request JWT. Here it comes from a session
-- GUC so a test can act as a given user, or as nobody.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('test.uid', true), '')::uuid;
$$;
