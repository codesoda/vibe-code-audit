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

# ---------------------------------------------------------------------------
# File & pattern helpers
# ---------------------------------------------------------------------------

# json_int_from_file FILE KEY
#   Extracts the first integer value for KEY from a JSON-like FILE.
#   Returns the integer on stdout; defaults to 0 if the file is missing,
#   the key is absent, or the value is non-numeric.
#   Used by run_index.sh to parse agentroot status.json fields
#   (document_count, embedded_count). Inline copy remains in run_index.sh
#   until migration spec 07.
json_int_from_file() {
  local file="${1-}"
  local key="${2-}"
  local value
  value="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "$file" 2>/dev/null | head -n1)" || true
  if [ -z "$value" ]; then
    printf '0\n'
  else
    printf '%s\n' "$value"
  fi
}

# has_pattern_in_files PATTERN [FILE ...]
#   Returns 0 (true) if PATTERN matches in any of the listed files
#   (case-insensitive extended regex via grep -Eqi). Skips missing files.
#   Short-circuits on first match. Returns 1 if no match found.
#   Used by run_index.sh and run_agentroot_embed.sh for retrieval
#   diagnostics and error classification. Inline copies remain until
#   migration specs 07/10.
has_pattern_in_files() {
  local pattern="${1-}"
  shift
  local file
  for file in "$@"; do
    [ -f "$file" ] || continue
    if grep -Eqi "$pattern" "$file"; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# JSON helpers — RFC 8259 §7 compliant string escaping
# ---------------------------------------------------------------------------

# json_escape STRING
#   Escapes a string for safe embedding inside a JSON quoted value.
#   Handles: backslash, double-quote, and all control chars U+0000-U+001F.
#   Uses od + awk (no jq dependency). Preserves non-ASCII bytes (UTF-8 safe).
#   Note: shell variables cannot contain NUL (0x00); NUL is handled correctly
#   if present in the byte stream but cannot be passed via $1 in bash.
json_escape() {
  local input="${1-}"
  if [ -z "$input" ]; then
    return
  fi
  printf '%s' "$input" | LC_ALL=C od -An -tx1 | awk '
  BEGIN {
    split("0123456789abcdef", hx, "")
    for (i = 1; i <= 16; i++) h2d[hx[i]] = i - 1
  }
  {
    for (i = 1; i <= NF; i++) {
      d = h2d[substr($i, 1, 1)] * 16 + h2d[substr($i, 2, 1)]
      if      ($i == "5c") printf "\\\\"
      else if ($i == "22") printf "\\\""
      else if ($i == "08") printf "\\b"
      else if ($i == "09") printf "\\t"
      else if ($i == "0a") printf "\\n"
      else if ($i == "0c") printf "\\f"
      else if ($i == "0d") printf "\\r"
      else if (d < 32)     printf "\\u%04x", d
      else                  printf "%c", d
    }
  }'
}
