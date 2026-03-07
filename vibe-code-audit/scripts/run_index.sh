#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="run_index"
# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'USAGE'
Run deterministic preflight + indexing for vibe-code-audit.

Usage:
  run_index.sh --repo <repo_path> [--output <output_dir>] [--mode fast|standard|deep] [--top-k <n>] [--skip-read-plan]

Options:
  --repo     Path to target repository (required)
  --output   Path to audit output directory root (optional)
             Default: <repo>/vibe-code-audit/<UTC-timestamp>
  --mode     fast | standard | deep (default: standard)
  --top-k    Override PageRank top-k value
  --skip-read-plan  Do not auto-run build_read_plan.sh
  --help     Show this help

This script writes:
  <output_dir>/audit_index.tmp/
  <output_dir>/audit_index.tmp/derived/catalog.json
  <output_dir>/audit_index.tmp/derived/hotspots.json
  <output_dir>/audit_index.tmp/derived/dup_clusters.md

Machine-readable output:
  OUTPUT_DIR=<resolved absolute output dir>

Environment:
  VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0
    Disable automatic `agentroot embed` attempts when embeddings are missing
    (default: enabled).
  VIBE_CODE_AUDIT_EMBED_START_LOCAL=1
    When auto-embed is enabled, allow local llama-server bootstrapping.
  VIBE_CODE_AUDIT_EMBED_KEEP_SERVER=0|1
    Keep helper-started local embedding server alive until retrieval validation
    completes in this script (default in this script: 1).
  VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS=<n>
    Passed to the embed helper for local server health wait budget
    (default in helper: 60s).
  VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL=1
    Allow helper script to download the default nomic GGUF model when missing.
  VIBE_CODE_AUDIT_RETRIEVAL_STRICT=1
    Fail the run when both retrieval checks fail, even if embed instability is
    detected (default: 0, degrade to BM25-only when possible).
USAGE
}

kv_from_file() {
  file="$1"
  key="$2"
  value="$(sed -n "s/^${key}=//p" "$file" | tail -n1)"
  printf '%s\n' "$value"
}

REPO_PATH=""
OUTPUT_DIR=""
MODE="standard"
TOP_K=""
SKIP_READ_PLAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      [ $# -ge 2 ] || die "--repo requires a value"
      REPO_PATH="$2"
      shift 2
      ;;
    --output)
      [ $# -ge 2 ] || die "--output requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --mode)
      [ $# -ge 2 ] || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --top-k)
      [ $# -ge 2 ] || die "--top-k requires a value"
      TOP_K="$2"
      shift 2
      ;;
    --skip-read-plan)
      SKIP_READ_PLAN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[ -n "$REPO_PATH" ] || die "--repo is required"
[ -d "$REPO_PATH" ] || die "repo path not found: $REPO_PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TOP_K" ]; then
  case "$MODE" in
    fast) TOP_K="80" ;;
    standard) TOP_K="200" ;;
    deep) TOP_K="350" ;;
    *) die "invalid mode: $MODE (expected fast|standard|deep)" ;;
  esac
fi

case "$TOP_K" in
  ''|*[!0-9]*) die "--top-k must be a positive integer" ;;
esac

if ! command -v llmcc >/dev/null 2>&1; then
  die "llmcc is not installed or not on PATH"
fi
if ! command -v agentroot >/dev/null 2>&1; then
  die "agentroot is not installed or not on PATH"
fi

LLMCC_VERSION="$(llmcc --version)"
AGENTROOT_VERSION="$(agentroot --version)"

REPO_PATH_ABS="$(cd "$REPO_PATH" && pwd)"

if [ -z "$OUTPUT_DIR" ]; then
  TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  OUTPUT_DIR="$REPO_PATH_ABS/vibe-code-audit/$TIMESTAMP"
fi

OUTPUT_DIR_ABS="$(cd "$REPO_PATH_ABS" && resolve_output_dir "$OUTPUT_DIR")"

