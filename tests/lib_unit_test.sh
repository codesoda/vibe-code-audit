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
# Per-directory membership checks: agentroot flags
# ---------------------------------------------------------------------------
for dir in .git node_modules target dist build .next coverage; do
  if printf '%s' "$ACTUAL_AGENT" | grep -q -- "--exclude $dir"; then
    pass "agentroot flags includes $dir"
  else
    fail "agentroot flags includes $dir"
    printf '  actual: %s\n' "$ACTUAL_AGENT" >&2
  fi
done

# ---------------------------------------------------------------------------
# Per-directory membership checks: rg globs
# ---------------------------------------------------------------------------
for dir in .git node_modules target dist build .next coverage; do
  if printf '%s' "$ACTUAL_RG" | grep -qF -- "--glob '!${dir}/**'"; then
    pass "rg globs includes $dir"
  else
    fail "rg globs includes $dir"
    printf '  actual: %s\n' "$ACTUAL_RG" >&2
  fi
done

# ---------------------------------------------------------------------------
# Per-directory membership checks: JSON array
# ---------------------------------------------------------------------------
for dir in .git node_modules target dist build .next coverage; do
  if printf '%s' "$ACTUAL_JSON" | grep -qF "\"$dir\""; then
    pass "json array includes $dir"
  else
    fail "json array includes $dir"
    printf '  actual: %s\n' "$ACTUAL_JSON" >&2
  fi
done

# ---------------------------------------------------------------------------
# JSON element count: exactly 7 quoted entries
# ---------------------------------------------------------------------------
JSON_ELEM_COUNT="$(printf '%s' "$ACTUAL_JSON" | grep -o '"[^"]*"' | wc -l | tr -d ' ')"
assert_eq "json array has exactly 7 elements" "7" "$JSON_ELEM_COUNT"

# ---------------------------------------------------------------------------
# Duplicate entry guards: no directory appears more than once per helper
# ---------------------------------------------------------------------------
_count_occurrences() {
  local haystack="$1" needle="$2"
  local count=0 tmp="$haystack"
  while [ "${tmp#*"$needle"}" != "$tmp" ]; do
    count=$((count + 1))
    tmp="${tmp#*"$needle"}"
  done
  printf '%d' "$count"
}

_check_no_duplicates() {
  local label="$1" output="$2" needle_fmt="$3"
  local dir count
  for dir in .git node_modules target dist build .next coverage; do
    # shellcheck disable=SC2059
    needle="$(printf -- "$needle_fmt" "$dir")"
    count="$(_count_occurrences "$output" "$needle")"
    if [ "$count" -gt 1 ]; then
      fail "$label duplicate entry: $dir appears $count times"
      return
    fi
  done
  pass "$label no duplicate entries"
}

_check_no_duplicates "find prune" "$ACTUAL_FIND" "-name %s"
_check_no_duplicates "agentroot flags" "$ACTUAL_AGENT" "--exclude %s"
_check_no_duplicates "rg globs" "$ACTUAL_RG" "'!%s/**'"
_check_no_duplicates "json array" "$ACTUAL_JSON" '"%s"'

# ---------------------------------------------------------------------------
# Non-empty output guards: ensure no helper returns empty string
# ---------------------------------------------------------------------------
for _helper_name in ACTUAL_FIND ACTUAL_AGENT ACTUAL_RG ACTUAL_JSON; do
  eval "_helper_val=\"\${$_helper_name}\""
  if [ -z "$_helper_val" ]; then
    fail "$_helper_name is unexpectedly empty"
  else
    pass "$_helper_name is non-empty"
  fi
done

# ===========================================================================
# json_escape tests
# ===========================================================================

# ---------------------------------------------------------------------------
# Test: json_escape — newline
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'hello\nworld')"
assert_eq "json_escape newline" 'hello\nworld' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — tab
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'hello\tworld')"
assert_eq "json_escape tab" 'hello\tworld' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — carriage return
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'hello\rworld')"
assert_eq "json_escape carriage return" 'hello\rworld' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — double quote
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape 'say "hello"')"
assert_eq "json_escape double quote" 'say \"hello\"' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — backslash
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape 'back\slash')"
assert_eq "json_escape backslash" 'back\\slash' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — backspace (0x08)
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'a\bb')"
assert_eq "json_escape backspace" 'a\bb' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — form feed (0x0c)
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'a\fb')"
assert_eq "json_escape form feed" 'a\fb' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — empty input returns empty output
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape '')"
assert_eq "json_escape empty input" '' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — plain ASCII passes through unchanged
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape 'hello world 123')"
assert_eq "json_escape plain ASCII" 'hello world 123' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — control characters use \uXXXX encoding
# Representative controls: SOH (0x01), STX (0x02), BEL (0x07), ESC (0x1b)
# Note: NUL (0x00) cannot be passed via bash variables; this is a known
# shell limitation documented in _lib.sh. NUL handling is correct in the
# byte-stream path but untestable via $1 argument passing.
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'\x01')"
assert_eq "json_escape SOH (0x01)" '\u0001' "$ACTUAL"

