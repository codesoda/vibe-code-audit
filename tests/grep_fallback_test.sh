#!/usr/bin/env bash
set -euo pipefail

# Grep-fallback regression test for build_read_plan.sh (Spec 16 / Spec 31)
# Verifies that when rg is not available, the grep -R fallback path:
#   1. Uses --exclude-dir for all 7 canonical directories
#   2. Produces correct read_plan.tsv / read_plan.md artifacts
#   3. Excludes files from excluded directories and includes files from valid paths

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/vibe-code-audit/scripts/build_read_plan.sh"

PASS=0
FAIL=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------
# Setup: temp dirs, PATH hiding, cleanup trap
# ---------------------------------------------------------------------------

ORIG_PATH="$PATH"
TMPROOT=""

cleanup() {
  PATH="$ORIG_PATH"
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT INT TERM

TMPROOT="$(mktemp -d)"
MOCK_REPO="$TMPROOT/repo"
OUTPUT_DIR="$TMPROOT/output"
mkdir -p "$MOCK_REPO" "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Static checks on build_read_plan.sh
# ---------------------------------------------------------------------------

# 1. grep -R call includes all 7 --exclude-dir flags via EXCLUDE_DIRS iteration
EXPECTED_DIRS=".git node_modules target dist build .next coverage"
GREP_LINE="$(grep -n 'grep -R' "$SCRIPT" | head -n1)"
if [ -n "$GREP_LINE" ]; then
  pass "grep -R call found in build_read_plan.sh"
else
  fail "grep -R call not found in build_read_plan.sh"
fi

# 2. Verify exclude_args array is built from EXCLUDE_DIRS
if grep -q 'grep_exclude_args+=(--exclude-dir' "$SCRIPT"; then
  pass "grep_exclude_args built with --exclude-dir from EXCLUDE_DIRS loop"
else
  fail "grep_exclude_args not built from EXCLUDE_DIRS loop"
fi

# 3. Verify the grep call uses the array expansion
if grep -q '"${grep_exclude_args\[@\]}"' "$SCRIPT"; then
  pass "grep -R uses grep_exclude_args array expansion"
else
  fail "grep -R does not use grep_exclude_args array expansion"
fi

# 4. Verify --exclude-dir args appear before PATTERN in grep call
GREP_CMD_LINE=$(grep 'grep -R -n -E' "$SCRIPT")
if printf '%s' "$GREP_CMD_LINE" | grep -q 'grep_exclude_args.*\$PATTERN'; then
  pass "grep --exclude-dir args positioned before PATTERN"
else
  fail "grep --exclude-dir args NOT positioned before PATTERN"
fi

# ---------------------------------------------------------------------------
# Fixture: mock repo with excluded + included directories
# ---------------------------------------------------------------------------

# Create files that match the read-plan PATTERN inside excluded directories
for dir in $EXPECTED_DIRS; do
  mkdir -p "$MOCK_REPO/$dir/sub"
  printf 'function validateSchema() { return true; }\n' > "$MOCK_REPO/$dir/sub/match.js"
done

# Create a file matching the pattern in an included directory
mkdir -p "$MOCK_REPO/src/auth"
printf 'function validatePermission(user) { return authorize(user); }\n' > "$MOCK_REPO/src/auth/check.js"

# Also add a second included match to verify multi-file output
mkdir -p "$MOCK_REPO/lib"
printf 'const timeout = config.retryBackoff || 3000;\n' > "$MOCK_REPO/lib/retry.js"

# ---------------------------------------------------------------------------
# PATH manipulation: hide rg
# ---------------------------------------------------------------------------

# Build a filtered PATH that excludes any directory containing rg
FILTERED_PATH=""
IFS=':'
for segment in $ORIG_PATH; do
  if [ -x "$segment/rg" ]; then
    continue
  fi
  if [ -n "$FILTERED_PATH" ]; then
    FILTERED_PATH="$FILTERED_PATH:$segment"
  else
    FILTERED_PATH="$segment"
  fi
done
unset IFS

export PATH="$FILTERED_PATH"

# Verify rg is truly hidden
if command -v rg >/dev/null 2>&1; then
  fail "rg still visible in PATH after filtering — fallback test unreliable"
  # Restore and skip dynamic tests
  PATH="$ORIG_PATH"
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  exit "$FAIL"
else
  pass "rg hidden from PATH — grep fallback will be exercised"
fi

# ---------------------------------------------------------------------------
# Execute build_read_plan.sh in fallback mode
# ---------------------------------------------------------------------------

SCRIPT_EXIT=0
bash "$SCRIPT" --repo "$MOCK_REPO" --output "$OUTPUT_DIR/audit_index.tmp" --mode fast 2>"$TMPROOT/stderr.log" || SCRIPT_EXIT=$?

if [ "$SCRIPT_EXIT" -eq 0 ]; then
  pass "build_read_plan.sh exited 0 in grep fallback mode"
else
  fail "build_read_plan.sh exited $SCRIPT_EXIT in grep fallback mode"
fi

# ---------------------------------------------------------------------------
# Assert artifacts exist
# ---------------------------------------------------------------------------

DERIVED="$OUTPUT_DIR/audit_index.tmp/derived"
READ_PLAN_TSV="$DERIVED/read_plan.tsv"
READ_PLAN_MD="$DERIVED/read_plan.md"

if [ -f "$READ_PLAN_TSV" ]; then
  pass "read_plan.tsv created"
else
  fail "read_plan.tsv not created"
fi

if [ -f "$READ_PLAN_MD" ]; then
  pass "read_plan.md created"
else
  fail "read_plan.md not created"
fi

# ---------------------------------------------------------------------------
# Assert included matches are present in read_plan.tsv
# ---------------------------------------------------------------------------

if [ -f "$READ_PLAN_TSV" ] && [ -s "$READ_PLAN_TSV" ]; then
  pass "read_plan.tsv is non-empty"
else
  fail "read_plan.tsv is empty — expected at least one included match"
fi

if [ -f "$READ_PLAN_TSV" ] && grep -q 'src/auth/check.js' "$READ_PLAN_TSV"; then
  pass "included file src/auth/check.js appears in read_plan.tsv"
else
  fail "included file src/auth/check.js missing from read_plan.tsv"
fi

# ---------------------------------------------------------------------------
# Assert excluded directories do NOT appear in read_plan.tsv
# ---------------------------------------------------------------------------

EXCLUSION_CLEAN=true
for dir in $EXPECTED_DIRS; do
  if [ -f "$READ_PLAN_TSV" ] && grep -q "^${dir}/" "$READ_PLAN_TSV"; then
    fail "excluded directory '$dir' found in read_plan.tsv"
    EXCLUSION_CLEAN=false
  fi
done

if [ "$EXCLUSION_CLEAN" = true ]; then
  pass "no excluded directories appear in read_plan.tsv"
fi

# ---------------------------------------------------------------------------
# Assert read_plan.md contains expected structure
# ---------------------------------------------------------------------------

if [ -f "$READ_PLAN_MD" ] && grep -q '# Read Plan' "$READ_PLAN_MD"; then
  pass "read_plan.md contains '# Read Plan' header"
else
  fail "read_plan.md missing '# Read Plan' header"
fi

if [ -f "$READ_PLAN_MD" ] && grep -q '## Slices' "$READ_PLAN_MD"; then
  pass "read_plan.md contains '## Slices' section"
else
  fail "read_plan.md missing '## Slices' section"
fi

# ---------------------------------------------------------------------------
# Restore PATH (also handled by trap, but explicit for safety)
# ---------------------------------------------------------------------------

PATH="$ORIG_PATH"

if command -v rg >/dev/null 2>&1; then
  pass "PATH restored — rg visible again"
else
  # rg may not be installed at all; that's fine
  pass "PATH restored (rg may not be installed on this system)"
fi

# ---------------------------------------------------------------------------
# Cleanup check
# ---------------------------------------------------------------------------

# Temp files should not leak (raw/norm are cleaned by script)
if [ -f "$DERIVED/.read_plan_matches_raw.tsv" ]; then
  fail "temporary raw matches file leaked"
else
  pass "temporary raw matches file cleaned up"
fi

if [ -f "$DERIVED/.read_plan_matches_norm.tsv" ]; then
  fail "temporary normalized matches file leaked"
else
  pass "temporary normalized matches file cleaned up"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
