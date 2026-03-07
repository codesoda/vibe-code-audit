#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_SH="$ROOT_DIR/vibe-code-audit/scripts/_lib.sh"

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

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label"
    printf '  expected: %s\n' "$expected" >&2
    printf '  actual:   %s\n' "$actual" >&2
  fi
}

# Source _lib.sh (requires SCRIPT_NAME)
SCRIPT_NAME="lib_unit_test"
# shellcheck source=../vibe-code-audit/scripts/_lib.sh
. "$LIB_SH"

# ---------------------------------------------------------------------------
# Test: EXCLUDE_DIRS value
# ---------------------------------------------------------------------------
assert_eq "EXCLUDE_DIRS contains all 7 dirs" \
  ".git node_modules target dist build .next coverage" \
  "$EXCLUDE_DIRS"

# ---------------------------------------------------------------------------
# Test: exclude_find_prune_args
# ---------------------------------------------------------------------------
ACTUAL_FIND="$(exclude_find_prune_args)"
EXPECTED_FIND="-name .git -o -name node_modules -o -name target -o -name dist -o -name build -o -name .next -o -name coverage"
assert_eq "exclude_find_prune_args output" "$EXPECTED_FIND" "$ACTUAL_FIND"

# ---------------------------------------------------------------------------
# Test: exclude_agentroot_flags
# ---------------------------------------------------------------------------
ACTUAL_AGENT="$(exclude_agentroot_flags)"
# Trim trailing space from output
ACTUAL_AGENT="${ACTUAL_AGENT% }"
EXPECTED_AGENT="--exclude .git --exclude node_modules --exclude target --exclude dist --exclude build --exclude .next --exclude coverage"
assert_eq "exclude_agentroot_flags output" "$EXPECTED_AGENT" "$ACTUAL_AGENT"

# ---------------------------------------------------------------------------
# Test: exclude_rg_globs
# ---------------------------------------------------------------------------
ACTUAL_RG="$(exclude_rg_globs)"
ACTUAL_RG="${ACTUAL_RG% }"
EXPECTED_RG="--glob '!.git/**' --glob '!node_modules/**' --glob '!target/**' --glob '!dist/**' --glob '!build/**' --glob '!.next/**' --glob '!coverage/**'"
assert_eq "exclude_rg_globs output" "$EXPECTED_RG" "$ACTUAL_RG"

# ---------------------------------------------------------------------------
# Test: exclude_dirs_json_array
# ---------------------------------------------------------------------------
ACTUAL_JSON="$(exclude_dirs_json_array)"
EXPECTED_JSON='[".git", "node_modules", "target", "dist", "build", ".next", "coverage"]'
assert_eq "exclude_dirs_json_array output" "$EXPECTED_JSON" "$ACTUAL_JSON"

# ---------------------------------------------------------------------------
# Test: exclude_dirs_json_array produces valid JSON
# ---------------------------------------------------------------------------
# Validate the JSON array is parseable (basic bracket/quote check)
if printf '%s' "$ACTUAL_JSON" | grep -qE '^\[("[^"]*"(, "[^"]*")*)\]$'; then
  pass "exclude_dirs_json_array valid JSON format"
else
  fail "exclude_dirs_json_array valid JSON format"
fi

# ---------------------------------------------------------------------------
# Test: exclude_find_prune_args has no leading -o
# ---------------------------------------------------------------------------
if printf '%s' "$ACTUAL_FIND" | grep -q '^-name'; then
  pass "exclude_find_prune_args no leading -o"
else
  fail "exclude_find_prune_args no leading -o"
fi

# ---------------------------------------------------------------------------
# Test: no empty flags emitted (regression guard)
# ---------------------------------------------------------------------------
if printf '%s' "$ACTUAL_AGENT" | grep -qE -- '--exclude  |--exclude$'; then
  fail "exclude_agentroot_flags emits empty flag"
else
  pass "exclude_agentroot_flags no empty flags"
fi

if printf '%s' "$ACTUAL_RG" | grep -qE -- "--glob ''|--glob '\!'"; then
  fail "exclude_rg_globs emits empty glob"
else
  pass "exclude_rg_globs no empty globs"
fi

# ---------------------------------------------------------------------------
# Test: count of directories matches expected 7
# ---------------------------------------------------------------------------
DIR_COUNT=0
for _d in $EXCLUDE_DIRS; do
  DIR_COUNT=$((DIR_COUNT + 1))
done
assert_eq "EXCLUDE_DIRS has 7 entries" "7" "$DIR_COUNT"

# ---------------------------------------------------------------------------
# Contract tests: helper output matches hardcoded patterns in scripts
# ---------------------------------------------------------------------------

# Verify agentroot flags match the inline list in run_index.sh
INLINE_AGENTROOT="--exclude .git --exclude node_modules --exclude target --exclude dist --exclude build --exclude .next --exclude coverage"
assert_eq "agentroot flags match run_index.sh inline" "$INLINE_AGENTROOT" "$ACTUAL_AGENT"

# Verify JSON array matches the inline manifest pattern in run_index.sh
INLINE_JSON='[".git", "node_modules", "target", "dist", "build", ".next", "coverage"]'
assert_eq "JSON array matches run_index.sh manifest" "$INLINE_JSON" "$ACTUAL_JSON"

# Verify rg globs match the inline list in build_read_plan.sh
INLINE_RG="--glob '!.git/**' --glob '!node_modules/**' --glob '!target/**' --glob '!dist/**' --glob '!build/**' --glob '!.next/**' --glob '!coverage/**'"
assert_eq "rg globs match build_read_plan.sh inline" "$INLINE_RG" "$ACTUAL_RG"

# Verify find prune covers all dirs from run_index.sh repo_has_file_named()
for dir in .git node_modules target dist build .next coverage; do
  if printf '%s' "$ACTUAL_FIND" | grep -q -- "-name $dir"; then
    pass "find prune includes $dir"
  else
    fail "find prune includes $dir"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
