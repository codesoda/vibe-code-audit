#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="render_system_map.sh"

usage() {
  cat <<'USAGE'
Optionally render a system map image for an audit report when Graphviz is available.

Usage:
  render_system_map.sh --report <audit_report.md> [--dot <system_map.dot>] [--image <system_map.png>] [--mode <auto|crate|full>] [--no-edit]

Behavior:
  - If rendering succeeds, this script exits 0 and prints:
      SYSTEM_MAP_PATH=<absolute path to generated image>
      SYSTEM_MAP_DOT=<absolute path to source dot file>
      SYSTEM_MAP_REPORT_UPDATED=0|1
  - If requirements are unavailable, this script exits 0 and prints:
      SYSTEM_MAP_SKIPPED=1
      SYSTEM_MAP_REASON=<reason>
USAGE
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
}

warn() {
  printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

REPORT_PATH=""
DOT_PATH=""
IMAGE_PATH=""
MAP_MODE="auto"
NO_EDIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --report)
      [ $# -ge 2 ] || {
        warn "--report requires a value"
        usage
        exit 1
      }
      REPORT_PATH="$2"
      shift 2
      ;;
    --dot)
      [ $# -ge 2 ] || {
        warn "--dot requires a value"
        usage
        exit 1
      }
      DOT_PATH="$2"
      shift 2
      ;;
    --image)
      [ $# -ge 2 ] || {
        warn "--image requires a value"
        usage
        exit 1
      }
      IMAGE_PATH="$2"
      shift 2
      ;;
    --mode)
      [ $# -ge 2 ] || {
        warn "--mode requires a value"
        usage
        exit 1
      }
      MAP_MODE="$2"
      shift 2
      ;;
    --no-edit)
      NO_EDIT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

case "$MAP_MODE" in
  auto|crate|full) ;;
  *)
    warn "Invalid --mode value: $MAP_MODE (expected auto|crate|full)"
    usage
    exit 1
    ;;
esac

if [ -z "$REPORT_PATH" ]; then
  warn "--report is required"
  usage
  exit 1
fi

if [ ! -s "$REPORT_PATH" ]; then
  warn "Report file not found or empty: $REPORT_PATH"
  echo "SYSTEM_MAP_SKIPPED=1"
  echo "SYSTEM_MAP_REASON=report_missing_or_empty"
  exit 0
fi

REPORT_DIR="$(cd "$(dirname "$REPORT_PATH")" && pwd)"
REPORT_PATH_ABS="$REPORT_DIR/$(basename "$REPORT_PATH")"

if ! command -v dot >/dev/null 2>&1; then
  warn "graphviz 'dot' is not installed; skipping system map render"
  echo "SYSTEM_MAP_SKIPPED=1"
  echo "SYSTEM_MAP_REASON=graphviz_missing"
  exit 0
fi

