#!/usr/bin/env bash
# Applies the zone-level security settings for sushantnagil.com. Safe to re-run.
# Needs CLOUDFLARE_API_TOKEN with Zone: Read, Zone Settings: Edit and DNS: Edit.
set -euo pipefail

DOMAIN="sushantnagil.com"
BASE="https://api.cloudflare.com/client/v4"
AUTH=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}")

ZONE_ID=$(curl -sS -m 30 "${AUTH[@]}" "${BASE}/zones?name=${DOMAIN}" | python3 -c 'import sys, json; print(json.load(sys.stdin)["result"][0]["id"])')
API="${BASE}/zones/${ZONE_ID}"

call() {
  local method=$1 path=$2 body=$3
  curl -sS -m 30 -X "$method" "${API}/${path}" "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    --data "$body" |
    python3 -c 'import sys, json; d = json.load(sys.stdin); r = d.get("result") or {}
print("OK  " if d["success"] else "FAIL", sys.argv[1], r.get("value", r.get("status", "")) if d["success"] else d["errors"])' "$path"
}

call PATCH settings/always_use_https '{"value":"on"}'    # http:// redirects to https://
call PATCH settings/min_tls_version  '{"value":"1.2"}'   # refuse TLS 1.0 and 1.1
call PATCH settings/tls_1_3          '{"value":"on"}'
call PATCH settings/ssl              '{"value":"strict"}'
call PATCH dnssec                    '{"status":"active"}' # signs DNS answers against spoofing
