# _lib.sh — shared utility library for vibe-code-audit pipeline scripts
#
# Sourced by all pipeline scripts (run_index.sh, build_derived_artifacts.sh,
# build_read_plan.sh, run_agentroot_embed.sh, render_system_map.sh,
# render_report_pdf.sh). NOT sourced by install.sh.
#
# The sourcing script is responsible for:
#   1. Setting `set -euo pipefail` before sourcing.
#   2. Defining SCRIPT_NAME before sourcing (used in log prefixes).

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME:-unknown}" "$*" >&2
}

warn() {
  printf '[%s] WARNING: %s\n' "${SCRIPT_NAME:-unknown}" "$*" >&2
}

die() {
  printf '[%s] FATAL: %s\n' "${SCRIPT_NAME:-unknown}" "$*" >&2
  exit 1
}
