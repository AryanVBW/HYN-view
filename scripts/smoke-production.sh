#!/usr/bin/env bash
set -euo pipefail
base="${1:?Usage: smoke-production.sh https://portal.example.com}"
base="${base%/}"
for attempt in {1..12}; do
  home=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "$base/" || true)
  protected=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "$base/api/relayers" || true)
  deliveries=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "$base/admin/deliveries" || true)
  if [[ "$home" == 200 && "$protected" == 401 && ( "$deliveries" == 307 || "$deliveries" == 303 ) ]]; then
    echo 'Production smoke checks passed: homepage 200, protected relayer API 401, delivery dashboard requires sign-in.'
    exit 0
  fi
  echo "Attempt $attempt: homepage=$home protected_api=$protected deliveries=$deliveries"
  sleep 5
done
echo 'Production smoke checks failed.' >&2
exit 1
