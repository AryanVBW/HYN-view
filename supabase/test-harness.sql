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
