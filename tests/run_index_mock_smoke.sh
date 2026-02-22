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

  (
    set -euo pipefail

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/vca-smoke.${case_name}.XXXXXX")"
    repo_dir="$work_dir/repo"
    output_dir="$work_dir/output"
    bin_dir="$work_dir/bin"

    if [ "$repo_layout" = "nested-rust" ]; then
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
    export MOCK_AGENTROOT_EMBEDDED_COUNT="23"
    unset VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED

    run_output="$(
      bash "$RUN_INDEX_SCRIPT" \
        --repo "$repo_dir" \
        --output "$output_dir" \
        --mode standard
    )"

    resolved_output="$(printf '%s\n' "$run_output" | sed -n 's/^OUTPUT_DIR=//p' | tail -n1)"
    [ -n "$resolved_output" ] || fail "case $case_name: run_index.sh did not emit OUTPUT_DIR"

    manifest="$resolved_output/audit_index/manifest.json"
    assert_nonempty_file "$manifest"
    assert_nonempty_file "$resolved_output/audit_index/derived/catalog.json"
    assert_nonempty_file "$resolved_output/audit_index/derived/hotspots.json"
    assert_nonempty_file "$resolved_output/audit_index/derived/dup_clusters.md"
    [ -e "$resolved_output/audit_index/derived/read_plan.tsv" ] || \
      fail "case $case_name: expected read_plan.tsv to exist"
    assert_nonempty_file "$resolved_output/audit_index/derived/read_plan.md"

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
    [ "$query_ok" -eq 1 ] || [ "$vsearch_ok" -eq 1 ] || \
      fail "case $case_name: expected at least one retrieval check to pass"

    embed_attempted="$(json_int "$manifest" "agentroot_embed_attempted")"
    embed_ok="$(json_int "$manifest" "agentroot_embed_ok")"
    embed_backend="$(json_string "$manifest" "agentroot_embed_backend")"
    [ "$embed_attempted" -eq 0 ] || \
      fail "case $case_name: expected agentroot_embed_attempted=0"
    [ "$embed_ok" -eq 0 ] || \
      fail "case $case_name: expected agentroot_embed_ok=0"
    [ "$embed_backend" = "none" ] || \
      fail "case $case_name: expected agentroot_embed_backend=none"

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

printf '[run_index_mock_smoke] All smoke cases passed.\n'
