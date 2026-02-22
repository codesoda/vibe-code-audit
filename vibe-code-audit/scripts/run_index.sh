#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="run_index.sh"

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
  <output_dir>/audit_index/

Machine-readable output:
  OUTPUT_DIR=<resolved absolute output dir>

Environment:
  VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=1
    Attempt `agentroot embed` automatically when embeddings are missing.
USAGE
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
}

warn() {
  printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_int_from_file() {
  file="$1"
  key="$2"
  value="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "$file" | head -n1)"
  if [ -z "$value" ]; then
    printf '0\n'
  else
    printf '%s\n' "$value"
  fi
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

OUTPUT_DIR_ABS="$OUTPUT_DIR"
case "$OUTPUT_DIR_ABS" in
  /*)
    mkdir -p "$OUTPUT_DIR_ABS"
    OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR_ABS" && pwd)"
    ;;
  *)
    mkdir -p "$REPO_PATH_ABS/$OUTPUT_DIR_ABS"
    OUTPUT_DIR_ABS="$(cd "$REPO_PATH_ABS/$OUTPUT_DIR_ABS" && pwd)"
    ;;
esac

AUDIT_INDEX_DIR="$OUTPUT_DIR_ABS/audit_index"
RUST_OUT_DIR="$AUDIT_INDEX_DIR/llmcc/rust"
TS_OUT_DIR="$AUDIT_INDEX_DIR/llmcc/ts"
AGENTROOT_OUT_DIR="$AUDIT_INDEX_DIR/agentroot"
DERIVED_OUT_DIR="$AUDIT_INDEX_DIR/derived"

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

HAS_RUST=0
HAS_TS=0
if [ -f Cargo.toml ]; then
  HAS_RUST=1
fi
if [ -f tsconfig.json ]; then
  HAS_TS=1
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

if [ "$AGENTROOT_MODE" = "index-subcommand" ]; then
  log "Running agentroot index"
  if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot index . \
    --exclude .git \
    --exclude node_modules \
    --exclude target \
    --exclude dist \
    --exclude build \
    --exclude .next \
    --exclude coverage \
    --output "$AGENTROOT_OUT_DIR"; then
    test -d "$AGENTROOT_OUT_DIR"
    if run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json"; then
      AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
      AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"
    else
      warn "agentroot status check failed (see $AGENTROOT_OUT_DIR/status.json)"
    fi

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
  if [ "$HAS_TS" -eq 1 ] || [ -f package.json ]; then
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

  if [ "${VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED:-0}" = "1" ] && [ "$AGENTROOT_EMBEDDED_COUNT" -eq 0 ]; then
    log "Attempting agentroot embed (VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=1)"
    if AGENTROOT_DB="$AGENTROOT_DB_PATH" agentroot embed > "$AGENTROOT_OUT_DIR/embed.txt" 2>&1; then
      if run_agentroot_status_check "$AGENTROOT_OUT_DIR/status.json"; then
        AGENTROOT_DOC_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "document_count")"
        AGENTROOT_EMBEDDED_COUNT="$(json_int_from_file "$AGENTROOT_OUT_DIR/status.json" "embedded_count")"
      fi
    else
      warn "agentroot embed failed (see $AGENTROOT_OUT_DIR/embed.txt)"
    fi
  fi

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

[ "$QUERY_OK" -eq 1 ] || [ "$VSEARCH_OK" -eq 1 ] || die "retrieval checks failed (query + vsearch)"
test -s "$AGENTROOT_OUT_DIR/query_check.txt" || die "query_check.txt was not written"
test -s "$AGENTROOT_OUT_DIR/vsearch_check.txt" || die "vsearch_check.txt was not written"

if [ "$AGENTROOT_EMBEDDED_COUNT" -gt 0 ] && ! grep -qi 'No vector embeddings found' "$AGENTROOT_OUT_DIR/vsearch_check.txt"; then
  RETRIEVAL_MODE="hybrid"
else
  RETRIEVAL_MODE="bm25-only"
  warn "Vector embeddings unavailable; continuing with BM25-only retrieval"
fi

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
  "retrieval_mode": "$(json_escape "$RETRIEVAL_MODE")",
  "retrieval_query_ok": $QUERY_OK,
  "retrieval_vsearch_ok": $VSEARCH_OK,
  "exclude_patterns": [".git", "node_modules", "target", "dist", "build", ".next", "coverage"],
  "modes_enabled": $MODES_ENABLED,
  "pagerank_top_k": $TOP_K,
  "budget_mode": "$(json_escape "$MODE")",
  "command_runner": "vibe-code-audit/scripts/run_index.sh"
}
MANIFEST

log "Wrote $MANIFEST_PATH"

if [ "$SKIP_READ_PLAN" -eq 0 ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  READ_PLAN_SCRIPT="$SCRIPT_DIR/build_read_plan.sh"
  if [ -x "$READ_PLAN_SCRIPT" ]; then
    log "Running read plan builder"
    bash "$READ_PLAN_SCRIPT" --repo "$REPO_PATH_ABS" --output "$OUTPUT_DIR_ABS" --mode "$MODE"
    test -e "$DERIVED_OUT_DIR/read_plan.tsv" || die "read_plan.tsv was not generated"
    test -s "$DERIVED_OUT_DIR/read_plan.md" || die "read_plan.md was not generated"
  else
    warn "Read plan script not found or not executable: $READ_PLAN_SCRIPT"
  fi
fi

log "Indexing complete"
printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR_ABS"
