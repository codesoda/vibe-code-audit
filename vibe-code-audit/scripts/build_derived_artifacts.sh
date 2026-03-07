#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="build_derived_artifacts"
# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'USAGE'
Build deterministic derived artifacts used by vibe-code-audit analysis.

Usage:
  build_derived_artifacts.sh --repo <repo_path> --output <output_dir> [--mode <fast|standard|deep>] [--top-k <n>]

Writes:
  <output_dir>/audit_index/derived/catalog.json
  <output_dir>/audit_index/derived/hotspots.json
  <output_dir>/audit_index/derived/dup_clusters.md
USAGE
}

REPO_PATH=""
OUTPUT_DIR=""
MODE="standard"
TOP_K="0"
FLAG_HAS_RUST=""
FLAG_HAS_TS=""
FLAG_HAS_JS=""

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
    --has-rust)
      [ $# -ge 2 ] || die "--has-rust requires a value"
      FLAG_HAS_RUST="$2"
      shift 2
      ;;
    --has-ts)
      [ $# -ge 2 ] || die "--has-ts requires a value"
      FLAG_HAS_TS="$2"
      shift 2
      ;;
    --has-js)
      [ $# -ge 2 ] || die "--has-js requires a value"
      FLAG_HAS_JS="$2"
      shift 2
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
[ -n "$OUTPUT_DIR" ] || die "--output is required"
[ -d "$REPO_PATH" ] || die "repo path not found: $REPO_PATH"

# Validate --has-* flags: must be 0 or 1 if provided
if [ -n "$FLAG_HAS_RUST" ]; then
  case "$FLAG_HAS_RUST" in 0|1) ;; *) die "--has-rust: invalid value '$FLAG_HAS_RUST' (expected 0 or 1)" ;; esac
fi
if [ -n "$FLAG_HAS_TS" ]; then
  case "$FLAG_HAS_TS" in 0|1) ;; *) die "--has-ts: invalid value '$FLAG_HAS_TS' (expected 0 or 1)" ;; esac
fi
if [ -n "$FLAG_HAS_JS" ]; then
  case "$FLAG_HAS_JS" in 0|1) ;; *) die "--has-js: invalid value '$FLAG_HAS_JS' (expected 0 or 1)" ;; esac
fi

REPO_PATH_ABS="$(cd "$REPO_PATH" && pwd)"
OUTPUT_DIR_ABS="$(cd "$REPO_PATH_ABS" && resolve_output_dir "$OUTPUT_DIR")"

AUDIT_INDEX_DIR="$OUTPUT_DIR_ABS/audit_index"
DERIVED_DIR="$AUDIT_INDEX_DIR/derived"
mkdir -p "$DERIVED_DIR"

HOTSPOTS_JSON="$DERIVED_DIR/hotspots.json"
CATALOG_JSON="$DERIVED_DIR/catalog.json"
DUP_CLUSTERS_MD="$DERIVED_DIR/dup_clusters.md"

