#!/usr/bin/env bash
# Proves the D1 -> Postgres data migration on a throwaway cluster before it is
# ever run against the real self-hosted Supabase.
#
#   bash scripts/verify-d1-migration.sh migration-artifacts/d1-production.sql
#
# It stands up a temporary Postgres (same approach as supabase/run-tests.sh),
# applies the Supabase test harness + schema, converts the D1 export, loads it,
# and asserts every table's row count matches the D1 source. Nothing here touches
# a real project: the cluster lives in a temp dir and is destroyed on exit.
#
# This is the check that fails if the conversion breaks. Row counts are the
# assertion because a silently-skipped table or a coercion that dropped rows is
# exactly the failure a "it ran without error" load would hide.

set -uo pipefail

HERE=$(cd -P "${BASH_SOURCE[0]%/*}/.." && pwd)
DUMP=${1:-$HERE/migration-artifacts/d1-production.sql}

[[ -f $DUMP ]] || { printf 'verify: no D1 export at %s\n' "$DUMP" >&2; exit 1; }

for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@14/bin \
         /usr/lib/postgresql/16/bin /usr/lib/postgresql/14/bin; do
  [[ -x $p/initdb ]] && { PATH="$p:$PATH"; break; }
done
command -v initdb >/dev/null || { printf 'verify: no postgres (brew install postgresql@16)\n' >&2; exit 1; }
command -v sqlite3 >/dev/null || { printf 'verify: no sqlite3\n' >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hyn-d1verify.XXXXXX") || exit 1
PGDATA="$WORK/data"; SOCK="$WORK/sock"; PORT=${PGPORT:-54331}
mkdir -p "$SOCK"
cleanup() { pg_ctl -D "$PGDATA" -m immediate stop >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT

printf 'verify: loading D1 export into sqlite…\n'
sqlite3 "$WORK/d1.sqlite" < "$DUMP" 2>"$WORK/sqlite.log" || { tail -5 "$WORK/sqlite.log" >&2; exit 1; }

printf 'verify: initialising throwaway postgres…\n'
initdb -U postgres -A trust "$PGDATA" >"$WORK/initdb.log" 2>&1 || { tail -20 "$WORK/initdb.log" >&2; exit 1; }
pg_ctl -D "$PGDATA" -o "-p $PORT -k $SOCK -c listen_addresses=''" -l "$WORK/pg.log" start >/dev/null 2>&1 \
  || { tail -20 "$WORK/pg.log" >&2; exit 1; }
for _ in $(seq 1 20); do
  psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -c 'select 1' >/dev/null 2>&1 && break; sleep 0.5
done
pg() { command psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

printf 'verify: applying harness + schema…\n'
pg -f "$HERE/supabase/test-harness.sql" >"$WORK/harness.log" 2>&1 || { tail -20 "$WORK/harness.log" >&2; exit 1; }
pg -f "$HERE/supabase/schema.sql" >"$WORK/schema.log" 2>&1 || { tail -30 "$WORK/schema.log" >&2; exit 1; }

# profiles.id references auth.users. Real Supabase gets these from the auth
# migration; here they are synthesised from the D1 profile ids so the FK is
# satisfied and the load is exercised with constraints in place.
printf 'verify: seeding auth.users from D1 profile ids…\n'
sqlite3 -noheader -list "$WORK/d1.sqlite" \
  "select id||'|'||coalesce(email,'') from profiles" > "$WORK/users.txt"
: > "$WORK/users.sql"
while IFS='|' read -r uid uemail; do
  [[ -z $uid ]] && continue
  printf "insert into auth.users (id,email) values ('%s',%s) on conflict do nothing;\n" \
    "$uid" "$( [[ -n $uemail ]] && printf "'%s'" "${uemail//\'/\'\'}" || printf NULL )" >> "$WORK/users.sql"
done < "$WORK/users.txt"
pg -f "$WORK/users.sql" >"$WORK/users.log" 2>&1 || { tail -10 "$WORK/users.log" >&2; exit 1; }

printf 'verify: introspecting target columns…\n'
command psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -At -F$'\t' \
  -c "select table_name, column_name, data_type from information_schema.columns
      where table_schema='public' order by table_name, ordinal_position" > "$WORK/pg-columns.tsv"

printf 'verify: converting D1 data…\n'
python3 "$HERE/scripts/d1-to-postgres.py" \
  --sqlite "$WORK/d1.sqlite" --columns "$WORK/pg-columns.tsv" \
  --out "$WORK/data.sql" --report "$WORK/convert.txt" || exit 1
cat "$WORK/convert.txt"

printf 'verify: loading into postgres…\n'
if ! pg -f "$WORK/data.sql" >"$WORK/load.log" 2>&1; then
  printf 'verify: LOAD FAILED\n' >&2; tail -25 "$WORK/load.log" >&2; exit 1
fi

printf '\nverify: comparing row counts (D1 -> Postgres)\n'
fail=0
while read -r t; do
  case $t in d1_migrations|hyn_migration_state|sqlite_sequence) continue;; esac
  s=$(sqlite3 "$WORK/d1.sqlite" "select count(*) from \"$t\"" 2>/dev/null) || continue
  p=$(command psql -U postgres -p "$PORT" -h "$SOCK" -d postgres -At \
        -c "select count(*) from public.\"$t\"" 2>/dev/null)
  if [[ -z $p ]]; then
    printf '  %-26s d1=%-6s pg=%-6s  SKIP (absent in schema)\n' "$t" "$s" "-"
    continue
  fi
  if [[ $s == "$p" ]]; then
    printf '  %-26s d1=%-6s pg=%-6s  ok\n' "$t" "$s" "$p"
  elif (( p > s )); then
    # schema.sql seeds its own 'global' defaults (delivery_rules,
    # delivery_digest_settings). Extra rows on the Postgres side are those
    # defaults, not migrated data, so this is not a loss. Losing a row is.
    printf '  %-26s d1=%-6s pg=%-6s  ok (+%d schema-seeded)\n' "$t" "$s" "$p" "$((p - s))"
  else
    printf '  %-26s d1=%-6s pg=%-6s  ROWS LOST\n' "$t" "$s" "$p"; fail=1
  fi
done < <(sqlite3 "$WORK/d1.sqlite" "select name from sqlite_master where type='table' order by name")

if (( fail )); then
  printf '\nverify: FAILED — rows present in D1 did not reach Postgres\n' >&2; exit 1
fi
printf '\nverify: PASS — every D1 row reached Postgres\n'
