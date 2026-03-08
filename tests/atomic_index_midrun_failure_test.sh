#!/usr/bin/env bash
set -euo pipefail

# Test: Atomic Index Mid-Run Failure (Spec 36)
#
# Validates that:
#   - After a mid-run failure, no audit_index.tmp/ remains
#   - Any prior audit_index/ is untouched
#   - After a successful run, audit_index/ has fresh content and audit_index.tmp/ is absent

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_INDEX_SCRIPT="$ROOT_DIR/vibe-code-audit/scripts/run_index.sh"

TEST_TMPDIR=""
cleanup() {
  if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}
trap cleanup EXIT INT TERM

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/vca-atomic-idx-test.XXXXXX")"

PASS_FILE="$TEST_TMPDIR/.pass_count"
FAIL_FILE="$TEST_TMPDIR/.fail_count"
printf '0\n' > "$PASS_FILE"
printf '0\n' > "$FAIL_FILE"

pass() {
  local c
  c="$(cat "$PASS_FILE")"
  printf '%d\n' "$((c + 1))" > "$PASS_FILE"
  printf '[atomic_index_midrun] PASS: %s\n' "$1"
}

fail() {
  local c
  c="$(cat "$FAIL_FILE")"
  printf '%d\n' "$((c + 1))" > "$FAIL_FILE"
  printf '[atomic_index_midrun] FAIL: %s\n' "$1" >&2
}

# --- Helper: create mock binaries ---

write_mock_llmcc() {
  local bin_dir="$1"
  local fail_on_graph="$2"  # "1" = fail during graph generation, "0" = succeed

  cat > "$bin_dir/llmcc" <<MOCK_EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\${1:-}" = "--version" ]; then
  printf 'llmcc mock 0.0.0\n'
  exit 0
fi

if [ "\${1:-}" = "--help" ]; then
  printf 'Usage: llmcc [OPTIONS] <--file <FILE>...|--dir <DIR>...>\n'
  printf '  -d, --dir <DIR>...\n'
  exit 0
fi

# Graph generation
if [ "$fail_on_graph" = "1" ]; then
  printf 'error: forced mid-run graph failure\n' >&2
  exit 2
fi

# Success path: parse -o and write a dot file
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --dir|--lang|--depth|--pagerank-top-k) shift 2 ;;
    --graph) shift ;;
    -o) out="\${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "\$out" ]; then
  mkdir -p "\$(dirname "\$out")"
  printf 'digraph G { "a" -> "b"; }\n' > "\$out"
fi
printf 'Total time: 0.01s\n'
MOCK_EOF
  chmod +x "$bin_dir/llmcc"
}

write_mock_agentroot() {
  local bin_dir="$1"

  cat > "$bin_dir/agentroot" <<'MOCK_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"

if [ "$cmd" = "--version" ]; then
  printf 'agentroot mock 0.0.0\n'
  exit 0
fi

if [ "$cmd" = "--help" ]; then
  printf 'Usage: agentroot <command>\n  collection\n  update\n  status\n  query\n  vsearch\n'
  exit 0
fi

if [ "$cmd" = "index" ] && [ "${2:-}" = "--help" ]; then
  printf "error: unknown command 'index'\n" >&2
  exit 2
fi

case "$cmd" in
  collection)
    sub="${2:-}"
    case "$sub" in
      add)
        printf 'collection added\n'
        ;;
      list)
        printf 'mock-collection\n'
        ;;
      *)
        printf 'collection command ok\n'
        ;;
    esac
    ;;
  update)
    printf 'updated\n'
    ;;
  embed)
    printf 'embedded\n'
    ;;
  status)
    if [ "${2:-}" = "--format" ] && [ "${3:-}" = "json" ]; then
      printf '{"document_count": 23, "embedded_count": 23}\n'
      exit 0
    fi
    printf '{"document_count": 23, "embedded_count": 23}\n'
    ;;
  query|vsearch)
    shift
    query_text="${1:-}"
    shift || true
    if [ "${1:-}" = "--format" ] && [ "${2:-}" = "json" ]; then
      printf '{"query": "%s", "count": 1}\n' "$query_text"
      exit 0
    fi
    printf 'result for %s\n' "$query_text"
    ;;
  *)
    printf 'error: unknown command %s\n' "$cmd" >&2
    exit 2
    ;;
