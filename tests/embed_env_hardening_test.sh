#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

SCRIPTS_DIR="$(cd "$(dirname "$0")/../vibe-code-audit/scripts" && pwd)"
SCRIPT="$SCRIPTS_DIR/run_agentroot_embed.sh"

echo "=== Embed Env Hardening Tests ==="

# --- Static checks ---

# 1. No direct sourcing of embed.env
if grep -qE '^\s*\.\s+"?\$EMBED_ENV_FILE"?' "$SCRIPT"; then
  fail "run_agentroot_embed.sh still sources EMBED_ENV_FILE"
else
  pass "No direct sourcing of EMBED_ENV_FILE"
fi

# 2. Parser uses while-read loop
if grep -q 'while IFS.*read.*_env_key.*_env_value' "$SCRIPT"; then
  pass "Parser uses while-read loop"
else
  fail "Parser does not use while-read loop"
fi

# 3. Whitelist enforcement via case statement
if grep -q 'VIBE_CODE_AUDIT_EMBED_HOST' "$SCRIPT" && \
   grep -q 'VIBE_CODE_AUDIT_EMBED_PORT' "$SCRIPT" && \
   grep -q 'VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL' "$SCRIPT"; then
  pass "Whitelist includes HOST, PORT, DOWNLOAD_MODEL"
else
  fail "Whitelist missing expected keys"
fi

# 4. bash -n syntax check
if bash -n "$SCRIPT" 2>/dev/null; then
  pass "bash -n syntax check passes"
else
  fail "bash -n syntax check failed"
fi

# 4b. shellcheck (advisory — reports availability but does not fail suite)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$SCRIPT" >/dev/null 2>&1; then
    pass "shellcheck passes on run_agentroot_embed.sh"
  else
    fail "shellcheck found warnings in run_agentroot_embed.sh"
  fi
else
  echo "  SKIP: shellcheck not installed — install via 'brew install shellcheck' for lint coverage"
fi

# --- Dynamic test infrastructure ---

TMPDIR_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT INT TERM

# Create mock binaries
MOCK_BIN="$TMPDIR_ROOT/bin"
mkdir -p "$MOCK_BIN"

# Mock agentroot: always fails embed (triggers connection-refused path)
cat > "$MOCK_BIN/agentroot" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "embed" ]; then
  echo "Connection refused" >&2
  exit 1
fi
exit 0
STUB
chmod +x "$MOCK_BIN/agentroot"

# Mock curl: logs the URL it receives, always fails (no healthy server)
cat > "$MOCK_BIN/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    http://*) echo "$arg" >> "${MOCK_CURL_LOG:-/dev/null}" ;;
  esac
done
exit 1
STUB
chmod +x "$MOCK_BIN/curl"

# Helper: set up an isolated test home with embed.env and run the script
run_with_env() {
  local env_content="$1"
  shift
  local tag="${1:-default}"
  shift || true
  local test_home="$TMPDIR_ROOT/home_${tag}"
  mkdir -p "$test_home/.config/vibe-code-audit"
  local test_db="$test_home/test.sqlite"
  touch "$test_db"
  printf '%s\n' "$env_content" > "$test_home/.config/vibe-code-audit/embed.env"
  local curl_log="$test_home/curl_urls.log"
  HOME="$test_home" \
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOCK_CURL_LOG="$curl_log" \
    bash "$SCRIPT" --db "$test_db" --no-start-local "$@" 2>/dev/null || true
}

# Helper: get the health URL the script tried (via mock curl log)
get_health_url() {
  local tag="$1"
  local curl_log="$TMPDIR_ROOT/home_${tag}/curl_urls.log"
  if [ -f "$curl_log" ]; then
    head -1 "$curl_log"
  else
    echo "NO_CURL_CALL"
  fi
}

# --- 5. Valid HOST and PORT are applied ---
echo ""
echo "--- Dynamic: valid config values ---"
run_with_env 'VIBE_CODE_AUDIT_EMBED_HOST=10.0.0.1
VIBE_CODE_AUDIT_EMBED_PORT=9999' "hostport" >/dev/null
health_url="$(get_health_url "hostport")"
if [ "$health_url" = "http://10.0.0.1:9999/health" ]; then
  pass "HOST and PORT from embed.env are applied correctly"
else
  fail "HOST/PORT not applied: health URL was $health_url"
fi