ACTUAL="$(json_escape $'\x02')"
assert_eq "json_escape STX (0x02)" '\u0002' "$ACTUAL"

ACTUAL="$(json_escape $'\x07')"
assert_eq "json_escape BEL (0x07)" '\u0007' "$ACTUAL"

ACTUAL="$(json_escape $'\x1b')"
assert_eq "json_escape ESC (0x1b)" '\u001b' "$ACTUAL"

ACTUAL="$(json_escape $'\x1f')"
assert_eq "json_escape US (0x1f)" '\u001f' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — mixed control chars in a single string
# ---------------------------------------------------------------------------
ACTUAL="$(json_escape $'line1\nline2\ttab\r\n')"
assert_eq "json_escape mixed controls" 'line1\nline2\ttab\r\n' "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: json_escape — version string with newline produces valid JSON
# Validates that escaped output can be safely wrapped in JSON quotes
# without embedded raw control bytes. Uses shell-only structural check
# (no jq dependency).
# ---------------------------------------------------------------------------
VERSION=$'1.2.3\n'
ESCAPED="$(json_escape "$VERSION")"
JSON_DOC="{\"version\":\"${ESCAPED}\"}"

# Structural check: no raw control bytes remain in the JSON string.
# Uses od to detect any byte 0x00-0x1f in the output (portable, no grep -P).
RAW_CTRL_COUNT="$(printf '%s' "$JSON_DOC" | LC_ALL=C od -An -tx1 | tr ' ' '\n' | grep -cE '^(0[0-9a-f]|1[0-9a-f])$' || true)"
if [ "$RAW_CTRL_COUNT" -eq 0 ]; then
  pass "json_escape version string: no raw control bytes"
else
  fail "json_escape version string: raw control bytes in JSON output (found $RAW_CTRL_COUNT)"
fi

# Structural check: JSON doc matches basic object pattern
if printf '%s' "$JSON_DOC" | grep -qE '^\{"version":"[^"]*"\}$'; then
  pass "json_escape version string: valid JSON structure"
else
  fail "json_escape version string: valid JSON structure"
  printf '  json_doc: %s\n' "$JSON_DOC" >&2
fi

# ===========================================================================
# resolve_output_dir tests
# ===========================================================================

