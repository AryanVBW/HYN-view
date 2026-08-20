#!/usr/bin/env bash
# Applies supabase/schema.sql (or the full migration chain) to a throwaway
# Postgres cluster and runs the pairing + ingest flow test against it.
#
#   bash supabase/run-tests.sh
#   HYN_TEST_MIGRATIONS=1 bash supabase/run-tests.sh  # full upgrade path
#   HYN_TEST_SCHEMA_REAPPLY=1 bash supabase/run-tests.sh  # legacy reapply
#   HYN_TEST_LOCKING=1 bash supabase/run-tests.sh  # concurrent cleanup
#
# Needs a local postgres (brew install postgresql@16). Nothing here touches a
# real Supabase project: the cluster is created in a temp directory and removed
# on exit, and the test itself runs inside a transaction that is rolled back.

set -uo pipefail

HERE=$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)

# Prefer a versioned homebrew postgres, fall back to whatever is on PATH.
for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@14/bin \
         /usr/lib/postgresql/16/bin /usr/lib/postgresql/14/bin; do
  [[ -x $p/initdb ]] && { PATH="$p:$PATH"; break; }
done

command -v initdb >/dev/null || { printf 'run-tests: no postgres found (brew install postgresql@16)\n' >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hyn-pgtest.XXXXXX") || exit 1
PGDATA="$WORK/data"
SOCK="$WORK/sock"
PORT=${PGPORT:-54329}
mkdir -p "$SOCK"

cleanup() {
  pg_ctl -D "$PGDATA" -m immediate stop >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

printf 'run-tests: initialising a throwaway cluster…\n'
initdb -U postgres -A trust "$PGDATA" >"$WORK/initdb.log" 2>&1 || {
  tail -20 "$WORK/initdb.log" >&2; exit 1; }

pg_ctl -D "$PGDATA" -o "-p $PORT -k $SOCK -c listen_addresses=''" \
  -l "$WORK/pg.log" start >/dev/null 2>&1 || { tail -20 "$WORK/pg.log" >&2; exit 1; }

# pg_ctl returns before the socket is always ready on a cold cluster.
for _ in $(seq 1 20); do
  psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -c 'select 1' >/dev/null 2>&1 && break
  sleep 0.5
done

psql() { command psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

if [[ ${HYN_TEST_MIGRATIONS:-0} == 1 ]]; then
  printf 'run-tests: applying the harness and migration chain…\n'
else
  printf 'run-tests: applying the harness and schema…\n'
fi
psql -f "$HERE/test-harness.sql" >/dev/null 2>&1 || { printf 'harness failed\n' >&2; exit 1; }
if [[ ${HYN_TEST_MIGRATIONS:-0} == 1 ]]; then
  # Exercise the actual upgrade path from the original full-schema migration.
  # This mode catches patches that work in schema.sql but fail on an existing
  # project because a legacy column, constraint, grant, or row is still present.
  for migration in "$HERE"/migrations/*.sql; do
    if [[ ${migration##*/} == 20260821120000_hash_pairing_codes_and_expire.sql ]]; then
      # Simulate an in-flight pairing created by the previous production schema.
      psql -c "insert into public.device_codes (user_code, device_code_hash, hostname, os, agent_version, expires_at) values ('7ABC-DEFG', public._hyn_sha256('legacy-device-code'), 'legacy-host', 'Ubuntu', 'legacy', now() + interval '10 minutes')" >/dev/null
    fi
    if [[ ${migration##*/} == 20260821121000_remove_central_notification_credentials.sql ]]; then
      # Prove the destructive privacy migration removes real legacy rows, not
      # merely empty tables created by the old migration chain.
      psql -c "insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444', 'legacy-notify@example.com'); insert into public.notification_channels (owner, kind, target, secret) values ('44444444-4444-4444-4444-444444444444', 'resend', 'legacy-target@example.com', 'legacy-central-secret'); insert into public.notify_prefs (user_id, notify_email) values ('44444444-4444-4444-4444-444444444444', 'legacy-target@example.com')" >/dev/null
    fi
    if [[ ${migration##*/} == 20260821121500_allowlist_portal_node_config.sql ]]; then
      # Simulate config smuggled through the direct API before the allowlist.
      psql -c "insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666', 'legacy-config@example.com'); insert into public.nodes (owner, name, config) values ('66666666-6666-6666-6666-666666666666', 'legacy-config-node', '{\"alert_mem_pct\":\"81\",\"alert_disk_pct\":\"08\",\"report_at\":\"06:15\",\"webhook_url\":\"https://attacker.example/hook\",\"heartbeat_url\":\"https://attacker.example/ping\",\"cloud_url\":\"https://attacker.example\"}'::jsonb)" >/dev/null
    fi
    psql -f "$migration" 2>&1 | grep -viE 'NOTICE|does not exist, skipping' >&2
    if [[ ${migration##*/} == 20260821121000_remove_central_notification_credentials.sql ]]; then
      # The migration must remove notification state, not the account itself;
      # remove only this test fixture before the common flow assertions count
      # profiles.
      psql -c "delete from auth.users where id = '44444444-4444-4444-4444-444444444444'" >/dev/null
    fi
  done
  psql -f "$HERE/migration-upgrade-test.sql"
else
  # Policy "does not exist, skipping" notices are expected on a first apply.
  psql -f "$HERE/schema.sql" 2>&1 | grep -viE 'NOTICE|does not exist, skipping' >&2
  if [[ ${HYN_TEST_SCHEMA_REAPPLY:-0} == 1 ]]; then
    # Recreate legacy central notification stores, including an actual provider
    # secret, so a schema reapplication proves it removes old deployed state.
    psql -c "create table public.notification_channels (id uuid primary key default gen_random_uuid(), owner uuid, kind text, target text, secret text); insert into public.notification_channels (kind, target, secret) values ('resend', 'legacy-target@example.com', 'legacy-central-secret'); create table public.notify_prefs (user_id uuid primary key, notify_email text, notify_phone text, admin_id uuid, updated_at timestamptz default now()); insert into public.notify_prefs (user_id, notify_email, notify_phone) values ('55555555-5555-5555-5555-555555555555', 'legacy-target@example.com', '+910000000000')" >/dev/null
    psql -c "alter table public.nodes drop constraint if exists nodes_config_portal_keys_check; insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777', 'reapply-config@example.com'); insert into public.nodes (owner, name, config) values ('77777777-7777-7777-7777-777777777777', 'reapply-config-node', '{\"alert_mem_pct\":\"82\",\"alert_disk_pct\":\"08\",\"webhook_url\":\"https://attacker.example/hook\"}'::jsonb)" >/dev/null
    psql -f "$HERE/schema.sql" 2>&1 | grep -viE 'NOTICE|does not exist, skipping' >&2
    if [[ $(psql -Atc "select count(*) from public.nodes where owner = '77777777-7777-7777-7777-777777777777' and (config ? 'webhook_url' or config ? 'alert_disk_pct' or config->>'alert_mem_pct' <> '82')") != 0 ]]; then
      printf 'run-tests: schema reapply did not sanitise legacy node config\n' >&2
      exit 1
    fi
    psql -c "delete from auth.users where id = '77777777-7777-7777-7777-777777777777'" >/dev/null
  fi
fi

if [[ ${HYN_TEST_LOCKING:-0} == 1 ]]; then
  psql -c "insert into public.device_codes (user_code_verifier, device_code_hash, hostname, expires_at) values (extensions.crypt('LOCK-TEST', extensions.gen_salt('bf', 10)), public._hyn_sha256('locking-device'), 'locking-fixture', now() - interval '1 minute')" >/dev/null

  PGAPPNAME=hyn-lock-holder command psql -U postgres -p "$PORT" -h "$SOCK" \
    -d postgres -v ON_ERROR_STOP=1 -q \
    -c "begin; select id from public.device_codes where device_code_hash = public._hyn_sha256('locking-device') for update; select pg_sleep(4); rollback" \
    >"$WORK/lock-holder.log" 2>&1 &
  lock_holder_pid=$!

  lock_ready=0
  for _ in $(seq 1 30); do
    if [[ $(psql -Atc "select count(*) from pg_stat_activity where application_name = 'hyn-lock-holder' and wait_event = 'PgSleep'") == 1 ]]; then
      lock_ready=1
      break
    fi
    sleep 0.1
  done
  if ((lock_ready == 0)); then
    wait "$lock_holder_pid" || true
    printf 'run-tests: locking fixture did not acquire its row lock\n' >&2
    exit 1
  fi

  # A purge that waits on the locked expired row fails this timeout. SKIP LOCKED
  # must let an unrelated pairing request complete while the fixture is held.
  if ! psql -c "set statement_timeout = '1500ms'; select public.hyn_device_start('nonblocking-cleanup', 'Ubuntu', 'test')" >/dev/null; then
    wait "$lock_holder_pid" || true
    printf 'run-tests: pairing cleanup blocked on another expired row\n' >&2
    exit 1
  fi
  wait "$lock_holder_pid" || { printf 'run-tests: locking fixture failed\n' >&2; exit 1; }

  psql -c "select public.hyn_device_start('post-lock-cleanup', 'Ubuntu', 'test')" >/dev/null
  if [[ $(psql -Atc "select count(*) from public.device_codes where device_code_hash = public._hyn_sha256('locking-device')") != 0 ]]; then
    printf 'run-tests: skipped expired row was not removed on the next pairing RPC\n' >&2
    exit 1
  fi
  printf 'PASS  concurrent expiry cleanup skips locked rows without deadlocking\n'
fi

printf 'run-tests: running the flow test…\n\n'
out=$(psql -f "$HERE/flow-test.sql" 2>&1)
rc=$?
printf '%s\n' "$out" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  //'

if ((rc != 0)); then
  printf '\nrun-tests: FAILED\n' >&2
  exit 1
fi

# A silent pass would be indistinguishable from a test file that ran nothing.
passes=$(printf '%s\n' "$out" | grep -c 'PASS ')
printf '\nrun-tests: %d checks passed\n' "$passes"
((passes > 0)) || { printf 'run-tests: no assertions ran\n' >&2; exit 1; }
exit 0