AUDIT_INDEX_DIR="$OUTPUT_DIR_ABS/audit_index.tmp"
RUST_OUT_DIR="$AUDIT_INDEX_DIR/llmcc/rust"
TS_OUT_DIR="$AUDIT_INDEX_DIR/llmcc/ts"
AGENTROOT_OUT_DIR="$AUDIT_INDEX_DIR/agentroot"
DERIVED_OUT_DIR="$AUDIT_INDEX_DIR/derived"

EMBED_SERVER_PID=""
cleanup_embed_server() {
  if [ -n "${EMBED_SERVER_PID:-}" ]; then
    kill "$EMBED_SERVER_PID" >/dev/null 2>&1 || true
    EMBED_SERVER_PID=""
  fi
}
trap cleanup_embed_server EXIT INT TERM

log "repo: $REPO_PATH_ABS"
log "output: $OUTPUT_DIR_ABS"
log "mode: $MODE (top-k=$TOP_K)"

rm -rf "$AUDIT_INDEX_DIR"
mkdir -p "$RUST_OUT_DIR" "$TS_OUT_DIR" "$AGENTROOT_OUT_DIR" "$DERIVED_OUT_DIR"

# llmcc compatibility: older builds expose depth1/depth2/depth3 subcommands,
# newer builds use --dir/--depth flags.
if llmcc --help 2>/dev/null | grep -q -- '--dir <DIR>'; then
  LLMCC_MODE="flag-depth"
else
  LLMCC_MODE="legacy-depth-subcommands"
fi
log "llmcc mode: $LLMCC_MODE"

run_llmcc_legacy_graph() {
  depth="$1"
  out="$2"
  topk="${3:-}"

  if [ "$depth" = "3" ] && [ -n "$topk" ]; then
    llmcc depth3 --pagerank-top-k "$topk" -o "$out"
  else
    llmcc "depth${depth}" -o "$out"
  fi
}

run_llmcc_flag_graph() {
  lang="$1"
  depth="$2"
  out="$3"
  topk="${4:-}"

  if [ -n "$topk" ]; then
    llmcc --dir "$REPO_PATH_ABS" --lang "$lang" --graph --depth "$depth" --pagerank-top-k "$topk" -o "$out"
  else
    llmcc --dir "$REPO_PATH_ABS" --lang "$lang" --graph --depth "$depth" -o "$out"
  fi
}

run_llmcc_graph() {
  lang="$1"
  depth="$2"
  out="$3"
  topk="${4:-}"

  if [ "$LLMCC_MODE" = "legacy-depth-subcommands" ]; then
    if run_llmcc_legacy_graph "$depth" "$out" "$topk"; then
      return 0
    fi
    warn "llmcc legacy subcommand mode failed for depth $depth; retrying flag-depth syntax"
    if run_llmcc_flag_graph "$lang" "$depth" "$out" "$topk"; then
      LLMCC_MODE="flag-depth"
      log "llmcc mode switched to flag-depth"
      return 0
    fi
  else
    if run_llmcc_flag_graph "$lang" "$depth" "$out" "$topk"; then
      return 0
    fi
    warn "llmcc flag-depth mode failed for depth $depth; retrying legacy subcommands"
    if run_llmcc_legacy_graph "$depth" "$out" "$topk"; then
      LLMCC_MODE="legacy-depth-subcommands"
      log "llmcc mode switched to legacy-depth-subcommands"
      return 0
    fi
  fi

  die "llmcc failed for lang=$lang depth=$depth"
}

pushd "$REPO_PATH_ABS" >/dev/null

repo_has_file_named() {
  name="$1"
  # shellcheck disable=SC2046
  if find . \( $(exclude_find_prune_args) \) -prune \
    -o -type f -name "$name" -print -quit | grep -q .; then
    return 0
  fi
  return 1
}