# --- 6. Quoted values are stripped ---
echo ""
echo "--- Dynamic: quote stripping ---"
run_with_env 'VIBE_CODE_AUDIT_EMBED_HOST="10.0.0.2"
VIBE_CODE_AUDIT_EMBED_PORT='"'"'9876'"'"'' "quotes" >/dev/null
health_url="$(get_health_url "quotes")"
if [ "$health_url" = "http://10.0.0.2:9876/health" ]; then
  pass "Quote stripping works for double and single quotes"
else
  fail "Quote stripping failed: health URL was $health_url"
fi

# --- 7. Command injection via semicolon is NOT executed ---
echo ""
echo "--- Dynamic: command injection prevention ---"
PWNED="$TMPDIR_ROOT/pwned_semicolon"
run_with_env "VIBE_CODE_AUDIT_EMBED_HOST=localhost; touch $PWNED" "inject_semi" >/dev/null
if [ -f "$PWNED" ]; then
  fail "Command injection via semicolon was executed"
else
  pass "Semicolon injection not executed"
fi

# --- 8. Command substitution is NOT executed ---
PWNED2="$TMPDIR_ROOT/pwned_subst"
run_with_env "VIBE_CODE_AUDIT_EMBED_HOST=\$(touch $PWNED2)" "inject_subst" >/dev/null
if [ -f "$PWNED2" ]; then
  fail "Command substitution injection was executed"
else
  pass "Command substitution injection not executed"
fi

# --- 9. Backtick injection is NOT executed ---
PWNED3="$TMPDIR_ROOT/pwned_backtick"
run_with_env "VIBE_CODE_AUDIT_EMBED_HOST=\`touch $PWNED3\`" "inject_backtick" >/dev/null
if [ -f "$PWNED3" ]; then
  fail "Backtick injection was executed"
else
  pass "Backtick injection not executed"
fi

# --- 10. Non-whitelisted keys are ignored ---
echo ""
echo "--- Dynamic: non-whitelisted keys ---"
# If non-whitelisted keys leaked, PATH would be overwritten and agentroot wouldn't be found
# The script would die with "agentroot is not installed" instead of producing EMBED_OK output
test_home_nwl="$TMPDIR_ROOT/home_nwl"
mkdir -p "$test_home_nwl/.config/vibe-code-audit"
touch "$test_home_nwl/test.sqlite"
printf 'EVIL_KEY=drop_tables\nLD_PRELOAD=/evil.so\nVIBE_CODE_AUDIT_EMBED_HOST=5.5.5.5\n' \
  > "$test_home_nwl/.config/vibe-code-audit/embed.env"
nwl_output="$(HOME="$test_home_nwl" PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  MOCK_CURL_LOG="$test_home_nwl/curl_urls.log" \
  bash "$SCRIPT" --db "$test_home_nwl/test.sqlite" --no-start-local 2>/dev/null || true)"
if echo "$nwl_output" | grep -q 'EMBED_OK='; then
  pass "Script runs despite non-whitelisted keys in embed.env"
else
  fail "Script failed — non-whitelisted keys may have interfered"
fi
# Verify the valid key was still applied
nwl_url="$(head -1 "$test_home_nwl/curl_urls.log" 2>/dev/null || echo NONE)"
if echo "$nwl_url" | grep -q '5.5.5.5'; then
  pass "Whitelisted key (HOST=5.5.5.5) still applied alongside ignored keys"
else
  fail "Whitelisted key not applied alongside ignored keys: $nwl_url"
fi

# --- 11. Comment and blank lines are ignored ---
echo ""
echo "--- Dynamic: comment and blank line handling ---"
run_with_env '# This is a comment
VIBE_CODE_AUDIT_EMBED_HOST=1.2.3.4

# Another comment
VIBE_CODE_AUDIT_EMBED_PORT=5555' "comments" >/dev/null
health_url="$(get_health_url "comments")"
if [ "$health_url" = "http://1.2.3.4:5555/health" ]; then
  pass "Comments and blank lines are correctly skipped"
else
  fail "Comment/blank handling failed: health URL was $health_url"
fi

# --- 12. Missing embed.env does not crash ---
echo ""
echo "--- Dynamic: missing embed.env ---"
test_home_miss="$TMPDIR_ROOT/home_miss"
mkdir -p "$test_home_miss"
touch "$test_home_miss/test.sqlite"
miss_output="$(HOME="$test_home_miss" PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$SCRIPT" --db "$test_home_miss/test.sqlite" --no-start-local 2>/dev/null || true)"
if echo "$miss_output" | grep -q 'EMBED_OK='; then
  pass "Missing embed.env does not crash (defaults used)"
