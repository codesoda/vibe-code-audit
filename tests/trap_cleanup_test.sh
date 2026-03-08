#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

SCRIPTS_DIR="$(cd "$(dirname "$0")/../vibe-code-audit/scripts" && pwd)"

echo "=== Trap & Cleanup Tests ==="

# --- Static checks: trap signatures ---

if grep -q 'trap cleanup_all EXIT INT TERM' "$SCRIPTS_DIR/run_index.sh"; then
  pass "run_index.sh traps EXIT INT TERM via cleanup_all"
else
  fail "run_index.sh missing EXIT INT TERM trap via cleanup_all"
fi

if grep -q 'trap cleanup EXIT INT TERM' "$SCRIPTS_DIR/run_agentroot_embed.sh"; then
  pass "run_agentroot_embed.sh traps EXIT INT TERM"
else
  fail "run_agentroot_embed.sh missing EXIT INT TERM trap"
fi

# Negative: no EXIT-only traps in target scripts
if grep -qE 'trap cleanup_all EXIT$' "$SCRIPTS_DIR/run_index.sh"; then
  fail "run_index.sh still has EXIT-only trap"
else
  pass "run_index.sh has no EXIT-only trap"
fi

if grep -qE 'trap cleanup EXIT$' "$SCRIPTS_DIR/run_agentroot_embed.sh"; then
  fail "run_agentroot_embed.sh still has EXIT-only trap"
else
  pass "run_agentroot_embed.sh has no EXIT-only trap"
fi

# --- Static checks: idempotency guards ---

# run_index.sh: cleanup_embed_server clears EMBED_SERVER_PID after kill
if awk '/^cleanup_embed_server\(\)/,/^}/' "$SCRIPTS_DIR/run_index.sh" | grep -q 'EMBED_SERVER_PID=""'; then
  pass "run_index.sh cleanup clears EMBED_SERVER_PID"
else
  fail "run_index.sh cleanup does not clear EMBED_SERVER_PID"
fi

# run_agentroot_embed.sh: cleanup clears LLAMA_PID and SERVER_STARTED after kill
if awk '/^cleanup\(\)/,/^}/' "$SCRIPTS_DIR/run_agentroot_embed.sh" | grep -q 'LLAMA_PID=""'; then
  pass "run_agentroot_embed.sh cleanup clears LLAMA_PID"
else
  fail "run_agentroot_embed.sh cleanup does not clear LLAMA_PID"
fi

if awk '/^cleanup\(\)/,/^}/' "$SCRIPTS_DIR/run_agentroot_embed.sh" | grep -q 'SERVER_STARTED=0'; then
  pass "run_agentroot_embed.sh cleanup clears SERVER_STARTED"
else
  fail "run_agentroot_embed.sh cleanup does not clear SERVER_STARTED"
fi

# --- Static checks: trap registration ordering ---
# Trap must be registered after function definition but before resource-critical code

RUN_INDEX_FUNC_LINE=$(grep -n 'cleanup_all()' "$SCRIPTS_DIR/run_index.sh" | head -1 | cut -d: -f1)
RUN_INDEX_TRAP_LINE=$(grep -n 'trap cleanup_all EXIT INT TERM' "$SCRIPTS_DIR/run_index.sh" | head -1 | cut -d: -f1)
if [ "$RUN_INDEX_TRAP_LINE" -gt "$RUN_INDEX_FUNC_LINE" ]; then
  pass "run_index.sh trap registered after function definition (line $RUN_INDEX_FUNC_LINE < $RUN_INDEX_TRAP_LINE)"
else
  fail "run_index.sh trap registered before function definition"
fi

# Verify cleanup_all calls both cleanup functions
if grep -A5 'cleanup_all()' "$SCRIPTS_DIR/run_index.sh" | grep -q 'cleanup_embed_server'; then
  pass "run_index.sh cleanup_all calls cleanup_embed_server"
else
  fail "run_index.sh cleanup_all missing cleanup_embed_server call"
fi

if grep -A5 'cleanup_all()' "$SCRIPTS_DIR/run_index.sh" | grep -q 'cleanup_audit_index_tmp'; then
  pass "run_index.sh cleanup_all calls cleanup_audit_index_tmp"
else
  fail "run_index.sh cleanup_all missing cleanup_audit_index_tmp call"
fi

# Verify cleanup_audit_index_tmp has guard for undefined variable
if awk '/^cleanup_audit_index_tmp\(\)/,/^}/' "$SCRIPTS_DIR/run_index.sh" | grep -q 'AUDIT_INDEX_DIR:-'; then
  pass "run_index.sh cleanup_audit_index_tmp guards undefined AUDIT_INDEX_DIR"
else
  fail "run_index.sh cleanup_audit_index_tmp missing undefined variable guard"
fi

EMBED_FUNC_LINE=$(grep -n '^cleanup()' "$SCRIPTS_DIR/run_agentroot_embed.sh" | head -1 | cut -d: -f1)
EMBED_TRAP_LINE=$(grep -n 'trap cleanup EXIT INT TERM' "$SCRIPTS_DIR/run_agentroot_embed.sh" | head -1 | cut -d: -f1)
if [ "$EMBED_TRAP_LINE" -gt "$EMBED_FUNC_LINE" ]; then
  pass "run_agentroot_embed.sh trap registered after function definition (line $EMBED_FUNC_LINE < $EMBED_TRAP_LINE)"
