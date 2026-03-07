#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="build_read_plan"
# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'USAGE'
Build a bounded evidence read plan for vibe-code-audit.

Usage:
  build_read_plan.sh --repo <repo_path> --output <output_dir> [--mode fast|standard|deep]

Writes:
  <output_dir>/audit_index/derived/read_plan.tsv
  <output_dir>/audit_index/derived/read_plan.md

TSV columns:
  file_path<TAB>match_line<TAB>start_line<TAB>end_line<TAB>signal
USAGE
}

REPO_PATH=""
OUTPUT_DIR=""
MODE="standard"

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

case "$MODE" in
  fast)
    MAX_SLICES=60
    MAX_FILES=20
    RADIUS=25
    ;;
  standard)
    MAX_SLICES=140
    MAX_FILES=45
    RADIUS=35
    ;;
  deep)
    MAX_SLICES=260
    MAX_FILES=80
    RADIUS=45
    ;;
  *)
    die "invalid mode: $MODE (expected fast|standard|deep)"
    ;;
esac

REPO_PATH_ABS="$(cd "$REPO_PATH" && pwd)"
OUTPUT_DIR_ABS="$(cd "$REPO_PATH_ABS" && resolve_output_dir "$OUTPUT_DIR")"

DERIVED_DIR="$OUTPUT_DIR_ABS/audit_index/derived"
mkdir -p "$DERIVED_DIR"

RAW_MATCHES="$DERIVED_DIR/.read_plan_matches_raw.tsv"
NORMALIZED_MATCHES="$DERIVED_DIR/.read_plan_matches_norm.tsv"
READ_PLAN_TSV="$DERIVED_DIR/read_plan.tsv"
READ_PLAN_MD="$DERIVED_DIR/read_plan.md"

PATTERN='auth|authoriz|permission|validate|schema|retry|backoff|timeout|transaction|idempot|partial write|cache|telemetry|tracing|serialize|deserialize|dto|config|feature flag|error handling|panic|unwrap\('

log "repo: $REPO_PATH_ABS"
log "output: $OUTPUT_DIR_ABS"
log "mode: $MODE"
log "limits: max_slices=$MAX_SLICES max_files=$MAX_FILES radius=$RADIUS"

pushd "$REPO_PATH_ABS" >/dev/null

rg_exclude_args=()
for dir in $EXCLUDE_DIRS; do
  rg_exclude_args+=(--glob "!${dir}/**")
done

grep_exclude_args=()
for dir in $EXCLUDE_DIRS; do
  grep_exclude_args+=(--exclude-dir "$dir")
done

if command -v rg >/dev/null 2>&1; then
  rg -n -S \
    "${rg_exclude_args[@]}" \
    --glob '!**/*.md' \
    --glob '!**/*.txt' \
    --glob '!**/*.lock' \
    --glob '!**/*.svg' \
    --glob '!**/*.png' \
    --glob '!**/*.jpg' \
    --glob '!**/*.jpeg' \
    "$PATTERN" . > "$RAW_MATCHES" || true
else
  grep -R -n -E "${grep_exclude_args[@]}" "$PATTERN" . > "$RAW_MATCHES" || true
fi

popd >/dev/null

if [ ! -s "$RAW_MATCHES" ]; then
  : > "$READ_PLAN_TSV"
  cat > "$READ_PLAN_MD" <<'EOF_MD'
# Read Plan

No high-signal matches were found for the default pattern set.
Proceed using hotspot artifacts and targeted manual probes.
EOF_MD
  log "No pattern matches found; wrote empty read plan"
  exit 0
fi

awk -F: -v OFS='\t' '{
  file=$1
  line=$2
  if (line ~ /^[0-9]+$/) {
    sig=$3
    for (i=4; i<=NF; i++) sig=sig ":" $i
    gsub(/^\./, "", file)
    sub(/^\//, "", file)
    print file, line, sig
  }
}' "$RAW_MATCHES" > "$NORMALIZED_MATCHES"

awk -F'\t' -v OFS='\t' -v radius="$RADIUS" -v max_slices="$MAX_SLICES" -v max_files="$MAX_FILES" '
BEGIN {
  slices=0
  files=0
}
{
  file=$1
  line=$2+0
  sig=$3

  if (!(file in seen_file)) {
    if (files >= max_files) {
      next
    }
    seen_file[file]=1
    files++
  }

  if (slices >= max_slices) {
    next
  }

  start=line-radius
  if (start < 1) start=1
  end=line+radius

  key=file ":" start ":" end
  if (key in seen_slice) {
    next
  }
  seen_slice[key]=1
  slices++

  print file, line, start, end, sig
}
' "$NORMALIZED_MATCHES" > "$READ_PLAN_TSV"

TOTAL_SLICES="$(wc -l < "$READ_PLAN_TSV" | tr -d ' ')"
TOTAL_FILES="$(cut -f1 "$READ_PLAN_TSV" | sort -u | wc -l | tr -d ' ')"

{
  printf '# Read Plan\n\n'
  printf 'Mode: `%s`\n\n' "$MODE"
  printf 'Limits: max files `%s`, max slices `%s`, slice radius `%s`\n\n' "$MAX_FILES" "$MAX_SLICES" "$RADIUS"
  printf 'Generated slices: `%s` across `%s` files\n\n' "$TOTAL_SLICES" "$TOTAL_FILES"
  printf 'Use this file as the evidence budget. Do not exceed these slices unless user explicitly asks.\n\n'
  printf '## Slices\n\n'
  awk -F'\t' '{
    printf "- `%s` lines `%s-%s` (match at `%s`): %s\n", $1, $3, $4, $2, $5
  }' "$READ_PLAN_TSV"
} > "$READ_PLAN_MD"

rm -f "$RAW_MATCHES" "$NORMALIZED_MATCHES"

log "Wrote $READ_PLAN_TSV"
log "Wrote $READ_PLAN_MD"
log "Read plan generation complete"