else
  fail "Missing embed.env caused failure"
fi

# --- 13. Last occurrence wins for duplicate keys ---
echo ""
echo "--- Dynamic: last occurrence wins ---"
run_with_env 'VIBE_CODE_AUDIT_EMBED_HOST=first
VIBE_CODE_AUDIT_EMBED_HOST=10.20.30.40' "dupes" >/dev/null
health_url="$(get_health_url "dupes")"
if echo "$health_url" | grep -q '10.20.30.40'; then
  pass "Last occurrence wins for duplicate keys"
else
  fail "Duplicate key handling: expected 10.20.30.40, got $health_url"
fi

# --- 14. CLI flags override embed.env values ---
echo ""
echo "--- Dynamic: CLI override precedence ---"
test_home_cli="$TMPDIR_ROOT/home_cli"
mkdir -p "$test_home_cli/.config/vibe-code-audit"
touch "$test_home_cli/test.sqlite"
printf 'VIBE_CODE_AUDIT_EMBED_HOST=from-file\nVIBE_CODE_AUDIT_EMBED_PORT=1111\n' \
  > "$test_home_cli/.config/vibe-code-audit/embed.env"
HOME="$test_home_cli" PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  MOCK_CURL_LOG="$test_home_cli/curl_urls.log" \
  bash "$SCRIPT" --db "$test_home_cli/test.sqlite" --no-start-local \
    --host cli-host --port 2222 2>/dev/null || true
cli_url="$(head -1 "$test_home_cli/curl_urls.log" 2>/dev/null || echo NONE)"
if [ "$cli_url" = "http://cli-host:2222/health" ]; then
  pass "CLI flags override embed.env values"
else
  fail "CLI override failed: health URL was $cli_url"
fi

# --- 14b. Pre-existing env var takes precedence over embed.env ---
echo ""
echo "--- Dynamic: environment variable precedence over embed.env ---"
test_home_prec="$TMPDIR_ROOT/home_prec"
mkdir -p "$test_home_prec/.config/vibe-code-audit"
touch "$test_home_prec/test.sqlite"
printf 'VIBE_CODE_AUDIT_EMBED_HOST=from-file\nVIBE_CODE_AUDIT_EMBED_PORT=1111\n' \
  > "$test_home_prec/.config/vibe-code-audit/embed.env"
HOME="$test_home_prec" PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  MOCK_CURL_LOG="$test_home_prec/curl_urls.log" \
  VIBE_CODE_AUDIT_EMBED_HOST=env-host \
  VIBE_CODE_AUDIT_EMBED_PORT=3333 \
  bash "$SCRIPT" --db "$test_home_prec/test.sqlite" --no-start-local 2>/dev/null || true
prec_url="$(head -1 "$test_home_prec/curl_urls.log" 2>/dev/null || echo NONE)"
if [ "$prec_url" = "http://env-host:3333/health" ]; then
  pass "Pre-existing env vars take precedence over embed.env"
else
  fail "Env precedence broken: expected http://env-host:3333/health, got $prec_url"
fi

# --- 15. Values with extra equals signs preserved ---
echo ""
echo "--- Dynamic: values with equals signs ---"
run_with_env 'VIBE_CODE_AUDIT_EMBED_HOST=host=with=equals' "eqval" >/dev/null
health_url="$(get_health_url "eqval")"
if echo "$health_url" | grep -q 'host=with=equals'; then
  pass "Values with extra equals signs are preserved"
else
  fail "Equals in value broken: health URL was $health_url"
fi

# --- 16. End-to-end output structure ---
echo ""
echo "--- Dynamic: end-to-end output structure ---"
run_with_env 'VIBE_CODE_AUDIT_EMBED_HOST=127.0.0.1
VIBE_CODE_AUDIT_EMBED_PORT=8000' "e2e" >/dev/null
e2e_output="$(HOME="$TMPDIR_ROOT/home_e2e" PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$SCRIPT" --db "$TMPDIR_ROOT/home_e2e/test.sqlite" --no-start-local 2>/dev/null || true)"
if echo "$e2e_output" | grep -q 'EMBED_OK=' && \
   echo "$e2e_output" | grep -q 'EMBED_BACKEND='; then
  pass "End-to-end output contains EMBED_OK and EMBED_BACKEND"
else
  fail "End-to-end output missing expected keys"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