if [ -n "$DOT_PATH" ]; then
  case "$DOT_PATH" in
    /*) ;;
    *) DOT_PATH="$REPORT_DIR/$DOT_PATH" ;;
  esac
fi

dot_candidates_by_mode() {
  mode="$1"
  case "$mode" in
    crate)
      cat <<EOF_CANDIDATES
$REPORT_DIR/system_map.dot
$REPORT_DIR/audit_index/derived/system_map.dot
$REPORT_DIR/audit_index/llmcc/rust/depth1.dot
$REPORT_DIR/audit_index/llmcc/ts/depth2.dot
$REPORT_DIR/audit_index/llmcc/rust/depth2.dot
$REPORT_DIR/audit_index/llmcc/ts/depth3.dot
$REPORT_DIR/audit_index/llmcc/rust/depth3.dot
EOF_CANDIDATES
      ;;
    full)
      cat <<EOF_CANDIDATES
$REPORT_DIR/system_map.dot
$REPORT_DIR/audit_index/derived/system_map.dot
$REPORT_DIR/audit_index/llmcc/rust/depth3_topk.dot
$REPORT_DIR/audit_index/llmcc/ts/depth3_topk.dot
$REPORT_DIR/audit_index/llmcc/rust/depth3.dot
$REPORT_DIR/audit_index/llmcc/ts/depth3.dot
$REPORT_DIR/audit_index/llmcc/rust/depth2.dot
$REPORT_DIR/audit_index/llmcc/ts/depth2.dot
$REPORT_DIR/audit_index/llmcc/rust/depth1.dot
EOF_CANDIDATES
      ;;
    *)
      cat <<EOF_CANDIDATES
$REPORT_DIR/system_map.dot
$REPORT_DIR/audit_index/derived/system_map.dot
$REPORT_DIR/audit_index/llmcc/rust/depth1.dot
$REPORT_DIR/audit_index/llmcc/ts/depth2.dot
$REPORT_DIR/audit_index/llmcc/rust/depth2.dot
$REPORT_DIR/audit_index/llmcc/ts/depth3.dot
$REPORT_DIR/audit_index/llmcc/rust/depth3.dot
$REPORT_DIR/audit_index/llmcc/rust/depth3_topk.dot
$REPORT_DIR/audit_index/llmcc/ts/depth3_topk.dot
EOF_CANDIDATES
      ;;
  esac
}

if [ -z "$DOT_PATH" ]; then
  while IFS= read -r candidate; do
    if [ -s "$candidate" ]; then
      DOT_PATH="$candidate"
      break
    fi
  done < <(dot_candidates_by_mode "$MAP_MODE")
fi

if [ -z "$DOT_PATH" ] || [ ! -s "$DOT_PATH" ]; then
  warn "No system map dot source found (expected system_map.dot or llmcc depth graph)"
  echo "SYSTEM_MAP_SKIPPED=1"
  echo "SYSTEM_MAP_REASON=dot_source_missing"
  exit 0
fi

DOT_PATH_DIR="$(cd "$(dirname "$DOT_PATH")" && pwd)"
DOT_PATH_ABS="$DOT_PATH_DIR/$(basename "$DOT_PATH")"

if [ -z "$IMAGE_PATH" ]; then
  IMAGE_PATH="$REPORT_DIR/system_map.png"
else
  case "$IMAGE_PATH" in
    /*) ;;
    *) IMAGE_PATH="$REPORT_DIR/$IMAGE_PATH" ;;
  esac
fi

mkdir -p "$(dirname "$IMAGE_PATH")"

DOT_RENDER_ARGS=(-Tpng -Gdpi=200)
case "$DOT_PATH_ABS" in
  */llmcc/*/depth3_topk.dot|*/llmcc/*/depth3.dot)
    # Prevent oversized images that often break PDF rendering.
    DOT_RENDER_ARGS+=(-Gsize=9,12! -Gratio=compress)
    ;;
esac
if [ "$MAP_MODE" = "full" ]; then
  DOT_RENDER_ARGS+=(-Gsize=9,12! -Gratio=compress)
fi

if ! dot "${DOT_RENDER_ARGS[@]}" "$DOT_PATH_ABS" -o "$IMAGE_PATH"; then
  warn "dot render failed for $DOT_PATH_ABS"
  echo "SYSTEM_MAP_SKIPPED=1"
  echo "SYSTEM_MAP_REASON=dot_render_failed"
  exit 0
fi

if [ ! -s "$IMAGE_PATH" ]; then
  warn "Rendered image is empty: $IMAGE_PATH"
  echo "SYSTEM_MAP_SKIPPED=1"
  echo "SYSTEM_MAP_REASON=empty_image_output"
  exit 0
fi

REPORT_UPDATED=0
IMAGE_REF="$(basename "$IMAGE_PATH")"
IMAGE_LINE="![System Map - module dependencies and boundaries]($IMAGE_REF)"

if [ "$NO_EDIT" -eq 0 ] && ! grep -Fq "]($IMAGE_REF)" "$REPORT_PATH_ABS"; then
  tmp_report="$(mktemp "${TMPDIR:-/tmp}/vca-system-map-report.XXXXXX")"
  awk -v image_line="$IMAGE_LINE" '
  BEGIN {
    in_system=0
    injected=0
    skipping_block=0
    dropped_ascii=0
    seen_system_heading=0
  }
  function is_system_heading(line) {
    return (line ~ /^# +[0-9]+[.] +System Map/ || line ~ /^## +System Map/ || line ~ /^# +System Map/)
  }
  function is_top_heading(line) {
    return (line ~ /^# +[0-9]+[.]/ || line ~ /^# +[A-Za-z]/)
  }
  {
    if (is_system_heading($0)) {
      in_system=1
      seen_system_heading=1
      print $0
      next
    }

    if (in_system == 1 && is_top_heading($0)) {
      if (injected == 0) {
        print ""
        print image_line
        print ""
        injected=1
      }
      in_system=0
    }

    if (in_system == 1 && dropped_ascii == 0) {
      if (skipping_block == 0 && $0 ~ /^```/) {
        if (injected == 0) {
          print ""
          print image_line
          print ""
          injected=1
        }
        skipping_block=1
        dropped_ascii=1
        next
      }
      if (skipping_block == 1) {
        if ($0 ~ /^```/) {
          skipping_block=0
        }
        next
      }
    }

    print $0
  }
  END {
    if (injected == 0) {
      if (seen_system_heading == 0) {
        print ""
        print "## System Map"
      }
      print ""
      print image_line
    }
  }
  ' "$REPORT_PATH_ABS" > "$tmp_report"
  mv "$tmp_report" "$REPORT_PATH_ABS"
  REPORT_UPDATED=1
fi

log "Rendered system map image: $IMAGE_PATH"
DOT_SOURCE_KIND="custom-dot"
case "$DOT_PATH_ABS" in
  */llmcc/*/depth1.dot) DOT_SOURCE_KIND="llmcc-depth1" ;;
  */llmcc/*/depth2.dot) DOT_SOURCE_KIND="llmcc-depth2" ;;
  */llmcc/*/depth3.dot) DOT_SOURCE_KIND="llmcc-depth3" ;;
  */llmcc/*/depth3_topk.dot) DOT_SOURCE_KIND="llmcc-depth3-topk" ;;
  */audit_index/derived/system_map.dot) DOT_SOURCE_KIND="derived-system-map" ;;
  */system_map.dot) DOT_SOURCE_KIND="report-system-map" ;;
esac
echo "SYSTEM_MAP_PATH=$IMAGE_PATH"
echo "SYSTEM_MAP_DOT=$DOT_PATH_ABS"
echo "SYSTEM_MAP_MODE=$MAP_MODE"
echo "SYSTEM_MAP_SOURCE_KIND=$DOT_SOURCE_KIND"
echo "SYSTEM_MAP_REPORT_UPDATED=$REPORT_UPDATED"
exit 0
