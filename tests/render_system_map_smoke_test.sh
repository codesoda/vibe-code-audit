#!/usr/bin/env bash
set -euo pipefail

# Smoke test for render_system_map.sh (Spec 34)
# Verifies that when dot (graphviz) is unavailable:
#   1. Script exits gracefully (exit 0, no crash)
#   2. Emits SYSTEM_MAP_SKIPPED=1 and SYSTEM_MAP_REASON=graphviz_missing
#   3. No temp file leaks under controlled TMPDIR

TEST_NAME="render_system_map_smoke"
# shellcheck source=_test_lib.sh
. "$(dirname "$0")/_test_lib.sh"

SCRIPT="$ROOT_DIR/vibe-code-audit/scripts/render_system_map.sh"

# ---------------------------------------------------------------------------
# Setup: temp dirs, PATH hiding, cleanup trap
# ---------------------------------------------------------------------------

ORIG_PATH="$PATH"
setup_tmproot
FIXTURE_DIR="$TMPROOT/fixture"
TEST_TMPDIR="$TMPROOT/tmpdir"
mkdir -p "$FIXTURE_DIR" "$TEST_TMPDIR"

# Create a minimal non-empty markdown report fixture
cat > "$FIXTURE_DIR/test_report.md" <<'EOF'
# Test Audit Report

## Summary

This is a minimal test report for smoke testing.

| Metric | Value |
|--------|-------|
| Files  | 0     |
EOF

# ---------------------------------------------------------------------------
# 1. Script exists and is valid shell
# ---------------------------------------------------------------------------

if [ -f "$SCRIPT" ]; then
  pass "render_system_map.sh exists"
else
  fail "render_system_map.sh not found at $SCRIPT"
  print_results
  exit 1
fi

if bash -n "$SCRIPT" 2>/dev/null; then
  pass "render_system_map.sh passes syntax check"
else
  fail "render_system_map.sh has syntax errors"
fi

# ---------------------------------------------------------------------------
# 2. Build filtered PATH that excludes dot
# ---------------------------------------------------------------------------

build_filtered_path "dot"

# Verify dot is hidden
if ! PATH="$FILTERED_PATH" command -v dot >/dev/null 2>&1; then
  pass "dot is hidden from filtered PATH"
else
  fail "dot is still visible in filtered PATH"
fi

# Verify essential commands survive PATH filtering
if PATH="$FILTERED_PATH" command -v bash >/dev/null 2>&1; then
  pass "bash remains available in filtered PATH"
else
  fail "bash lost from filtered PATH"
fi

if PATH="$FILTERED_PATH" command -v mkdir >/dev/null 2>&1; then
  pass "mkdir remains available in filtered PATH"
else
  fail "mkdir lost from filtered PATH"
fi

# ---------------------------------------------------------------------------
# 3. Run render_system_map.sh with dot hidden
# ---------------------------------------------------------------------------

STDOUT_FILE="$TMPROOT/stdout.txt"
STDERR_FILE="$TMPROOT/stderr.txt"
SCRIPT_EXIT=0

env PATH="$FILTERED_PATH" TMPDIR="$TEST_TMPDIR" \
  bash "$SCRIPT" --report "$FIXTURE_DIR/test_report.md" \
  >"$STDOUT_FILE" 2>"$STDERR_FILE" || SCRIPT_EXIT=$?

# ---------------------------------------------------------------------------
# 4. Assert graceful exit
# ---------------------------------------------------------------------------

if [ "$SCRIPT_EXIT" -eq 0 ]; then
  pass "script exits with code 0"
else
  fail "script exited with code $SCRIPT_EXIT (expected 0)"
fi

# Check no crash diagnostics in stderr
STDERR_CONTENT=""
if [ -s "$STDERR_FILE" ]; then
  STDERR_CONTENT="$(cat "$STDERR_FILE")"
fi

assert_no_crash_diagnostics "$STDERR_CONTENT"

# ---------------------------------------------------------------------------
# 5. Assert skip contract signals
# ---------------------------------------------------------------------------

STDOUT_CONTENT=""
if [ -s "$STDOUT_FILE" ]; then
  STDOUT_CONTENT="$(cat "$STDOUT_FILE")"
fi

if echo "$STDOUT_CONTENT" | grep -qF 'SYSTEM_MAP_SKIPPED=1'; then
  pass "SYSTEM_MAP_SKIPPED=1 emitted on stdout"
else
  fail "SYSTEM_MAP_SKIPPED=1 not found in stdout"
fi

if echo "$STDOUT_CONTENT" | grep -qF 'SYSTEM_MAP_REASON=graphviz_missing'; then
  pass "SYSTEM_MAP_REASON=graphviz_missing emitted on stdout"
else
  fail "SYSTEM_MAP_REASON=graphviz_missing not found in stdout"
fi

# Verify no SYSTEM_MAP_PATH is emitted (since dot is missing)
if echo "$STDOUT_CONTENT" | grep -qF 'SYSTEM_MAP_PATH='; then
  fail "SYSTEM_MAP_PATH emitted despite dot being missing"
else
  pass "no SYSTEM_MAP_PATH emitted (correct for missing dot)"
fi

# ---------------------------------------------------------------------------
# 6. Assert no temp file leaks
# ---------------------------------------------------------------------------

LEAKED_FILES="$(find "$TEST_TMPDIR" -maxdepth 1 -name 'vca-*' 2>/dev/null || true)"
if [ -z "$LEAKED_FILES" ]; then
  pass "no vca-* temp files leaked in TMPDIR"
else
  fail "temp files leaked in TMPDIR: $LEAKED_FILES"
fi

# ---------------------------------------------------------------------------
# 7. Assert PATH restored (trap verification)
# ---------------------------------------------------------------------------

if [ "$PATH" = "$ORIG_PATH" ]; then
  pass "PATH restored to original value after test"
else
  fail "PATH was not restored (test cleanup issue)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_results
