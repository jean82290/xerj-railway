#!/bin/sh
# Smoke test for a deployed XERJ: health, auth, index, search, agent memory.
# Cleans up after itself (deletes the test index and memory namespace).
#
# Usage:
#   sh scripts/smoke-test.sh https://your-service.up.railway.app <XERJ_ADMIN_KEY>
set -eu

URL="${1:?usage: smoke-test.sh <url> <admin-key>}"
KEY="${2:?usage: smoke-test.sh <url> <admin-key>}"
URL="${URL%/}"
IDX="smoke-test-$$"
NS="smoke-test-$$"
fails=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (expected $2, got $3)"; fails=$((fails + 1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
api() { curl -s -H "Authorization: ApiKey $KEY" -H 'Content-Type: application/json' "$@"; }

echo "Testing $URL"
check "health check answers without a key" 200 "$(code "$URL/health/ready")"
check "API refuses a request with no key"  401 "$(code "$URL/")"
check "API accepts the admin key"          200 "$(code -H "Authorization: ApiKey $KEY" "$URL/")"

check "create an index" 200 "$(code -X PUT -H "Authorization: ApiKey $KEY" -H 'Content-Type: application/json' \
  "$URL/$IDX" -d '{"mappings":{"properties":{"title":{"type":"text"},"body":{"type":"semantic_text"}}}}')"

printf '%s\n' \
  "{\"index\":{\"_index\":\"$IDX\",\"_id\":\"1\"}}" \
  '{"title":"Deploy on Railway","body":"Deploy apps from GitHub with one click"}' \
  "{\"index\":{\"_index\":\"$IDX\",\"_id\":\"2\"}}" \
  '{"title":"Rotate keys","body":"How to rotate the admin API key safely"}' |
  curl -s -o /dev/null -H "Authorization: ApiKey $KEY" -H 'Content-Type: application/x-ndjson' \
    -X POST "$URL/_bulk?refresh=true" --data-binary @-

hits=$(api -X POST "$URL/$IDX/_search" -d '{"query":{"match":{"title":"railway"}},"_source":false}' |
  sed -n 's/.*"total":{"value":\([0-9]*\).*/\1/p')
check "full-text search finds the document" 1 "$hits"

top=$(api -X POST "$URL/$IDX/_search" -d '{"query":{"semantic":{"field":"body","query":"change the api key","k":1}},"_source":false}' |
  sed -n 's/.*"hits":\[{"_index":"[^"]*","_id":"\([^"]*\)".*/\1/p')
check "semantic search ranks the right document first" 2 "$top"

check "store an agent memory" 201 "$(code -X POST -H "Authorization: ApiKey $KEY" -H 'Content-Type: application/json' \
  "$URL/_memory/$NS" -d '{"text":"the user prefers dark mode"}')"
recalled=$(api -X POST "$URL/_memory/$NS/_recall" -d '{"query":"which UI theme?","semantic":true,"k":1}' |
  grep -c 'dark mode' || true)
check "recall the agent memory" 1 "$recalled"

api -X DELETE "$URL/_memory/$NS" >/dev/null || true
api -X DELETE "$URL/$IDX" >/dev/null || true

if [ "$fails" -eq 0 ]; then echo "All checks passed."; else echo "$fails check(s) failed."; exit 1; fi
