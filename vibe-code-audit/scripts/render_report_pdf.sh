#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="render_report_pdf.sh"

usage() {
  cat <<'USAGE'
Optionally render an audit report PDF when required tools are available.

Usage:
  render_report_pdf.sh --report <audit_report.md> [--output <audit_report.pdf>] [--engine <pdf_engine>] [--skip-system-map]

Behavior:
  - If required tools are unavailable, this script exits 0 and prints:
      PDF_SKIPPED=1
      PDF_REASON=<reason>
  - If rendering succeeds, this script exits 0 and prints:
      PDF_PATH=<absolute path to generated PDF>
USAGE
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
}

warn() {
  printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

REPORT_PATH=""
OUTPUT_PATH=""
FORCED_ENGINE=""
SKIP_SYSTEM_MAP=0

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
    --output)
      [ $# -ge 2 ] || {
        warn "--output requires a value"
        usage
        exit 1
      }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --engine)
      [ $# -ge 2 ] || {
        warn "--engine requires a value"
        usage
        exit 1
      }
      FORCED_ENGINE="$2"
      shift 2
      ;;
    --skip-system-map)
      SKIP_SYSTEM_MAP=1
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

if [ -z "$REPORT_PATH" ]; then
  warn "--report is required"
  usage
  exit 1
fi

if [ ! -s "$REPORT_PATH" ]; then
  warn "Report file not found or empty: $REPORT_PATH"
  echo "PDF_SKIPPED=1"
  echo "PDF_REASON=report_missing_or_empty"
  exit 0
fi

if [ -z "$OUTPUT_PATH" ]; then
  case "$REPORT_PATH" in
    *.md) OUTPUT_PATH="${REPORT_PATH%.md}.pdf" ;;
    *) OUTPUT_PATH="${REPORT_PATH}.pdf" ;;
  esac
fi

REPORT_DIR="$(cd "$(dirname "$REPORT_PATH")" && pwd)"
REPORT_PATH_ABS="$REPORT_DIR/$(basename "$REPORT_PATH")"

if [ "$SKIP_SYSTEM_MAP" -eq 0 ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  SYSTEM_MAP_SCRIPT="$SCRIPT_DIR/render_system_map.sh"

  if [ -x "$SYSTEM_MAP_SCRIPT" ]; then
    SYSTEM_MAP_OUT="$(bash "$SYSTEM_MAP_SCRIPT" --report "$REPORT_PATH_ABS" || true)"
    if [ -n "$SYSTEM_MAP_OUT" ]; then
      printf '%s\n' "$SYSTEM_MAP_OUT" >&2
    fi
    SYSTEM_MAP_PATH="$(printf '%s\n' "$SYSTEM_MAP_OUT" | awk -F= '/^SYSTEM_MAP_PATH=/{print $2}' | tail -n1)"
    SYSTEM_MAP_REASON="$(printf '%s\n' "$SYSTEM_MAP_OUT" | awk -F= '/^SYSTEM_MAP_REASON=/{print $2}' | tail -n1)"
    if [ -n "$SYSTEM_MAP_PATH" ]; then
      log "System map image ready: $SYSTEM_MAP_PATH"
    elif [ -n "$SYSTEM_MAP_REASON" ]; then
      log "System map render skipped: $SYSTEM_MAP_REASON"
    fi
  fi
fi

if ! command -v pandoc >/dev/null 2>&1; then
  warn "pandoc is not installed; skipping PDF generation"
  echo "PDF_SKIPPED=1"
  echo "PDF_REASON=pandoc_missing"
  exit 0
fi

choose_engine() {
  if [ -n "$FORCED_ENGINE" ]; then
    if command -v "$FORCED_ENGINE" >/dev/null 2>&1; then
      printf '%s\n' "$FORCED_ENGINE"
      return 0
    fi
    return 1
  fi

  for engine in tectonic typst xelatex pdflatex wkhtmltopdf weasyprint; do
    if command -v "$engine" >/dev/null 2>&1; then
      printf '%s\n' "$engine"
      return 0
    fi
  done

  return 1
}

if ! PDF_ENGINE="$(choose_engine)"; then
  if [ -n "$FORCED_ENGINE" ]; then
    warn "Requested PDF engine '$FORCED_ENGINE' is not installed; skipping PDF generation"
    echo "PDF_SKIPPED=1"
    echo "PDF_REASON=engine_missing"
    exit 0
  fi

  warn "No supported PDF engine found (checked: tectonic, typst, xelatex, pdflatex, wkhtmltopdf, weasyprint)"
  echo "PDF_SKIPPED=1"
  echo "PDF_REASON=no_pdf_engine_available"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

PANDOC_COMMON_ARGS=(
  --from=gfm
  --resource-path="$REPORT_DIR"
  -V geometry:margin=1in
  -V geometry:a4paper
  -V fontsize=11pt
  -V colorlinks=true
  -V linkcolor=blue
  -V urlcolor=blue
  -V monofont=Menlo
  --syntax-highlighting=tango
)

case "$PDF_ENGINE" in
  tectonic|typst|xelatex|pdflatex)
    PANDOC_COMMON_ARGS+=(
      -V 'header-includes=\usepackage{longtable,booktabs,array}\usepackage{graphicx}'
    )
    ;;
esac

log "Rendering PDF with pandoc engine: $PDF_ENGINE"
if pandoc "$REPORT_PATH_ABS" \
  -o "$OUTPUT_PATH" \
  --pdf-engine="$PDF_ENGINE" \
  "${PANDOC_COMMON_ARGS[@]}"; then
  if [ -s "$OUTPUT_PATH" ]; then
    log "Wrote $OUTPUT_PATH"
    echo "PDF_PATH=$OUTPUT_PATH"
    exit 0
  fi

  warn "Pandoc completed but output file is empty: $OUTPUT_PATH"
  echo "PDF_SKIPPED=1"
  echo "PDF_REASON=empty_pdf_output"
  exit 0
fi

warn "Pandoc PDF render failed; skipping PDF artifact"
echo "PDF_SKIPPED=1"
echo "PDF_REASON=pandoc_render_failed"
exit 0
