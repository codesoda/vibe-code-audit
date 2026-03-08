#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_INDEX_SCRIPT="$ROOT_DIR/vibe-code-audit/scripts/run_index.sh"

fail() {
  printf '[run_index_mock_smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

json_string() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n1
}

json_int() {
  file="$1"
  key="$2"
  value="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "$file" | head -n1)"
  if [ -z "$value" ]; then
    printf '0\n'
  else
    printf '%s\n' "$value"
  fi
}

json_bool() {
  file="$1"
  key="$2"
  value="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\(true\\).*/\\1/p" "$file" | head -n1)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\(false\\).*/\\1/p" "$file" | head -n1
}

assert_nonempty_file() {
  path="$1"
  [ -s "$path" ] || fail "expected non-empty file: $path"
}

write_mock_bins() {
  bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/llmcc" <<'EOF_LLMCC'
#!/usr/bin/env bash
set -euo pipefail

mode="${MOCK_LLMCC_MODE:-flag}"
help_style="${MOCK_LLMCC_HELP_STYLE:-$mode}"

write_dot() {
  out="$1"
  mkdir -p "$(dirname "$out")"
  printf 'digraph G { "a" -> "b"; }\n' > "$out"
}

if [ "${1:-}" = "--version" ]; then
  printf 'llmcc mock 0.0.0\n'
  exit 0
fi

if [ "${1:-}" = "--help" ]; then
  if [ "$help_style" = "flag" ]; then
    printf 'Usage: llmcc [OPTIONS] <--file <FILE>...|--dir <DIR>...>\n'
    printf '  -d, --dir <DIR>...\n'
  else
    printf 'Usage: llmcc depth1|depth2|depth3\n'
  fi
  exit 0
fi

if [ "$mode" = "legacy" ]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    depth1|depth2|depth3) ;;
    *)
      printf "error: unexpected argument '%s' found\n" "$cmd" >&2
      exit 2
      ;;
  esac

  out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pagerank-top-k)
        shift 2
        ;;
      -o)
        out="${2:-}"
        shift 2
        ;;
      *)
        printf 'error: unexpected argument %s\n' "$1" >&2
        exit 2
        ;;
    esac
  done

  [ -n "$out" ] || {
    printf 'error: missing -o\n' >&2
    exit 2
  }
  write_dot "$out"
  printf 'Total time: 0.01s\n'
  exit 0
fi

out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir|--lang|--depth|--pagerank-top-k)
      shift 2
      ;;
    --graph)
      shift
      ;;
    -o)
      out="${2:-}"
      shift 2
      ;;
    *)
      printf 'error: unexpected argument %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[ -n "$out" ] || {
  printf 'error: missing -o\n' >&2
  exit 2
}
write_dot "$out"
printf 'Total time: 0.01s\n'
EOF_LLMCC
  chmod +x "$bin_dir/llmcc"

  cat > "$bin_dir/agentroot" <<'EOF_AGENTROOT'
#!/usr/bin/env bash
set -euo pipefail

mode="${MOCK_AGENTROOT_MODE:-index}"
supports_json="${MOCK_AGENTROOT_FORMAT_JSON:-1}"
index_fail="${MOCK_AGENTROOT_INDEX_FAIL:-0}"
doc_count="${MOCK_AGENTROOT_DOC_COUNT:-23}"
embedded_count="${MOCK_AGENTROOT_EMBEDDED_COUNT:-23}"
embed_fail="${MOCK_AGENTROOT_EMBED_FAIL:-0}"
embed_fail_utf8="${MOCK_AGENTROOT_EMBED_FAIL_UTF8:-0}"
query_fail="${MOCK_AGENTROOT_QUERY_FAIL:-0}"
vsearch_fail="${MOCK_AGENTROOT_VSEARCH_FAIL:-0}"

emit_status_json() {
  printf '{"document_count": %s, "embedded_count": %s}\n' "$doc_count" "$embedded_count"
}

cmd="${1:-}"

if [ "$cmd" = "--version" ]; then
  printf 'agentroot mock 0.0.0\n'
  exit 0
fi

if [ "$cmd" = "--help" ]; then
  printf 'Usage: agentroot <command>\n'
  if [ "$mode" = "index" ]; then
    printf '  index\n'
  fi
  printf '  collection\n  update\n  status\n  query\n  vsearch\n'
  exit 0