HAS_RUST=0
HAS_TS=0
HAS_JS=0
if [ -f Cargo.toml ] || repo_has_file_named "Cargo.toml"; then
  HAS_RUST=1
fi
if [ -f tsconfig.json ] || repo_has_file_named "tsconfig.json"; then
  HAS_TS=1
fi
if [ -f package.json ] || repo_has_file_named "package.json"; then
  HAS_JS=1
fi

if [ "$HAS_RUST" -eq 1 ]; then
  log "Running llmcc Rust graphs"
  run_llmcc_graph "rust" 1 "$RUST_OUT_DIR/depth1.dot"
  run_llmcc_graph "rust" 2 "$RUST_OUT_DIR/depth2.dot"
  run_llmcc_graph "rust" 3 "$RUST_OUT_DIR/depth3.dot"
  run_llmcc_graph "rust" 3 "$RUST_OUT_DIR/depth3_topk.dot" "$TOP_K"
  test -s "$RUST_OUT_DIR/depth3_topk.dot"
fi

if [ "$HAS_TS" -eq 1 ]; then
  log "Running llmcc TypeScript graphs"
  run_llmcc_graph "typescript" 2 "$TS_OUT_DIR/depth2.dot"
  run_llmcc_graph "typescript" 3 "$TS_OUT_DIR/depth3.dot"
  run_llmcc_graph "typescript" 3 "$TS_OUT_DIR/depth3_topk.dot" "$TOP_K"
  test -s "$TS_OUT_DIR/depth3_topk.dot"
fi

AGENTROOT_DB_PATH="$AGENTROOT_OUT_DIR/index.sqlite"
export AGENTROOT_DB="$AGENTROOT_DB_PATH"
log "agentroot db: $AGENTROOT_DB_PATH"

run_agentroot_query_check() {
  query="$1"
  out="$2"

  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot query "$query" --format json > "$out" 2>&1; then
    return 0
  fi
  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot query "$query" > "$out" 2>&1; then
    return 0
  fi
  return 1
}

run_agentroot_status_check() {
  out="$1"

  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot status --format json > "$out" 2>&1; then
    return 0
  fi
  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot status > "$out" 2>&1; then
    return 0
  fi
  return 1
}

run_agentroot_vsearch_check() {
  query="$1"
  out="$2"

  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot vsearch "$query" --format json > "$out" 2>&1; then
    return 0
  fi
  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot vsearch "$query" > "$out" 2>&1; then
    return 0
  fi
  return 1
}

