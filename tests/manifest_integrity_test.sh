#!/usr/bin/env bash
set -euo pipefail

# Manifest integrity test for INSTALL_MANIFEST.txt
# Ensures _lib.sh is listed exactly once and no duplicate entries exist.

TEST_NAME="manifest_integrity"
# shellcheck source=_test_lib.sh
. "$(dirname "$0")/_test_lib.sh"

MANIFEST="vibe-code-audit/INSTALL_MANIFEST.txt"

# 1. Manifest file exists
if [ -f "$MANIFEST" ]; then
  pass "manifest file exists"
else
  fail "manifest file not found at $MANIFEST"
  print_results
  exit 1
fi

# Strip comments and blank lines for content checks
CONTENT=$(grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$')

# 2. scripts/_lib.sh appears exactly once
LIB_COUNT=$(printf '%s\n' "$CONTENT" | grep -c '^scripts/_lib\.sh$' || true)
if [ "$LIB_COUNT" -eq 1 ]; then
  pass "scripts/_lib.sh listed exactly once"
else
  fail "scripts/_lib.sh count is $LIB_COUNT (expected 1)"
fi

# 3. No duplicate entries in manifest
DUP_COUNT=$(printf '%s\n' "$CONTENT" | sort | uniq -d | wc -l | tr -d ' ')
if [ "$DUP_COUNT" -eq 0 ]; then
  pass "no duplicate entries in manifest"
else
  DUPS=$(printf '%s\n' "$CONTENT" | sort | uniq -d)
  fail "found $DUP_COUNT duplicate entries: $DUPS"
fi

# 4. All expected script entries present
EXPECTED_SCRIPTS="run_index.sh run_agentroot_embed.sh build_derived_artifacts.sh build_read_plan.sh render_report_pdf.sh render_system_map.sh _lib.sh"
for script in $EXPECTED_SCRIPTS; do
  if printf '%s\n' "$CONTENT" | grep -q "^scripts/${script}$"; then
    pass "scripts/$script present"
  else
    fail "scripts/$script missing"
  fi
done

# 5. Entry format: _lib.sh line matches peer format (scripts/<name>)
LIB_LINE=$(printf '%s\n' "$CONTENT" | grep '_lib\.sh' || true)
if [ "$LIB_LINE" = "scripts/_lib.sh" ]; then
  pass "entry format matches peers"
else
  fail "entry format mismatch: got '$LIB_LINE'"
fi

print_results