fi

if [ "$cmd" = "index" ] && [ "${2:-}" = "--help" ]; then
  if [ "$mode" = "index" ]; then
    printf 'Usage: agentroot index <path> [--output DIR]\n'
    exit 0
  fi
  printf "error: unknown command 'index'\n" >&2
  exit 2
fi

case "$cmd" in
  index)
    if [ "$mode" != "index" ]; then
      printf "error: unknown command 'index'\n" >&2
      exit 2
    fi
    if [ "$index_fail" = "1" ]; then
      printf 'error: forced index failure\n' >&2
      exit 2
    fi
    shift
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --output)
          out="${2:-}"
          shift 2
          ;;
        --exclude)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ -n "$out" ]; then
      mkdir -p "$out"
    fi
    printf 'indexed\n'
    ;;
  collection)
    sub="${2:-}"
    case "$sub" in
      add)
        shift 2
        while [ $# -gt 0 ]; do
          case "$1" in
            --name|--mask)
              shift 2
              ;;
            *)
              shift
              ;;
          esac
        done
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
    if [ "$embed_fail" = "1" ]; then
      if [ "$embed_fail_utf8" = "1" ]; then
        printf "thread 'main' panicked at src/index/ast_chunker/oversized.rs:39:31:\n" >&2
        printf "byte index 12256 is not a char boundary; it is inside '—' (bytes 12255..12258)\n" >&2
      else
        printf 'error: forced embed failure\n' >&2
      fi
      exit 2
    fi
    printf 'embedded\n'
    ;;
  status)
    if [ "${2:-}" = "--format" ]; then
      if [ "${3:-}" = "json" ] && [ "$supports_json" = "1" ]; then
        emit_status_json
        exit 0
      fi
      printf 'error: unsupported format option\n' >&2
      exit 2
    fi
    emit_status_json
    ;;
  query|vsearch)
    shift
    query_text="${1:-}"
    shift || true
    if [ "$cmd" = "query" ] && [ "$query_fail" = "1" ]; then
      printf 'Error: HTTP error: error sending request for url (http://localhost:8000/v1/embeddings)\n' >&2
      printf '\nCaused by:\n    0: error sending request for url (http://localhost:8000/v1/embeddings)\n' >&2
      printf '    1: client error (Connect)\n    2: tcp connect error\n    3: Connection refused (os error 61)\n' >&2
      exit 2
    fi
    if [ "$cmd" = "vsearch" ] && [ "$vsearch_fail" = "1" ]; then
      printf 'Error: HTTP error: error sending request for url (http://localhost:8000/v1/embeddings)\n' >&2
      printf '\nCaused by:\n    0: error sending request for url (http://localhost:8000/v1/embeddings)\n' >&2
      printf '    1: client error (Connect)\n    2: tcp connect error\n    3: Connection refused (os error 61)\n' >&2
      exit 2
    fi
    if [ "${1:-}" = "--format" ]; then
      if [ "${2:-}" = "json" ] && [ "$supports_json" = "1" ]; then
        printf '{"query": "%s", "count": 1}\n' "$query_text"
        exit 0
      fi
      printf 'error: unsupported format option\n' >&2
      exit 2
    fi
    printf 'result for %s\n' "$query_text"
    ;;
  *)
    printf 'error: unknown command %s\n' "$cmd" >&2
    exit 2
    ;;
esac
EOF_AGENTROOT
  chmod +x "$bin_dir/agentroot"
}