attempt_agentroot_embed() {
  if [ "${VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED:-1}" != "1" ]; then
    return 0
  fi
  if [ "$AGENTROOT_EMBEDDED_COUNT" -gt 0 ]; then
    return 0
  fi

  EMBED_ATTEMPTED=1
  log "Attempting agentroot embed (VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=${VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED:-1})"

  EMBED_HELPER_SCRIPT="$SCRIPT_DIR/run_agentroot_embed.sh"
  EMBED_RUNNER_OUT="$AGENTROOT_OUT_DIR/embed_runner.txt"

  if [ -x "$EMBED_HELPER_SCRIPT" ]; then
    EMBED_KEEP_SERVER="${VIBE_CODE_AUDIT_EMBED_KEEP_SERVER:-1}"
    if VIBE_CODE_AUDIT_EMBED_KEEP_SERVER="$EMBED_KEEP_SERVER" \
      bash "$EMBED_HELPER_SCRIPT" --db "$AGENTROOT_DB_PATH" --output-dir "$AGENTROOT_OUT_DIR" >"$EMBED_RUNNER_OUT" 2>&1; then
      EMBED_OK=1
    else
      warn "agentroot embed helper did not produce embeddings (see $EMBED_RUNNER_OUT)"
      warn "Audit will continue with BM25-only search — this is normal without a local embedding server"
    fi
    EMBED_BACKEND_CANDIDATE="$(kv_from_file "$EMBED_RUNNER_OUT" "EMBED_BACKEND")"
    if [ -n "$EMBED_BACKEND_CANDIDATE" ]; then
      EMBED_BACKEND="$EMBED_BACKEND_CANDIDATE"
    fi
    EMBED_UTF8_PANIC_CANDIDATE="$(kv_from_file "$EMBED_RUNNER_OUT" "EMBED_UTF8_PANIC")"
    if [ "$EMBED_UTF8_PANIC_CANDIDATE" = "1" ]; then
      EMBED_UTF8_PANIC=1
    fi
    EMBED_SERVER_PID_CANDIDATE="$(kv_from_file "$EMBED_RUNNER_OUT" "EMBED_SERVER_PID")"
    if [ -n "$EMBED_SERVER_PID_CANDIDATE" ] && printf '%s' "$EMBED_SERVER_PID_CANDIDATE" | grep -Eq '^[0-9]+$'; then
      EMBED_SERVER_PID="$EMBED_SERVER_PID_CANDIDATE"
    fi
  else
    warn "embed helper script is missing: $EMBED_HELPER_SCRIPT"
    if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot embed > "$AGENTROOT_OUT_DIR/embed.txt" 2>&1; then
      EMBED_OK=1
      EMBED_BACKEND="direct"
    else
      warn "agentroot embed failed (see $AGENTROOT_OUT_DIR/embed.txt)"
    fi
  fi

  if run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json"; then
    AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
    AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"
  else
    warn "agentroot status check failed after embed attempt (see $AGENTROOT_OUT_DIR/status.json)"
  fi

  if [ "$EMBED_UTF8_PANIC" -eq 1 ]; then
    warn "Detected agentroot UTF-8 chunking panic; forcing BM25-only fallback behavior"
  fi
}

# agentroot compatibility: older builds expose `index`; newer builds use
# collection add + update.
if agentroot index --help >/dev/null 2>&1; then
  AGENTROOT_MODE="index-subcommand"
else
  AGENTROOT_MODE="collection-update"
fi
log "agentroot mode: $AGENTROOT_MODE"

AGENTROOT_COLLECTION=""
AGENTROOT_COLLECTIONS=()
AGENTROOT_DOC_COUNT=0
AGENTROOT_EMBEDDED_COUNT=0
RETRIEVAL_MODE="unknown"
QUERY_OK=0
VSEARCH_OK=0
EMBED_ATTEMPTED=0
EMBED_OK=0
EMBED_BACKEND="none"
EMBED_UTF8_PANIC=0
RETRIEVAL_STRICT="${VIBE_CODE_AUDIT_RETRIEVAL_STRICT:-0}"

if [ "$AGENTROOT_MODE" = "index-subcommand" ]; then
  log "Running agentroot index"
  # shellcheck disable=SC2046
  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot index . \
    $(exclude_agentroot_flags) \
    --output "$AGENTROOT_OUT_DIR"; then
    test -d "$AGENTROOT_OUT_DIR"
    if run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json"; then
      AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
      AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"
    else
      warn "agentroot status check failed (see $AGENTROOT_OUT_DIR/status.json)"
    fi

    attempt_agentroot_embed

    log "Running retrieval validation"
    if run_agentroot_query_check "retry backoff" "$AGENTROOT_OUT_DIR/query_check.txt"; then
      QUERY_OK=1
    else
      warn "agentroot query check failed (see $AGENTROOT_OUT_DIR/query_check.txt)"
    fi
    if run_agentroot_vsearch_check "permission check" "$AGENTROOT_OUT_DIR/vsearch_check.txt"; then
      VSEARCH_OK=1
    else
      warn "agentroot vsearch check failed (see $AGENTROOT_OUT_DIR/vsearch_check.txt)"
    fi
  else
    warn "agentroot index-subcommand mode failed; falling back to collection-update mode"
    AGENTROOT_MODE="collection-update"
  fi