find_hotspot_dot() {
  candidates=(
    "$AUDIT_INDEX_DIR/llmcc/rust/depth3_topk.dot"
    "$AUDIT_INDEX_DIR/llmcc/ts/depth3_topk.dot"
    "$AUDIT_INDEX_DIR/llmcc/rust/depth3.dot"
    "$AUDIT_INDEX_DIR/llmcc/ts/depth3.dot"
    "$AUDIT_INDEX_DIR/llmcc/rust/depth2.dot"
    "$AUDIT_INDEX_DIR/llmcc/ts/depth2.dot"
    "$AUDIT_INDEX_DIR/llmcc/rust/depth1.dot"
  )

  for candidate in "${candidates[@]}"; do
    if [ -s "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOTSPOT_DOT=""
HOTSPOT_DOT_REL=""

if HOTSPOT_DOT="$(find_hotspot_dot 2>/dev/null)"; then
  HOTSPOT_DOT_REL="${HOTSPOT_DOT#$OUTPUT_DIR_ABS/}"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vca-derived.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PATHS_RAW="$TMP_DIR/hotspot_paths_raw.txt"
COUNTS_TSV="$TMP_DIR/hotspot_counts.tsv"

: > "$PATHS_RAW"
: > "$COUNTS_TSV"

if [ -n "$HOTSPOT_DOT" ] && [ -s "$HOTSPOT_DOT" ]; then
  grep -oE 'path="[^"]+"' "$HOTSPOT_DOT" | \
    sed 's/^path="//; s/"$//' | \
    sed "s|^$REPO_PATH_ABS/||" | \
    cut -d: -f1 | \
    awk 'NF > 0 { print }' > "$PATHS_RAW" || true

  if [ -s "$PATHS_RAW" ]; then
    sort "$PATHS_RAW" | uniq -c | sort -rn | \
      awk '{count=$1; $1=""; sub(/^ +/, "", $0); printf "%s\t%s\n", count, $0}' > "$COUNTS_TSV"
  fi
fi

{
  printf '{\n'
  printf '  "generated_at": "%s",\n' "$(json_escape "$GENERATED_AT")"
  printf '  "source": "vibe-code-audit/scripts/build_derived_artifacts.sh",\n'
  printf '  "mode": "%s",\n' "$(json_escape "$MODE")"
  printf '  "top_k": %s,\n' "$TOP_K"
  if [ -n "$HOTSPOT_DOT_REL" ]; then
    printf '  "hotspot_dot": "%s",\n' "$(json_escape "$HOTSPOT_DOT_REL")"
  else
    printf '  "hotspot_dot": null,\n'
  fi
  printf '  "files_by_symbol_count": [\n'

  if [ -s "$COUNTS_TSV" ]; then
    i=0
    while IFS=$'\t' read -r count file_path; do
      i=$((i + 1))
      if [ "$i" -gt 80 ]; then
        break
      fi

      file_abs="$REPO_PATH_ABS/$file_path"
      line_count="null"
      if [ -f "$file_abs" ]; then
        line_count="$(wc -l < "$file_abs" | tr -d ' ')"
      fi

      if [ "$i" -gt 1 ]; then
        printf ',\n'
      fi

      printf '    {"file": "%s", "symbol_count": %s, "line_count": %s}' \
        "$(json_escape "$file_path")" \
        "$count" \
        "$line_count"
    done < "$COUNTS_TSV"
    printf '\n'
  fi

  printf '  ]\n'
  printf '}\n'
} > "$HOTSPOTS_JSON"

HAS_RUST="false"
HAS_TS="false"
HAS_JS="false"
HAS_FRONTEND="false"
WORKSPACE_DETECTED="false"

if [ -n "$FLAG_HAS_RUST" ]; then
  [ "$FLAG_HAS_RUST" = "1" ] && HAS_RUST="true"
else
  [ -f "$REPO_PATH_ABS/Cargo.toml" ] && HAS_RUST="true"
fi
if [ -n "$FLAG_HAS_TS" ]; then
  [ "$FLAG_HAS_TS" = "1" ] && HAS_TS="true"
else
  [ -f "$REPO_PATH_ABS/tsconfig.json" ] && HAS_TS="true"
fi
if [ -n "$FLAG_HAS_JS" ]; then
  [ "$FLAG_HAS_JS" = "1" ] && HAS_JS="true"
else
  [ -f "$REPO_PATH_ABS/package.json" ] && HAS_JS="true"
fi
[ -d "$REPO_PATH_ABS/web/src" ] && HAS_FRONTEND="true"

if [ -f "$REPO_PATH_ABS/Cargo.toml" ] && grep -Eq '^\[workspace\]' "$REPO_PATH_ABS/Cargo.toml"; then
  WORKSPACE_DETECTED="true"
fi

CRATE_ROWS="$TMP_DIR/crates.tsv"
: > "$CRATE_ROWS"

for cargo_file in "$REPO_PATH_ABS"/crates/*/Cargo.toml; do
  [ -f "$cargo_file" ] || continue
  crate_dir="$(dirname "$cargo_file")"
  crate_name="$(basename "$crate_dir")"
  rust_file_count="0"
  if [ -d "$crate_dir/src" ]; then
    rust_file_count="$(find "$crate_dir/src" -type f -name '*.rs' 2>/dev/null | wc -l | tr -d ' ')"
  fi
  printf '%s\t%s\t%s\n' \
    "$crate_name" \
    "${crate_dir#$REPO_PATH_ABS/}" \
    "$rust_file_count" >> "$CRATE_ROWS"
done

{
  printf '{\n'
  printf '  "generated_at": "%s",\n' "$(json_escape "$GENERATED_AT")"
  printf '  "repo_root": "%s",\n' "$(json_escape "$REPO_PATH_ABS")"
  printf '  "workspace_detected": %s,\n' "$WORKSPACE_DETECTED"
  printf '  "stacks": {\n'
  printf '    "rust": %s,\n' "$HAS_RUST"
  printf '    "typescript": %s,\n' "$HAS_TS"
  printf '    "javascript": %s\n' "$HAS_JS"
  printf '  },\n'
  printf '  "frontend": {\n'
  printf '    "present": %s,\n' "$HAS_FRONTEND"
  if [ "$HAS_FRONTEND" = "true" ]; then
    printf '    "path": "web/src"\n'
  else
    printf '    "path": null\n'
  fi
  printf '  },\n'
  printf '  "crates": [\n'

  if [ -s "$CRATE_ROWS" ]; then
    i=0
    while IFS=$'\t' read -r crate_name crate_path rust_file_count; do
      i=$((i + 1))
      if [ "$i" -gt 1 ]; then
        printf ',\n'
      fi
      printf '    {"name": "%s", "path": "%s", "rust_file_count": %s}' \
        "$(json_escape "$crate_name")" \
        "$(json_escape "$crate_path")" \
        "$rust_file_count"
    done < "$CRATE_ROWS"
    printf '\n'
  fi

  printf '  ]\n'
  printf '}\n'
} > "$CATALOG_JSON"

{
  printf '# Duplication Clusters (Bootstrap)\n\n'
  printf 'Generated by `build_derived_artifacts.sh` during indexing.\n'
  printf 'This bootstrap file is intentionally conservative; semantic clusters are finalized during analysis phases.\n\n'

  if [ -s "$COUNTS_TSV" ]; then
    printf '## Hotspot-derived candidate areas\n\n'
    i=0
    while IFS=$'\t' read -r count file_path; do
      i=$((i + 1))
      if [ "$i" -gt 20 ]; then
        break
      fi
      printf -- '- `%s` (%s symbols in llmcc hotspot graph)\n' "$file_path" "$count"
    done < "$COUNTS_TSV"
    printf '\n'
  else
    printf 'No hotspot symbol-path data was available from llmcc graph artifacts.\n\n'
  fi

  printf '## Next step\n\n'
  printf 'Use `read_plan.tsv` + targeted pattern mining to produce evidence-backed duplication clusters.\n'
} > "$DUP_CLUSTERS_MD"

log "Wrote $HOTSPOTS_JSON"
log "Wrote $CATALOG_JSON"
log "Wrote $DUP_CLUSTERS_MD"
