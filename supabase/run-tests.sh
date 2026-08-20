#!/usr/bin/env bash
# Applies supabase/schema.sql to a throwaway Postgres cluster and runs the
# pairing + ingest flow test against it.
#
#   bash supabase/run-tests.sh
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

printf 'run-tests: applying the harness and schema…\n'
psql -f "$HERE/test-harness.sql" >/dev/null 2>&1 || { printf 'harness failed\n' >&2; exit 1; }
# Policy "does not exist, skipping" notices are expected on a first apply.
psql -f "$HERE/schema.sql" 2>&1 | grep -viE 'NOTICE|does not exist, skipping' >&2

# Note: supabase/migrations/ is deliberately NOT replayed here. 20260820093810_init
# is a full copy of the schema for a fresh project, so applying it on top of
# schema.sql fails on duplicate policies. schema.sql is the shape under test; a
# migration is a patch for projects that already have an older one.

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