fi

if [ "$AGENTROOT_MODE" = "collection-update" ]; then
  AGENTROOT_COLLECTION_PREFIX="vca-$(basename "$REPO_PATH_ABS")-$(date -u +%Y%m%d%H%M%S)"
  COLLECTIONS_TSV="$AGENTROOT_OUT_DIR/collections.tsv"
  : > "$COLLECTIONS_TSV"

  MASKS=()
  if [ "$HAS_RUST" -eq 1 ]; then
    MASKS+=( '**/*.rs' '**/*.toml' )
  fi
  if [ "$HAS_TS" -eq 1 ] || [ "$HAS_JS" -eq 1 ]; then
    MASKS+=( '**/*.ts' '**/*.tsx' '**/*.js' '**/*.jsx' '**/*.mjs' '**/*.cjs' '**/*.json' )
  fi
  if [ "${#MASKS[@]}" -eq 0 ]; then
    MASKS+=( '**/*.py' '**/*.go' '**/*.java' '**/*.md' )
  fi

  idx=0
  for mask in "${MASKS[@]}"; do
    idx=$((idx + 1))
    name="${AGENTROOT_COLLECTION_PREFIX}-m${idx}"
    add_log="$AGENTROOT_OUT_DIR/collection_add_${idx}.txt"
    log "Adding agentroot collection: $name (mask=$mask)"
    if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot collection add "$REPO_PATH_ABS" \
      --name "$name" \
      --mask "$mask" > "$add_log" 2>&1; then
      AGENTROOT_COLLECTIONS+=( "$name" )
      printf '%s\t%s\n' "$name" "$mask" >> "$COLLECTIONS_TSV"
    else
      warn "agentroot collection add failed for mask $mask (see $add_log)"
    fi
  done

  [ "${#AGENTROOT_COLLECTIONS[@]}" -gt 0 ] || die "agentroot collection add failed for all masks"
  AGENTROOT_COLLECTION="${AGENTROOT_COLLECTIONS[0]}"
  printf '%s\n' "${AGENTROOT_COLLECTIONS[@]}" > "$AGENTROOT_OUT_DIR/collection_names.txt"

  log "Updating agentroot collections"
  AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot update > "$AGENTROOT_OUT_DIR/update.txt" 2>&1 || \
    die "agentroot update failed (see $AGENTROOT_OUT_DIR/update.txt)"

  run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json" || \
    die "agentroot status failed (see $AGENTROOT_OUT_DIR/status.json)"
  AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
  AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"

  if [ "$AGENTROOT_DOC_COUNT" -eq 0 ]; then
    warn "agentroot indexed zero documents from targeted masks; retrying with fallback mask '**/*'"
    fallback_name="${AGENTROOT_COLLECTION_PREFIX}-all"
    fallback_log="$AGENTROOT_OUT_DIR/collection_add_fallback.txt"
    AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot collection add "$REPO_PATH_ABS" \
      --name "$fallback_name" \
      --mask '**/*' > "$fallback_log" 2>&1 || \
      die "agentroot fallback collection add failed (see $fallback_log)"
    AGENTROOT_COLLECTIONS+=( "$fallback_name" )
    printf '%s\t%s\n' "$fallback_name" '**/*' >> "$COLLECTIONS_TSV"
    AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot update > "$AGENTROOT_OUT_DIR/update_fallback.txt" 2>&1 || \
      die "agentroot fallback update failed (see $AGENTROOT_OUT_DIR/update_fallback.txt)"
    run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json" || \
      die "agentroot status failed after fallback (see $AGENTROOT_OUT_DIR/status.json)"
    AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
    AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"
  fi

  [ "$AGENTROOT_DOC_COUNT" -gt 0 ] || die "agentroot indexed zero documents after fallback"

  attempt_agentroot_embed

  log "Running retrieval validation"
  if run_agentroot_query_check "retry backoff" "$AGENTROOT_OUT_DIR/query_check.txt"; then
    QUERY_OK=1
  else
    warn "agentroot query check failed (see $AGENTROOT_OUT_DIR/query_check.txt)"
  fi
  if run_agentroot_vsearch_check "permission check" "$AGENTROOT_OUT_DIR/vsearch_check.txt"; then
    VSEARCH_OK=1
  else
    warn "agentroot vsearch check failed (see $AGENTROOT_OUT_DIR/vsearch_check.txt)"
  fi