# Fixture setup: create temp root for all path tests, clean up on exit.
ROD_TMPDIR="$(mktemp -d)"
_rod_cleanup() { rm -rf "$ROD_TMPDIR"; }
trap _rod_cleanup EXIT

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — absolute path returns same path
# ---------------------------------------------------------------------------
ROD_ABS_DIR="$ROD_TMPDIR/abs_test"
mkdir -p "$ROD_ABS_DIR"
ACTUAL="$(resolve_output_dir "$ROD_ABS_DIR")"
# Use pwd -P to get the physical path of our expected value (macOS /tmp -> /private/tmp)
EXPECTED="$(cd "$ROD_ABS_DIR" && pwd -P)"
assert_eq "resolve_output_dir absolute path" "$EXPECTED" "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — relative path resolves to absolute
# ---------------------------------------------------------------------------
ROD_REL_BASE="$ROD_TMPDIR/rel_base"
mkdir -p "$ROD_REL_BASE"
ACTUAL="$(cd "$ROD_REL_BASE" && resolve_output_dir "child/output")"
EXPECTED="$(cd "$ROD_REL_BASE/child/output" && pwd -P)"
assert_eq "resolve_output_dir relative path" "$EXPECTED" "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — parent traversal (..) normalizes correctly
# ---------------------------------------------------------------------------
ROD_TRAVERSE_DIR="$ROD_TMPDIR/traverse/deep"
mkdir -p "$ROD_TRAVERSE_DIR"
ACTUAL="$(resolve_output_dir "$ROD_TRAVERSE_DIR/../deep")"
EXPECTED="$(cd "$ROD_TRAVERSE_DIR" && pwd -P)"
assert_eq "resolve_output_dir parent traversal (..)" "$EXPECTED" "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — symlink resolves to physical path
# Uses pwd -P (Decision B) to return the real directory, not the symlink.
# ---------------------------------------------------------------------------
ROD_REAL_DIR="$ROD_TMPDIR/real_target"
ROD_LINK="$ROD_TMPDIR/sym_link"
mkdir -p "$ROD_REAL_DIR"
ln -s "$ROD_REAL_DIR" "$ROD_LINK"
ACTUAL="$(resolve_output_dir "$ROD_LINK")"
EXPECTED="$(cd "$ROD_REAL_DIR" && pwd -P)"
assert_eq "resolve_output_dir symlink resolves to real path" "$EXPECTED" "$ACTUAL"

# ---------------------------------------------------------------------------
# resolve_output_dir contract matrix (Spec 25)
#
# resolve_output_dir() uses mkdir -p internally. Its contract is:
#   SUCCEEDS: path exists           → resolved to canonical absolute path
#   SUCCEEDS: path does not exist   → created via mkdir -p, then resolved
#   FAILS:    path is unresolvable  → exits non-zero (e.g. parent is a file)
#
# The "non-existent path" case is NOT a failure — it exercises mkdir -p.
# The failure case is an *unresolvable* path where mkdir -p itself fails.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — creates missing directory (mkdir -p behavior)
# ---------------------------------------------------------------------------
ROD_NEW_DIR="$ROD_TMPDIR/new_parent/new_child"
ACTUAL="$(resolve_output_dir "$ROD_NEW_DIR")"
EXPECTED="$(cd "$ROD_NEW_DIR" && pwd -P)"
assert_eq "resolve_output_dir creates missing directory" "$EXPECTED" "$ACTUAL"
if [ -d "$ROD_NEW_DIR" ]; then
  pass "resolve_output_dir created directory exists"
else
  fail "resolve_output_dir created directory exists"
fi

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — non-existent deep path is created (mkdir -p)
# Precondition: path must not exist. Postcondition: created and resolved.
# This proves the contract: non-existent ≠ failure; unresolvable = failure.
# ---------------------------------------------------------------------------
ROD_FRESH_DIR="$ROD_TMPDIR/fresh_nonexistent/deep/nested"
if [ -d "$ROD_FRESH_DIR" ]; then
  fail "resolve_output_dir non-existent precondition: directory should not exist yet"
else
  pass "resolve_output_dir non-existent precondition: directory does not exist yet"
fi
ACTUAL="$(resolve_output_dir "$ROD_FRESH_DIR")"
EXPECTED="$(cd "$ROD_FRESH_DIR" && pwd -P)"
assert_eq "resolve_output_dir non-existent path created and resolved" "$EXPECTED" "$ACTUAL"

# ---------------------------------------------------------------------------
# Test: resolve_output_dir — unresolvable path (file-as-parent) fails
# mkdir -p cannot create a child under a regular file → non-zero exit.
# This is the contract failure case (not merely "non-existent").
# ---------------------------------------------------------------------------
ROD_BLOCKER="$ROD_TMPDIR/blocker_file"
touch "$ROD_BLOCKER"
if _rod_out="$(resolve_output_dir "$ROD_BLOCKER/child" 2>/dev/null)"; then
  fail "resolve_output_dir unresolvable path should fail"
else
  pass "resolve_output_dir unresolvable path exits non-zero"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
