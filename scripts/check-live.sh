#!/usr/bin/env bash
# Checks the live site from the outside: DNS, TLS, redirects, 404s, security headers,
# and that the served CSP and SRI hashes match what the page actually loads.
# Usage: ./scripts/check-live.sh [host]   (default sushantnagil.com; www checks run only for it)
set -uo pipefail

SITE="${1:-sushantnagil.com}"
APEX="sushantnagil.com"
hosts="$SITE"; [ "$SITE" = "$APEX" ] && hosts="$SITE www.$SITE"
pass=0 fail=0
ok()  { echo "PASS  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL  $*"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== DNS"
for h in $hosts; do
  echo "  $h A: $(dig +short A "$h" @1.1.1.1 | tr '\n' ' ') AAAA: $(dig +short AAAA "$h" @1.1.1.1 | tr '\n' ' ')"
done

echo "== TLS"
cert=$(echo | openssl s_client -connect "$SITE:443" -servername "$SITE" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
echo "$cert" | sed 's/^/  /'
check "certificate is valid for $SITE" 'curl -s -o /dev/null -m 20 "https://$SITE/"'
check "TLS 1.1 is refused" '! curl -s -o /dev/null -m 20 --tlsv1.1 --tls-max 1.1 "https://$SITE/" 2>/dev/null'

echo "== responses"
code() { curl -s -o /dev/null -m 20 -w '%{http_code}' "$1"; }
loc()  { curl -s -o /dev/null -m 20 -w '%{redirect_url}' "$1"; }
check "https://$SITE/ returns 200" '[ "$(code "https://$SITE/")" = 200 ]'
check "http:// redirects to https://" '[ "$(loc "http://$SITE/")" = "https://$SITE/" ]'
if [ "$SITE" = "$APEX" ]; then
  check "www redirects to the bare domain, keeping path and query" '[ "$(loc "https://www.$SITE/a/b?x=1")" = "https://$SITE/a/b?x=1" ]'
  check "http://www redirects to https" '[[ "$(loc "http://www.$SITE/")" == https://* ]]'
fi
check "missing page returns 404" '[ "$(code "https://$SITE/no-such-page")" = 404 ]'
check "404 page is the custom one" 'curl -s -m 20 "https://$SITE/no-such-page" | grep -q "This page doesn"'
check "_headers is not served as a file" '[ "$(code "https://$SITE/_headers")" = 404 ]'
for f in favicon.svg robots.txt sitemap.xml; do check "/$f returns 200" '[ "$(code "https://$SITE/$f")" = 200 ]'; done

echo "== security headers"
H=$(curl -sI -m 20 "https://$SITE/" | tr -d '\r')
for name in content-security-policy strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy cross-origin-opener-policy; do
  check "header $name" 'grep -qi "^$name:" <<<"$H"'
done
H404=$(curl -sI -m 20 "https://$SITE/no-such-page" | tr -d '\r')
check "404 page also has the CSP" 'grep -qi "^content-security-policy:" <<<"$H404"'

echo "== CSP and SRI match what is served"
tmp=$(mktemp -d)
curl -s -m 20 "https://$SITE/" -o "$tmp/index.html"
grep -i '^content-security-policy:' <<<"$H" > "$tmp/csp"
python3 - "$tmp" <<'EOF'
import base64, hashlib, re, sys, urllib.request
d = sys.argv[1]
html = open(f"{d}/index.html", encoding="utf-8").read()
csp = open(f"{d}/csp").read()
bad = 0
for block in re.findall(r"<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)</script>", html):
    h = "sha256-" + base64.b64encode(hashlib.sha256(block.encode()).digest()).decode()
    good = f"'{h}'" in csp
    bad += not good
    print(("PASS" if good else "FAIL") + "  inline script hash is in the CSP")
for src, want in re.findall(r'<script src="([^"]+)" integrity="([^"]+)"', html):
    body = urllib.request.urlopen(src, timeout=30).read()
    got = "sha384-" + base64.b64encode(hashlib.sha384(body).digest()).decode()
    bad += got != want
    print(("PASS" if got == want else "FAIL") + "  SRI " + src.rsplit("/", 1)[-1])
open(f"{d}/py_fail", "w").write(str(bad))
EOF
py_fail=$(cat "$tmp/py_fail"); rm -rf "$tmp"

echo
echo "$pass shell checks passed, $fail failed; $py_fail hash mismatches"
[ "$fail" = 0 ] && [ "$py_fail" = 0 ]