fi

test -s "$AGENTROOT_OUT_DIR/query_check.txt" || die "query_check.txt was not written"
test -s "$AGENTROOT_OUT_DIR/vsearch_check.txt" || die "vsearch_check.txt was not written"

if [ "$QUERY_OK" -ne 1 ] && [ "$VSEARCH_OK" -ne 1 ]; then
  RETRIEVAL_TRANSPORT_ERROR=0
  if has_pattern_in_files 'localhost:8000/v1/embeddings|/v1/embeddings|Connection refused|error sending request for url.*embeddings' \
    "$AGENTROOT_OUT_DIR/query_check.txt" "$AGENTROOT_OUT_DIR/vsearch_check.txt"; then
    RETRIEVAL_TRANSPORT_ERROR=1
  fi

  if [ "$AGENTROOT_DOC_COUNT" -gt 0 ] && \
    { [ "$EMBED_UTF8_PANIC" -eq 1 ] || [ "$RETRIEVAL_TRANSPORT_ERROR" -eq 1 ] || [ "$EMBED_ATTEMPTED" -eq 1 ]; }; then
    if [ "$RETRIEVAL_STRICT" = "1" ]; then
      die "retrieval checks failed (query + vsearch) in strict mode"
    fi
    warn "retrieval checks failed; continuing with BM25-only mode due embed instability"
  else
    die "retrieval checks failed (query + vsearch)"
  fi
fi

if [ "$EMBED_UTF8_PANIC" -eq 1 ]; then
  RETRIEVAL_MODE="bm25-only"
  warn "Vector retrieval disabled due agentroot UTF-8 chunking panic"
elif [ "$VSEARCH_OK" -eq 1 ] && [ "$AGENTROOT_EMBEDDED_COUNT" -gt 0 ] && \
  ! grep -qi 'No vector embeddings found' "$AGENTROOT_OUT_DIR/vsearch_check.txt"; then
  RETRIEVAL_MODE="hybrid"
else
  RETRIEVAL_MODE="bm25-only"
  warn "Vector embeddings unavailable; continuing with BM25-only retrieval"
fi

cleanup_embed_server

popd >/dev/null

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MODES_ENABLED="[]"
if [ "$HAS_RUST" -eq 1 ] && [ "$HAS_TS" -eq 1 ]; then
  MODES_ENABLED='["rust","typescript"]'
elif [ "$HAS_RUST" -eq 1 ]; then
  MODES_ENABLED='["rust"]'
elif [ "$HAS_TS" -eq 1 ]; then
  MODES_ENABLED='["typescript"]'
else
  MODES_ENABLED='["generic"]'
fi

if [ -n "$AGENTROOT_COLLECTION" ]; then
  AGENTROOT_COLLECTION_JSON="\"$(json_escape "$AGENTROOT_COLLECTION")\""
else
  AGENTROOT_COLLECTION_JSON="null"
fi

AGENTROOT_COLLECTIONS_JSON="[]"
if [ "${#AGENTROOT_COLLECTIONS[@]}" -gt 0 ]; then
  AGENTROOT_COLLECTIONS_JSON="["
  sep=""
  for c in "${AGENTROOT_COLLECTIONS[@]}"; do
    AGENTROOT_COLLECTIONS_JSON="${AGENTROOT_COLLECTIONS_JSON}${sep}\"$(json_escape "$c")\""
    sep=","
  done
  AGENTROOT_COLLECTIONS_JSON="${AGENTROOT_COLLECTIONS_JSON}]"