run_case() {
  case_name="$1"
  llmcc_mode="$2"
  llmcc_help_style="$3"
  agentroot_mode="$4"
  agentroot_format_json="$5"
  agentroot_index_fail="$6"
  expected_llmcc_mode="$7"
  expected_agentroot_mode="$8"
  repo_layout="${9:-root-rust}"
  mock_embedded_count="${10:-23}"
  auto_embed_env="${11:-unset}"
  expected_embed_attempted="${12:-0}"
  expected_embed_ok="${13:-0}"
  expected_embed_backend="${14:-none}"
  mock_embed_fail="${15:-0}"
  mock_embed_fail_utf8="${16:-0}"
  mock_query_fail="${17:-0}"
  mock_vsearch_fail="${18:-0}"
  expected_retrieval_mode="${19:-}"
  expected_embed_utf8_panic="${20:-0}"
  case_mode="${21:-standard}"
  expected_top_k="${22:-}"
  skip_read_plan="${23:-0}"

  case "$skip_read_plan" in
    0|1) ;;
    *) fail "case $case_name: skip_read_plan must be 0|1, got '$skip_read_plan'" ;;
  esac

  (
    set -euo pipefail

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/vca-smoke.${case_name}.XXXXXX")"
    repo_dir="$work_dir/repo"
    output_dir="$work_dir/output"
    bin_dir="$work_dir/bin"

    if [ "$repo_layout" = "nested-rust" ] || [ "$repo_layout" = "nested-rust-mixed" ]; then
      mkdir -p "$repo_dir/backend/src"
      cat > "$repo_dir/backend/Cargo.toml" <<'EOF_CARGO'
[package]
name = "mock-nested-rust"
version = "0.1.0"
edition = "2021"
EOF_CARGO
      cat > "$repo_dir/backend/src/main.rs" <<'EOF_RS'
fn main() {
    println!("nested");
}
EOF_RS
      if [ "$repo_layout" = "nested-rust-mixed" ]; then
        cat > "$repo_dir/package.json" <<'EOF_PKG'
{"name": "mock-mixed-repo", "version": "1.0.0"}
EOF_PKG
      fi
    elif [ "$repo_layout" = "ts-node" ]; then
      mkdir -p "$repo_dir/src"
      cat > "$repo_dir/tsconfig.json" <<'EOF_TS'
{"compilerOptions": {"target": "es2020", "module": "commonjs"}}
EOF_TS
      cat > "$repo_dir/package.json" <<'EOF_PKG'
{"name": "mock-ts-repo", "version": "1.0.0"}
EOF_PKG
      cat > "$repo_dir/src/app.ts" <<'EOF_TSRC'
const greeting: string = "hello";
console.log(greeting);
EOF_TSRC
    elif [ "$repo_layout" = "js-only" ]; then
      mkdir -p "$repo_dir/src"
      cat > "$repo_dir/package.json" <<'EOF_PKG'
{"name": "mock-js-repo", "version": "1.0.0"}
EOF_PKG
      cat > "$repo_dir/src/index.js" <<'EOF_JS'
console.log("hello");
EOF_JS
    else
      mkdir -p "$repo_dir/src"
      cat > "$repo_dir/Cargo.toml" <<'EOF_CARGO'
[package]
name = "mock-repo"
version = "0.1.0"
edition = "2021"
EOF_CARGO
      cat > "$repo_dir/src/main.rs" <<'EOF_RS'
fn main() {
    println!("hello");
}
EOF_RS
    fi

    write_mock_bins "$bin_dir"

    PATH="$bin_dir:$PATH"
    export PATH
    export MOCK_LLMCC_MODE="$llmcc_mode"
    export MOCK_LLMCC_HELP_STYLE="$llmcc_help_style"
    export MOCK_AGENTROOT_MODE="$agentroot_mode"
    export MOCK_AGENTROOT_FORMAT_JSON="$agentroot_format_json"
    export MOCK_AGENTROOT_INDEX_FAIL="$agentroot_index_fail"
    export MOCK_AGENTROOT_DOC_COUNT="23"
    export MOCK_AGENTROOT_EMBEDDED_COUNT="$mock_embedded_count"
    export MOCK_AGENTROOT_EMBED_FAIL="$mock_embed_fail"
    export MOCK_AGENTROOT_EMBED_FAIL_UTF8="$mock_embed_fail_utf8"
    export MOCK_AGENTROOT_QUERY_FAIL="$mock_query_fail"
    export MOCK_AGENTROOT_VSEARCH_FAIL="$mock_vsearch_fail"
    case "$auto_embed_env" in
      unset)
        unset VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED
        ;;
      0|1)
        export VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED="$auto_embed_env"
        ;;
      *)
        fail "case $case_name: invalid auto_embed_env=$auto_embed_env"
        ;;
    esac

    # [R-006] Pre-create audit_index/ with sentinel to verify it survives the run
    mkdir -p "$output_dir/audit_index"
    printf 'sentinel\n' > "$output_dir/audit_index/.pre_existing_marker"

    skip_flags=""
    if [ "$skip_read_plan" -eq 1 ]; then
      skip_flags="--skip-read-plan"
    fi

    run_output="$(
      bash "$RUN_INDEX_SCRIPT" \
        --repo "$repo_dir" \
        --output "$output_dir" \
        --mode "$case_mode" \
        $skip_flags
    )"

    resolved_output="$(printf '%s\n' "$run_output" | sed -n 's/^OUTPUT_DIR=//p' | tail -n1)"
    [ -n "$resolved_output" ] || fail "case $case_name: run_index.sh did not emit OUTPUT_DIR"

    manifest="$resolved_output/audit_index/manifest.json"
    assert_nonempty_file "$manifest"
    assert_nonempty_file "$resolved_output/audit_index/derived/catalog.json"
    assert_nonempty_file "$resolved_output/audit_index/derived/hotspots.json"
    assert_nonempty_file "$resolved_output/audit_index/derived/dup_clusters.md"
    if [ "$skip_read_plan" -eq 1 ]; then
      if [ -e "$resolved_output/audit_index/derived/read_plan.tsv" ]; then
        fail "case $case_name: read_plan.tsv should NOT exist when --skip-read-plan is set"
      fi
      if [ -e "$resolved_output/audit_index/derived/read_plan.md" ]; then
        fail "case $case_name: read_plan.md should NOT exist when --skip-read-plan is set"
      fi
    else
      [ -e "$resolved_output/audit_index/derived/read_plan.tsv" ] || \
        fail "case $case_name: expected read_plan.tsv to exist"
      assert_nonempty_file "$resolved_output/audit_index/derived/read_plan.md"
    fi

    # Guard: no nested audit_index/audit_index.tmp path produced
    if [ -d "$resolved_output/audit_index/audit_index.tmp" ]; then
      fail "case $case_name: nested audit_index/audit_index.tmp directory detected — contract mismatch"
    fi

    # Assert no stale audit_index.tmp/ remains after successful run
    if [ -d "$resolved_output/audit_index.tmp" ]; then
      fail "case $case_name: audit_index.tmp/ still exists after successful run — atomic rename failed"
    fi

    # Pre-existing audit_index/ should be replaced (not preserved) on success
    if [ -f "$resolved_output/audit_index/.pre_existing_marker" ]; then
      fail "case $case_name: pre-existing sentinel still present — old audit_index/ was not replaced"
    fi

    llmcc_mode_actual="$(json_string "$manifest" "llmcc_mode")"
    [ "$llmcc_mode_actual" = "$expected_llmcc_mode" ] || \
      fail "case $case_name: expected llmcc_mode=$expected_llmcc_mode, got $llmcc_mode_actual"

    agentroot_mode_actual="$(json_string "$manifest" "agentroot_mode")"
    [ "$agentroot_mode_actual" = "$expected_agentroot_mode" ] || \
      fail "case $case_name: expected agentroot_mode=$expected_agentroot_mode, got $agentroot_mode_actual"

    doc_count="$(json_int "$manifest" "agentroot_document_count")"
    [ "$doc_count" -gt 0 ] || fail "case $case_name: agentroot_document_count should be > 0"

    query_ok="$(json_int "$manifest" "retrieval_query_ok")"
    vsearch_ok="$(json_int "$manifest" "retrieval_vsearch_ok")"
    if [ "$expected_retrieval_mode" != "bm25-only" ]; then
      [ "$query_ok" -eq 1 ] || [ "$vsearch_ok" -eq 1 ] || \
        fail "case $case_name: expected at least one retrieval check to pass"
    fi

    embed_attempted="$(json_int "$manifest" "agentroot_embed_attempted")"
    embed_ok="$(json_int "$manifest" "agentroot_embed_ok")"
    embed_backend="$(json_string "$manifest" "agentroot_embed_backend")"
    [ "$embed_attempted" -eq "$expected_embed_attempted" ] || \
      fail "case $case_name: expected agentroot_embed_attempted=$expected_embed_attempted, got $embed_attempted"
    [ "$embed_ok" -eq "$expected_embed_ok" ] || \
      fail "case $case_name: expected agentroot_embed_ok=$expected_embed_ok, got $embed_ok"
    [ "$embed_backend" = "$expected_embed_backend" ] || \
      fail "case $case_name: expected agentroot_embed_backend=$expected_embed_backend, got $embed_backend"

    embed_utf8_panic="$(json_int "$manifest" "agentroot_embed_utf8_panic")"
    [ "$embed_utf8_panic" -eq "$expected_embed_utf8_panic" ] || \
      fail "case $case_name: expected agentroot_embed_utf8_panic=$expected_embed_utf8_panic, got $embed_utf8_panic"

    if [ -n "$expected_retrieval_mode" ]; then
      retrieval_mode="$(json_string "$manifest" "retrieval_mode")"
      [ "$retrieval_mode" = "$expected_retrieval_mode" ] || \
        fail "case $case_name: expected retrieval_mode=$expected_retrieval_mode, got $retrieval_mode"
    fi

    if [ -n "$expected_top_k" ]; then
      actual_top_k="$(json_int "$manifest" "pagerank_top_k")"
      [ "$actual_top_k" -eq "$expected_top_k" ] || \
        fail "case $case_name: expected pagerank_top_k=$expected_top_k, got $actual_top_k"
    fi

    catalog="$resolved_output/audit_index/derived/catalog.json"
    assert_nonempty_file "$catalog"

    catalog_rust="$(json_bool "$catalog" "rust")"
    catalog_ts="$(json_bool "$catalog" "typescript")"
    catalog_js="$(json_bool "$catalog" "javascript")"

    if [ "$repo_layout" = "nested-rust" ]; then
      [ "$catalog_rust" = "true" ] || \
        fail "case $case_name: expected catalog stacks.rust=true for nested-rust layout, got $catalog_rust"
      [ "$catalog_ts" = "false" ] || \
        fail "case $case_name: expected catalog stacks.typescript=false for nested-rust layout, got $catalog_ts"
      [ "$catalog_js" = "false" ] || \
        fail "case $case_name: expected catalog stacks.javascript=false for nested-rust layout, got $catalog_js"
    elif [ "$repo_layout" = "nested-rust-mixed" ]; then
      [ "$catalog_rust" = "true" ] || \
        fail "case $case_name: expected catalog stacks.rust=true for nested-rust-mixed layout, got $catalog_rust"
      [ "$catalog_ts" = "false" ] || \
        fail "case $case_name: expected catalog stacks.typescript=false for nested-rust-mixed layout, got $catalog_ts"
      [ "$catalog_js" = "true" ] || \
        fail "case $case_name: expected catalog stacks.javascript=true for nested-rust-mixed layout, got $catalog_js"
    elif [ "$repo_layout" = "ts-node" ]; then
      [ "$catalog_rust" = "false" ] || \
        fail "case $case_name: expected catalog stacks.rust=false for ts-node layout, got $catalog_rust"
      [ "$catalog_ts" = "true" ] || \
        fail "case $case_name: expected catalog stacks.typescript=true for ts-node layout, got $catalog_ts"
      [ "$catalog_js" = "true" ] || \
        fail "case $case_name: expected catalog stacks.javascript=true for ts-node layout, got $catalog_js"

      # TS graph artifacts must exist and be non-empty
      ts_graph_dir="$resolved_output/audit_index/llmcc/ts"
      assert_nonempty_file "$ts_graph_dir/depth2.dot"
      assert_nonempty_file "$ts_graph_dir/depth3.dot"
      assert_nonempty_file "$ts_graph_dir/depth3_topk.dot"
    elif [ "$repo_layout" = "js-only" ]; then
      [ "$catalog_rust" = "false" ] || \
        fail "case $case_name: expected catalog stacks.rust=false for js-only layout, got $catalog_rust"
      [ "$catalog_ts" = "false" ] || \
        fail "case $case_name: expected catalog stacks.typescript=false for js-only layout, got $catalog_ts"
      [ "$catalog_js" = "true" ] || \
        fail "case $case_name: expected catalog stacks.javascript=true for js-only layout, got $catalog_js"
    elif [ "$repo_layout" = "root-rust" ]; then
      [ "$catalog_rust" = "true" ] || \
        fail "case $case_name: expected catalog stacks.rust=true for root-rust layout, got $catalog_rust"
    fi

    printf '[run_index_mock_smoke] PASS: %s\n' "$case_name"
    rm -rf "$work_dir"
  )
}