esac
MOCK_EOF
  chmod +x "$bin_dir/agentroot"
}

create_rust_repo_fixture() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/src"
  cat > "$repo_dir/Cargo.toml" <<'EOF'
[package]
name = "mock-atomic-test"
version = "0.1.0"
edition = "2021"
EOF
  cat > "$repo_dir/src/main.rs" <<'EOF'
fn main() { println!("test"); }
EOF
}

# ============================================================
# TEST 1: Mid-run failure — old audit_index/ preserved, no tmp
# ============================================================

(
  set -euo pipefail

  work_dir="$TEST_TMPDIR/case-failure"
  repo_dir="$work_dir/repo"
  output_dir="$work_dir/output"
  bin_dir="$work_dir/bin"

  mkdir -p "$bin_dir"
  create_rust_repo_fixture "$repo_dir"

  # Mock llmcc that fails during graph generation (mid-run)
  write_mock_llmcc "$bin_dir" "1"
  write_mock_agentroot "$bin_dir"

  # Pre-create audit_index/ with a sentinel marker
  mkdir -p "$output_dir/audit_index"
  printf 'pre-existing-sentinel\n' > "$output_dir/audit_index/.pre_existing_marker"
  printf '{"old": true}\n' > "$output_dir/audit_index/old_manifest.json"

  # Run with mocks — should fail mid-run when llmcc tries to generate graphs
  SCRIPT_EXIT=0
  PATH="$bin_dir:$PATH" \
  VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0 \
    bash "$RUN_INDEX_SCRIPT" \
      --repo "$repo_dir" \
      --output "$output_dir" \
      --mode standard >/dev/null 2>&1 || SCRIPT_EXIT=$?

  # Assert: non-zero exit
  if [ "$SCRIPT_EXIT" -ne 0 ]; then
    pass "1a: non-zero exit code on mid-run failure (exit=$SCRIPT_EXIT)"
  else
    fail "1a: expected non-zero exit, got 0"
  fi

  # Assert: no audit_index.tmp/ remains
  if [ ! -d "$output_dir/audit_index.tmp" ]; then
    pass "1b: audit_index.tmp/ absent after mid-run failure"
  else
    fail "1b: audit_index.tmp/ still exists after mid-run failure"
  fi

  # Assert: original audit_index/ sentinel preserved
  if [ -f "$output_dir/audit_index/.pre_existing_marker" ]; then
    marker_content="$(cat "$output_dir/audit_index/.pre_existing_marker")"
    if [ "$marker_content" = "pre-existing-sentinel" ]; then
      pass "1c: original audit_index/ sentinel preserved with correct content"
    else
      fail "1c: sentinel exists but content changed: $marker_content"
    fi
  else
    fail "1c: original audit_index/.pre_existing_marker missing after failure"
  fi

  # Assert: original audit_index/ extra file preserved
  if [ -f "$output_dir/audit_index/old_manifest.json" ]; then
    pass "1d: original audit_index/old_manifest.json preserved"
  else
    fail "1d: original audit_index/old_manifest.json missing after failure"
  fi
)

# ============================================================
# TEST 2: Success path — fresh audit_index/, no tmp remains
# ============================================================