fi

MANIFEST_PATH="$AUDIT_INDEX_DIR/manifest.json"
cat > "$MANIFEST_PATH" <<MANIFEST
{
  "generated_at": "$(json_escape "$GENERATED_AT")",
  "repo_root": "$(json_escape "$REPO_PATH_ABS")",
  "output_dir": "$(json_escape "$OUTPUT_DIR_ABS")",
  "llmcc_version": "$(json_escape "$LLMCC_VERSION")",
  "llmcc_mode": "$(json_escape "$LLMCC_MODE")",
  "agentroot_version": "$(json_escape "$AGENTROOT_VERSION")",
  "agentroot_mode": "$(json_escape "$AGENTROOT_MODE")",
  "agentroot_db": "$(json_escape "$AGENTROOT_DB_PATH")",
  "agentroot_collection": $AGENTROOT_COLLECTION_JSON,
  "agentroot_collections": $AGENTROOT_COLLECTIONS_JSON,
  "agentroot_document_count": $AGENTROOT_DOC_COUNT,
  "agentroot_embedded_count": $AGENTROOT_EMBEDDED_COUNT,
  "agentroot_embed_attempted": $EMBED_ATTEMPTED,
  "agentroot_embed_ok": $EMBED_OK,
  "agentroot_embed_backend": "$(json_escape "$EMBED_BACKEND")",
  "agentroot_embed_utf8_panic": $EMBED_UTF8_PANIC,
  "retrieval_mode": "$(json_escape "$RETRIEVAL_MODE")",
  "retrieval_query_ok": $QUERY_OK,
  "retrieval_vsearch_ok": $VSEARCH_OK,
  "exclude_patterns": $(exclude_dirs_json_array),
  "modes_enabled": $MODES_ENABLED,
  "pagerank_top_k": $TOP_K,
  "budget_mode": "$(json_escape "$MODE")",
  "command_runner": "vibe-code-audit/scripts/run_index.sh"
}
MANIFEST

log "Wrote $MANIFEST_PATH"

DERIVED_SCRIPT="$SCRIPT_DIR/build_derived_artifacts.sh"
if [ -x "$DERIVED_SCRIPT" ]; then
  log "Building derived artifacts"
  bash "$DERIVED_SCRIPT" --repo "$REPO_PATH_ABS" --output "$AUDIT_INDEX_DIR" --mode "$MODE" --top-k "$TOP_K" \
    --has-rust "$HAS_RUST" --has-ts "$HAS_TS" --has-js "$HAS_JS"
  test -s "$DERIVED_OUT_DIR/catalog.json" || die "catalog.json was not generated"
  test -s "$DERIVED_OUT_DIR/hotspots.json" || die "hotspots.json was not generated"
  test -s "$DERIVED_OUT_DIR/dup_clusters.md" || die "dup_clusters.md was not generated"
else
  warn "Derived artifacts script not found or not executable: $DERIVED_SCRIPT"
fi

if [ "$SKIP_READ_PLAN" -eq 0 ]; then
  READ_PLAN_SCRIPT="$SCRIPT_DIR/build_read_plan.sh"
  if [ -x "$READ_PLAN_SCRIPT" ]; then
    log "Running read plan builder"
    bash "$READ_PLAN_SCRIPT" --repo "$REPO_PATH_ABS" --output "$AUDIT_INDEX_DIR" --mode "$MODE"
    test -e "$DERIVED_OUT_DIR/read_plan.tsv" || die "read_plan.tsv was not generated"
    test -s "$DERIVED_OUT_DIR/read_plan.md" || die "read_plan.md was not generated"
  else
    warn "Read plan script not found or not executable: $READ_PLAN_SCRIPT"
  fi
fi

log "Indexing complete"
printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR_ABS"