run_case "llmcc-fallback-and-query-format-fallback" \
  "flag" "legacy" "collection" "0" "0" \
  "flag-depth" "collection-update"

run_case "legacy-llmcc-with-index-agentroot" \
  "legacy" "legacy" "index" "1" "0" \
  "legacy-depth-subcommands" "index-subcommand"

run_case "agentroot-index-fallback-to-collection" \
  "flag" "flag" "index" "1" "1" \
  "flag-depth" "collection-update"

run_case "nested-rust-workspace-marker" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "nested-rust"

run_case "nested-rust-mixed-with-js" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "nested-rust-mixed"

run_case "auto-embed-default-on-when-vectors-missing" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "0" "unset" "1" "1" "direct"

run_case "auto-embed-opt-out-when-vectors-missing" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "0" "0" "0" "0" "none"

run_case "js-only-repo-stack-flags" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "js-only"

run_case "ts-node-repo-stack-flags" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "ts-node"

run_case "mode-fast-top-k-80" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "23" "unset" "0" "0" "none" \
  "0" "0" "0" "0" "" "0" \
  "fast" "80"

run_case "mode-deep-top-k-350" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "23" "unset" "0" "0" "none" \
  "0" "0" "0" "0" "" "0" \
  "deep" "350"

run_case "skip-read-plan-no-artifacts" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "23" "unset" "0" "0" "none" \
  "0" "0" "0" "0" "" "0" \
  "standard" "" "1"