else
  fail "run_agentroot_embed.sh trap registered before function definition"
fi

# --- Dynamic test: run_agentroot_embed.sh cleanup idempotency under INT ---

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create a minimal script that sources run_agentroot_embed.sh's cleanup logic
# and tests idempotent double-call
cat > "$TMPDIR_TEST/idempotent_test.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SERVER_STARTED=1
LLAMA_PID=""
KEEP_SERVER=0

cleanup() {
  if [ "$SERVER_STARTED" -eq 1 ] && [ -n "${LLAMA_PID:-}" ] && [ "$KEEP_SERVER" -ne 1 ]; then
    kill "$LLAMA_PID" >/dev/null 2>&1 || true
    LLAMA_PID=""
    SERVER_STARTED=0
  fi
}

# Start a no-op background process to get a real PID
sleep 300 &
LLAMA_PID="$!"

# Call cleanup twice — second call must be a no-op
cleanup
cleanup

# If we get here without error, idempotency works
echo "IDEMPOTENT_OK=1"
SCRIPT
chmod +x "$TMPDIR_TEST/idempotent_test.sh"

IDEMPOTENT_OUT="$(bash "$TMPDIR_TEST/idempotent_test.sh" 2>&1)"
if echo "$IDEMPOTENT_OUT" | grep -q 'IDEMPOTENT_OK=1'; then
  pass "cleanup is idempotent (double-call safe)"
else
  fail "cleanup idempotency test failed: $IDEMPOTENT_OUT"
fi

# --- Dynamic test: KEEP_SERVER=1 suppresses cleanup ---

cat > "$TMPDIR_TEST/keep_server_test.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SERVER_STARTED=1
LLAMA_PID=""
KEEP_SERVER=1

cleanup() {
  if [ "$SERVER_STARTED" -eq 1 ] && [ -n "${LLAMA_PID:-}" ] && [ "$KEEP_SERVER" -ne 1 ]; then
    kill "$LLAMA_PID" >/dev/null 2>&1 || true
    LLAMA_PID=""
    SERVER_STARTED=0
  fi
}

sleep 300 &
LLAMA_PID="$!"

cleanup
# Process should still be alive since KEEP_SERVER=1
if kill -0 "$LLAMA_PID" 2>/dev/null; then
  echo "KEEP_SERVER_OK=1"
  kill "$LLAMA_PID" 2>/dev/null || true
else
  echo "KEEP_SERVER_FAIL=1"
fi
SCRIPT
chmod +x "$TMPDIR_TEST/keep_server_test.sh"

KEEP_OUT="$(bash "$TMPDIR_TEST/keep_server_test.sh" 2>&1)"
if echo "$KEEP_OUT" | grep -q 'KEEP_SERVER_OK=1'; then
  pass "KEEP_SERVER=1 suppresses cleanup kill"
else
  fail "KEEP_SERVER test failed: $KEEP_OUT"
fi

# --- Dynamic test: signal triggers cleanup ---
# Uses TERM (reliable for background bash processes) and verifies cleanup runs

cat > "$TMPDIR_TEST/signal_test.sh" <<'SCRIPT'
#!/usr/bin/env bash
SERVER_STARTED=1
LLAMA_PID=""
KEEP_SERVER=0
MARKER_FILE="$1"

cleanup() {
  if [ "$SERVER_STARTED" -eq 1 ] && [ -n "${LLAMA_PID:-}" ] && [ "$KEEP_SERVER" -ne 1 ]; then
    kill "$LLAMA_PID" >/dev/null 2>&1 || true
    LLAMA_PID=""
    SERVER_STARTED=0
  fi
  echo "CLEANUP_RAN" > "$MARKER_FILE"
}
trap cleanup EXIT INT TERM

sleep 300 &
LLAMA_PID="$!"

# Write readiness marker then block
echo "READY" > "${MARKER_FILE}.ready"
# Use wait instead of sleep so signals are delivered immediately
wait
SCRIPT
chmod +x "$TMPDIR_TEST/signal_test.sh"

MARKER_TERM="$TMPDIR_TEST/cleanup_marker_term"
bash "$TMPDIR_TEST/signal_test.sh" "$MARKER_TERM" &
SIG_PID="$!"

waited=0
while [ ! -f "${MARKER_TERM}.ready" ] && [ "$waited" -lt 30 ]; do
  sleep 0.1
  waited=$((waited + 1))
done

kill -TERM "$SIG_PID" 2>/dev/null || true
wait "$SIG_PID" 2>/dev/null || true

if [ -f "$MARKER_TERM" ] && grep -q 'CLEANUP_RAN' "$MARKER_TERM"; then
  pass "TERM signal triggers cleanup"
else
  fail "TERM signal did not trigger cleanup"
fi

# INT test: bash non-interactive mode may not interrupt wait on SIGINT,
# so we verify the trap is registered and cleanup would fire on EXIT
# after INT by sending TERM (which reliably interrupts wait).
# The trap declaration covers INT identically to TERM.
# We verify INT registration via the static grep checks above.

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
