# shellcheck shell=bash
# _test_lib.sh — shared test harness for vibe-code-audit test suite
#
# Sourced by all test files. Provides:
#   - pass()/fail() counter functions
#   - assert_eq() helper
#   - setup_tmproot() / cleanup_tmproot() for temp dir lifecycle
#   - print_results() for uniform summary output
#   - build_filtered_path() for hiding commands during testing
#   - assert_no_crash_diagnostics() for crash pattern detection
#   - Automatic cleanup trap registration
#
# The sourcing script MUST:
#   1. Set `set -euo pipefail` before sourcing.
#   2. Optionally set TEST_NAME before sourcing (used in output prefix).
#
# Optional modes:
#   FILE_COUNTERS=1  — use file-based pass/fail counters (safe in subshells).
#                      Requires setup_tmproot() to be called first.

TEST_NAME="${TEST_NAME:-$(basename "$0" .sh)}"
# shellcheck disable=SC2034  # ROOT_DIR is used by sourcing scripts
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

# File-based counter support (for subshell-safe counting)
FILE_COUNTERS="${FILE_COUNTERS:-0}"
_PASS_FILE=""
_FAIL_FILE=""

_init_file_counters() {
  if [ "$FILE_COUNTERS" -eq 1 ] && [ -n "${TMPROOT:-}" ]; then
    _PASS_FILE="$TMPROOT/.pass_count"
    _FAIL_FILE="$TMPROOT/.fail_count"
    printf '0\n' > "$_PASS_FILE"
    printf '0\n' > "$_FAIL_FILE"
  fi
}

pass() {
  if [ "$FILE_COUNTERS" -eq 1 ] && [ -n "$_PASS_FILE" ]; then
    local c
    c="$(cat "$_PASS_FILE")"
    printf '%d\n' "$((c + 1))" > "$_PASS_FILE"
  else
    PASS=$((PASS + 1))
  fi
  printf 'PASS: %s\n' "$*"
}

fail() {
  if [ "$FILE_COUNTERS" -eq 1 ] && [ -n "$_FAIL_FILE" ]; then
    local c
    c="$(cat "$_FAIL_FILE")"
    printf '%d\n' "$((c + 1))" > "$_FAIL_FILE"
  else
    FAIL=$((FAIL + 1))
  fi
  printf 'FAIL: %s\n' "$*" >&2
}

# assert_eq LABEL EXPECTED ACTUAL
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label"
    printf '  expected: %s\n' "$expected" >&2
    printf '  actual:   %s\n' "$actual" >&2
  fi
}

# ---------------------------------------------------------------------------
# Temp directory lifecycle
# ---------------------------------------------------------------------------

TMPROOT=""

setup_tmproot() {
  TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/vca-test-${TEST_NAME}.XXXXXX")"
  if [ "$FILE_COUNTERS" -eq 1 ]; then
    _init_file_counters
  fi
}

cleanup_tmproot() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}

trap cleanup_tmproot EXIT INT TERM

# ---------------------------------------------------------------------------
# PATH manipulation helpers
# ---------------------------------------------------------------------------

# build_filtered_path COMMAND
#   Builds a colon-separated PATH string with directories containing COMMAND
#   removed. Result is stored in FILTERED_PATH.
build_filtered_path() {
  local cmd_to_hide="$1"
  FILTERED_PATH=""
  local segment
  IFS=':'
  for segment in $PATH; do
    if [ -z "$segment" ]; then
      continue
    fi
    if [ -x "$segment/$cmd_to_hide" ]; then
      continue
    fi
    if [ -n "$FILTERED_PATH" ]; then
      FILTERED_PATH="$FILTERED_PATH:$segment"
    else
      FILTERED_PATH="$segment"
    fi
  done
  unset IFS
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

# assert_no_crash_diagnostics CONTENT
#   Fails if CONTENT contains shell crash patterns (unbound variable, syntax
#   error, segfault, core dump, panic).
assert_no_crash_diagnostics() {
  local content="$1"
  if echo "$content" | grep -Eiq 'unbound variable|syntax error|segmentation fault|core dumped|panic'; then
    fail "stderr contains crash diagnostic: $(echo "$content" | grep -Ei 'unbound variable|syntax error|segmentation fault|core dumped|panic' | head -1)"
  else
    pass "no crash diagnostics in stderr"
  fi
}

# ---------------------------------------------------------------------------
# Results summary
# ---------------------------------------------------------------------------

print_results() {
  # Sync from file counters if active
  if [ "$FILE_COUNTERS" -eq 1 ] && [ -n "$_PASS_FILE" ] && [ -f "$_PASS_FILE" ]; then
    PASS="$(cat "$_PASS_FILE")"
    FAIL="$(cat "$_FAIL_FILE")"
  fi
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