run_case "embed-utf8-panic-falls-back-to-bm25" \
  "flag" "flag" "collection" "1" "0" \
  "flag-depth" "collection-update" \
  "root-rust" "0" "unset" "1" "0" "direct" \
  "1" "1" "1" "1" "bm25-only" "1"

# --- Failure-path test: pre-existing audit_index/ preserved, audit_index.tmp/ cleaned up ---
(
  set -euo pipefail

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/vca-smoke.failure-cleanup.XXXXXX")"
  repo_dir="$work_dir/repo"
  output_dir="$work_dir/output"

  # Create a minimal repo (no mock bins → llmcc not found → die)
  mkdir -p "$repo_dir/src"
  cat > "$repo_dir/Cargo.toml" <<'EOF_CARGO'
[package]
name = "mock-fail"
version = "0.1.0"
edition = "2021"
EOF_CARGO

  # Pre-create audit_index/ with sentinel
  mkdir -p "$output_dir/audit_index"
  printf 'survivor\n' > "$output_dir/audit_index/.pre_existing_marker"

  # Run without mock bins on PATH — llmcc check will die
  # Use a clean PATH without mock bins
  if PATH="/usr/bin:/bin" bash "$RUN_INDEX_SCRIPT" \
    --repo "$repo_dir" \
    --output "$output_dir" \
    --mode standard >/dev/null 2>&1; then
    fail "failure-cleanup: expected run_index.sh to fail when llmcc is missing"
  fi

  # Assert: pre-existing audit_index/ is preserved
  if [ ! -f "$output_dir/audit_index/.pre_existing_marker" ]; then
    fail "failure-cleanup: pre-existing audit_index/ was destroyed on failure"
  fi

  # Assert: audit_index.tmp/ is cleaned up
  if [ -d "$output_dir/audit_index.tmp" ]; then
    fail "failure-cleanup: audit_index.tmp/ still exists after failure — cleanup trap did not run"
  fi

  printf '[run_index_mock_smoke] PASS: failure-cleanup (pre-existing index preserved, tmp cleaned)\n'
  rm -rf "$work_dir"
)

# Shellcheck gate for pipeline scripts and shared libraries
PIPELINE_SCRIPTS=(
  "$ROOT_DIR/vibe-code-audit/scripts/_lib.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/run_index.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/build_derived_artifacts.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/build_read_plan.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/run_agentroot_embed.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/render_system_map.sh"
  "$ROOT_DIR/vibe-code-audit/scripts/render_report_pdf.sh"
)
if command -v shellcheck >/dev/null 2>&1; then
  sc_fail=0
  for script in "${PIPELINE_SCRIPTS[@]}"; do
    if ! shellcheck -x -S warning "$script" >/dev/null 2>&1; then
      printf '[run_index_mock_smoke] WARN: shellcheck found warnings in %s\n' "$(basename "$script")" >&2
      sc_fail=1
    fi
  done
  if [ "$sc_fail" -eq 0 ]; then
    printf '[run_index_mock_smoke] PASS: shellcheck (no new warnings)\n'
  fi
else
  printf '[run_index_mock_smoke] SKIP: shellcheck not installed — install via "brew install shellcheck"\n' >&2
fi

printf '[run_index_mock_smoke] All smoke cases passed.\n'
