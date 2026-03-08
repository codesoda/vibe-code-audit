# shellcheck shell=bash
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
# Config path constants
# ---------------------------------------------------------------------------

# Canonical path for persistent embed configuration written by install.sh.
# Can be overridden via environment for testing.
EMBED_ENV_FILE="${EMBED_ENV_FILE:-$HOME/.config/vibe-code-audit/embed.env}"

# ---------------------------------------------------------------------------
# File & pattern helpers
# ---------------------------------------------------------------------------

# kv_from_file FILE KEY
#   Extracts the value of KEY from a simple KEY=VALUE file.
#   Reads the last occurrence of the key (last-occurrence-wins).
#   Returns the value on stdout; empty string if not found.
kv_from_file() {
  local file="${1-}"
  local key="${2-}"
  local value
  value="$(sed -n "s/^${key}=//p" "$file" | tail -n1)"
  printf '%s\n' "$value"
}

# repo_has_file_named NAME
#   Returns 0 (true) if a file named NAME exists anywhere in the current
#   directory tree (respecting EXCLUDE_DIRS). Must be called from within
#   the repository root (e.g., after pushd "$REPO_PATH_ABS").
repo_has_file_named() {
  local name="${1-}"
  # shellcheck disable=SC2046
  if find . \( $(exclude_find_prune_args) \) -prune \
    -o -type f -name "$name" -print -quit | grep -q .; then
    return 0
  fi
  return 1
}

# json_int_from_file FILE KEY
#   Extracts the first integer value for KEY from a JSON-like FILE.
#   Returns the integer on stdout; defaults to 0 if the file is missing,
#   the key is absent, or the value is non-numeric.
#   Used by run_index.sh to parse agentroot status.json fields
#   (document_count, embedded_count).
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
#   diagnostics and error classification.
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
# Path helpers
# ---------------------------------------------------------------------------

# resolve_output_dir PATH
#   Resolves PATH to a canonical absolute directory path.
#   Creates the directory (mkdir -p) if it doesn't exist, matching the
#   inline OUTPUT_DIR_ABS resolution in run_index.sh, build_derived_artifacts.sh,
#   and build_read_plan.sh.
#   For absolute paths (starting with /): creates and canonicalizes directly.
#   For relative paths: resolves relative to the caller's working directory.
#     Callers must cd to the appropriate base (e.g., REPO_PATH_ABS) before
#     invoking for relative paths.
#   Returns the canonical absolute path on stdout via cd + pwd.
#   Dies if the path cannot be created, is not a directory, or cannot be resolved.
resolve_output_dir() {
  local dir="${1-}"
  [ -n "$dir" ] || die "resolve_output_dir: path argument is required"
  if ! mkdir -p "$dir" 2>/dev/null; then
    die "resolve_output_dir: cannot create directory: $dir"
  fi
  [ -d "$dir" ] || die "resolve_output_dir: not a directory: $dir"
  (cd "$dir" && pwd -P) || die "resolve_output_dir: cannot resolve directory: $dir"
}

# ---------------------------------------------------------------------------
# Exclude-directory list and helpers
# ---------------------------------------------------------------------------

# Canonical list of directories to exclude from traversal.
# All scripts MUST use these helpers instead of hardcoding directory names.
# Space-delimited string (not a bash array) for POSIX compatibility.
EXCLUDE_DIRS=".git node_modules target dist build .next coverage"

# exclude_find_prune_args
#   Outputs find(1) prune expression fragments for use inside \( ... \) -prune.
#   Usage: find . \( $(exclude_find_prune_args) \) -prune -o ...
#   Output: -name .git -o -name node_modules -o -name target ...
exclude_find_prune_args() {
  local first=1
  local dir
  for dir in $EXCLUDE_DIRS; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ' -o '
    fi
    printf -- '-name %s' "$dir"
  done
}

# exclude_agentroot_flags
#   Outputs --exclude flags for agentroot CLI.
#   Usage: agentroot index . $(exclude_agentroot_flags) --output ...
#   Output: --exclude .git --exclude node_modules ...
exclude_agentroot_flags() {
  local dir
  for dir in $EXCLUDE_DIRS; do
    printf -- '--exclude %s ' "$dir"
  done
}

# exclude_rg_globs
#   Outputs ripgrep glob exclusion flags.
#   Usage: rg $(exclude_rg_globs) PATTERN .
#   Output: --glob '!.git/**' --glob '!node_modules/**' ...
exclude_rg_globs() {
  local dir
  for dir in $EXCLUDE_DIRS; do
    printf -- "--glob '!%s/**' " "$dir"
  done
}

# exclude_dirs_json_array
#   Outputs a JSON array of excluded directory names.
#   Usage: "exclude_patterns": $(exclude_dirs_json_array),
#   Output: [".git", "node_modules", "target", "dist", "build", ".next", "coverage"]
exclude_dirs_json_array() {
  local first=1
  local dir
  printf '['
  for dir in $EXCLUDE_DIRS; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ', '
    fi
    printf '"%s"' "$dir"
  done
  printf ']'
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
