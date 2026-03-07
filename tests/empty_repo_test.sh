#!/usr/bin/env bash
set -euo pipefail

# Empty-repo edge case test for build_derived_artifacts.sh (Spec 32)
# Verifies that an empty repo (just .git/, no source files) produces:
#   1. Clean exit (exit code 0, no unbound variable errors)
#   2. Valid catalog.json with all stacks false and empty crates
#   3. Valid hotspots.json with empty files_by_symbol_count
#   4. Non-empty dup_clusters.md bootstrap scaffold

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/vibe-code-audit/scripts/build_derived_artifacts.sh"

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
# Setup: temp fixture with empty repo, cleanup trap
# ---------------------------------------------------------------------------

TMPROOT=""

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT INT TERM

TMPROOT="$(mktemp -d)"
MOCK_REPO="$TMPROOT/repo"
OUTPUT_DIR="$TMPROOT/output"
mkdir -p "$MOCK_REPO/.git" "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Execute build_derived_artifacts.sh against empty repo
# ---------------------------------------------------------------------------

SCRIPT_EXIT=0
bash "$SCRIPT" \
  --repo "$MOCK_REPO" \
  --output "$OUTPUT_DIR/audit_index.tmp" \
  --mode fast \
  --top-k 10 \
  2>"$TMPROOT/stderr.log" || SCRIPT_EXIT=$?

if [ "$SCRIPT_EXIT" -eq 0 ]; then
  pass "exit code 0"
else
  fail "exit code $SCRIPT_EXIT (expected 0)"
fi

# ---------------------------------------------------------------------------
# No-crash diagnostics: check stderr for fatal shell errors
# ---------------------------------------------------------------------------

STDERR_CONTENT=""
if [ -f "$TMPROOT/stderr.log" ]; then
  STDERR_CONTENT="$(cat "$TMPROOT/stderr.log")"
fi

CRASH_PATTERNS="unbound variable|syntax error|command not found|bad substitution"
if printf '%s' "$STDERR_CONTENT" | grep -qiE "$CRASH_PATTERNS"; then
  fail "stderr contains crash diagnostic"
  printf '  stderr: %s\n' "$STDERR_CONTENT" >&2
else
  pass "no crash diagnostics in stderr"
fi

# ---------------------------------------------------------------------------
# Assert artifact files exist and are non-empty
# ---------------------------------------------------------------------------

DERIVED="$OUTPUT_DIR/audit_index.tmp/derived"

for artifact in catalog.json hotspots.json dup_clusters.md; do
  if [ -f "$DERIVED/$artifact" ] && [ -s "$DERIVED/$artifact" ]; then
    pass "$artifact exists and is non-empty"
  else
    fail "$artifact missing or empty"
  fi
done

# ---------------------------------------------------------------------------
# JSON validity: python3 if available, else structural checks
# ---------------------------------------------------------------------------

validate_json() {
  local file="$1"
  local label="$2"

  if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$file" >/dev/null 2>&1; then
      pass "$label is valid JSON (python3)"
      return
    else
      fail "$label is invalid JSON (python3)"
      return
    fi
  fi

  # Structural fallback: starts with {, ends with }, non-empty
  local first last
  first="$(head -c1 "$file")"
  last="$(tail -c2 "$file" | head -c1)"
  if [ "$first" = "{" ] && [ "$last" = "}" ]; then
    pass "$label is structurally valid JSON (shell fallback)"
  else
    fail "$label structural JSON check failed (first='$first' last='$last')"
  fi
}

if [ -f "$DERIVED/catalog.json" ]; then
  validate_json "$DERIVED/catalog.json" "catalog.json"
fi

if [ -f "$DERIVED/hotspots.json" ]; then
  validate_json "$DERIVED/hotspots.json" "hotspots.json"
fi

# ---------------------------------------------------------------------------
# Semantic assertions: catalog.json
# ---------------------------------------------------------------------------

if [ -f "$DERIVED/catalog.json" ]; then
  CATALOG="$(cat "$DERIVED/catalog.json")"

  # Stack booleans should all be false
  for stack in rust typescript javascript; do
    if printf '%s' "$CATALOG" | grep -q "\"$stack\": false"; then
      pass "catalog stacks.$stack is false"
    else
      fail "catalog stacks.$stack is not false"
    fi
  done

  # workspace_detected should be false
  if printf '%s' "$CATALOG" | grep -q '"workspace_detected": false'; then
    pass "catalog workspace_detected is false"
  else
    fail "catalog workspace_detected is not false"
  fi

  # frontend.present should be false
  if printf '%s' "$CATALOG" | grep -q '"present": false'; then
    pass "catalog frontend.present is false"
  else
    fail "catalog frontend.present is not false"
  fi

  # crates should be empty array
  if printf '%s' "$CATALOG" | tr -d '[:space:]' | grep -q '"crates":\[\]'; then
    pass "catalog crates is empty array"
  else
    fail "catalog crates is not empty array"
  fi

  # Required keys present
  for key in repo_root workspace_detected stacks frontend crates; do
    if printf '%s' "$CATALOG" | grep -q "\"$key\""; then
      pass "catalog contains key '$key'"
    else
      fail "catalog missing key '$key'"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Semantic assertions: hotspots.json
# ---------------------------------------------------------------------------

if [ -f "$DERIVED/hotspots.json" ]; then
  HOTSPOTS="$(cat "$DERIVED/hotspots.json")"

  # hotspot_dot should be null
  if printf '%s' "$HOTSPOTS" | grep -q '"hotspot_dot": null'; then
    pass "hotspots hotspot_dot is null"
  else
    fail "hotspots hotspot_dot is not null"
  fi

  # files_by_symbol_count should be empty array
  if printf '%s' "$HOTSPOTS" | tr -d '[:space:]' | grep -q '"files_by_symbol_count":\[\]'; then
    pass "hotspots files_by_symbol_count is empty array"
  else
    fail "hotspots files_by_symbol_count is not empty array"
  fi

  # Required keys present
  for key in generated_at source mode top_k files_by_symbol_count; do
    if printf '%s' "$HOTSPOTS" | grep -q "\"$key\""; then
      pass "hotspots contains key '$key'"
    else
      fail "hotspots missing key '$key'"
    fi
  done
fi

# ---------------------------------------------------------------------------
# dup_clusters.md structural check
# ---------------------------------------------------------------------------

if [ -f "$DERIVED/dup_clusters.md" ]; then
  if grep -q '# Duplication Clusters' "$DERIVED/dup_clusters.md"; then
    pass "dup_clusters.md contains header"
  else
    fail "dup_clusters.md missing header"
  fi

  if grep -q 'No hotspot symbol-path data' "$DERIVED/dup_clusters.md"; then
    pass "dup_clusters.md indicates no hotspot data (expected for empty repo)"
  else
    fail "dup_clusters.md does not indicate missing hotspot data"
  fi
fi

# ---------------------------------------------------------------------------
# Cleanup verification: no temp file leaks from the script
# ---------------------------------------------------------------------------

# The script uses mktemp for its own work dir and cleans up via trap.
# Verify no vca-derived temp dirs leaked.
LEAKED=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'vca-derived.*' -type d 2>/dev/null | head -n5)
if [ -z "$LEAKED" ]; then
  pass "no vca-derived temp dirs leaked"
else
  fail "vca-derived temp dir(s) leaked: $LEAKED"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