(
  set -euo pipefail

  work_dir="$TEST_TMPDIR/case-success"
  repo_dir="$work_dir/repo"
  output_dir="$work_dir/output"
  bin_dir="$work_dir/bin"

  mkdir -p "$bin_dir"
  create_rust_repo_fixture "$repo_dir"

  # Mock llmcc that succeeds
  write_mock_llmcc "$bin_dir" "0"
  write_mock_agentroot "$bin_dir"

  mkdir -p "$output_dir"

  # Run with mocks — should succeed
  SCRIPT_EXIT=0
  PATH="$bin_dir:$PATH" \
  VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0 \
    bash "$RUN_INDEX_SCRIPT" \
      --repo "$repo_dir" \
      --output "$output_dir" \
      --mode standard >/dev/null 2>&1 || SCRIPT_EXIT=$?

  # Assert: zero exit
  if [ "$SCRIPT_EXIT" -eq 0 ]; then
    pass "2a: zero exit code on success"
  else
    fail "2a: expected zero exit, got $SCRIPT_EXIT"
  fi

  # Assert: no audit_index.tmp/ remains
  if [ ! -d "$output_dir/audit_index.tmp" ]; then
    pass "2b: audit_index.tmp/ absent after successful run"
  else
    fail "2b: audit_index.tmp/ still exists after successful run"
  fi

  # Assert: audit_index/ exists with fresh content
  if [ -d "$output_dir/audit_index" ]; then
    pass "2c: audit_index/ directory exists after success"
  else
    fail "2c: audit_index/ directory missing after success"
  fi

  # Assert: manifest.json exists and is non-empty
  if [ -s "$output_dir/audit_index/manifest.json" ]; then
    pass "2d: manifest.json exists and is non-empty"
  else
    fail "2d: manifest.json missing or empty"
  fi

  # Assert: derived/catalog.json exists
  if [ -s "$output_dir/audit_index/derived/catalog.json" ]; then
    pass "2e: derived/catalog.json exists and is non-empty"
  else
    fail "2e: derived/catalog.json missing or empty"
  fi

  # Assert: no nested audit_index.tmp inside audit_index
  if [ ! -d "$output_dir/audit_index/audit_index.tmp" ]; then
    pass "2f: no nested audit_index.tmp inside audit_index/"
  else
    fail "2f: nested audit_index/audit_index.tmp/ detected"
  fi
)

# ============================================================
# TEST 3: Success replaces pre-existing audit_index/
# ============================================================

(
  set -euo pipefail

  work_dir="$TEST_TMPDIR/case-success-replace"
  repo_dir="$work_dir/repo"
  output_dir="$work_dir/output"
  bin_dir="$work_dir/bin"

  mkdir -p "$bin_dir"
  create_rust_repo_fixture "$repo_dir"

  write_mock_llmcc "$bin_dir" "0"
  write_mock_agentroot "$bin_dir"

  # Pre-create audit_index/ with old sentinel
  mkdir -p "$output_dir/audit_index"
  printf 'old-sentinel\n' > "$output_dir/audit_index/.pre_existing_marker"

  SCRIPT_EXIT=0
  PATH="$bin_dir:$PATH" \
  VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0 \
    bash "$RUN_INDEX_SCRIPT" \
      --repo "$repo_dir" \
      --output "$output_dir" \
      --mode standard >/dev/null 2>&1 || SCRIPT_EXIT=$?

  if [ "$SCRIPT_EXIT" -eq 0 ]; then
    pass "3a: zero exit code on success with pre-existing index"
  else
    fail "3a: expected zero exit, got $SCRIPT_EXIT"
  fi

  # Assert: old sentinel is gone (replaced by new content)
  if [ ! -f "$output_dir/audit_index/.pre_existing_marker" ]; then
    pass "3b: old sentinel removed — audit_index/ was replaced"
  else
    fail "3b: old sentinel still present — audit_index/ was NOT replaced"
  fi

  # Assert: new manifest exists
  if [ -s "$output_dir/audit_index/manifest.json" ]; then
    pass "3c: fresh manifest.json present after replacement"
  else
    fail "3c: manifest.json missing after replacement"
  fi

  # Assert: no tmp remains
  if [ ! -d "$output_dir/audit_index.tmp" ]; then
    pass "3d: audit_index.tmp/ absent after successful replacement"
  else
    fail "3d: audit_index.tmp/ still present after successful replacement"
  fi
)

# ============================================================
# Summary
# ============================================================

PASS="$(cat "$PASS_FILE")"
FAIL="$(cat "$FAIL_FILE")"
printf '\n[atomic_index_midrun] Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
