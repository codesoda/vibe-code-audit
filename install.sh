#!/bin/sh
set -eu

# NOTE: This is a standalone POSIX sh installer that does NOT source _lib.sh.
# It intentionally defines its own output helpers (info, dim, ok, warn, die)
# for colored terminal output. Changes to logging in _lib.sh must be
# manually reconciled here if the installer's output contract changes.

SKILL_NAME="vibe-code-audit"
REPO_OWNER="${VIBE_CODE_AUDIT_REPO_OWNER:-codesoda}"
REPO_NAME="${VIBE_CODE_AUDIT_REPO_NAME:-vibe-code-audit}"
REPO_REF="${VIBE_CODE_AUDIT_REPO_REF:-main}"
RAW_BASE="${VIBE_CODE_AUDIT_RAW_BASE:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}}"

CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

AUTO_YES=0
SKIP_DEPS=0
INSTALL_CODEX=1
INSTALL_CLAUDE=1

TMP_DIR=""
SOURCE_DIR=""
SOURCE_MODE="remote"

# ---------------------------------------------------------------------------
# Color definitions — soft pastels that work on both light and dark terminals
# Uses 256-color mode for broader compatibility
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  USE_COLOR=1
else
  USE_COLOR=0
fi

if [ "$USE_COLOR" -eq 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  # Soft lavender for headers
  C_HEADER='\033[38;5;141m'
  # Soft mint for success/info
  C_OK='\033[38;5;114m'
  # Soft peach for warnings
  C_WARN='\033[38;5;216m'
  # Soft rose for errors
  C_ERR='\033[38;5;210m'
  # Soft sky blue for prompts
  C_PROMPT='\033[38;5;117m'
  # Soft grey for secondary text
  C_DIM_TEXT='\033[38;5;249m'
  # Soft cyan for check marks
  C_CHECK='\033[38;5;151m'
else
  C_RESET=''
  C_BOLD=''
  C_DIM=''
  C_HEADER=''
  C_OK=''
  C_WARN=''
  C_ERR=''
  C_PROMPT=''
  C_DIM_TEXT=''
  C_CHECK=''
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
header() {
  printf '\n%b%b  %s%b\n' "$C_BOLD" "$C_HEADER" "$*" "$C_RESET"
  printf '%b  %s%b\n' "$C_DIM_TEXT" "$(echo "$*" | sed 's/./-/g')" "$C_RESET"
}

info() {
  printf '%b  %s%b\n' "$C_OK" "$*" "$C_RESET"
}

dim() {
  printf '%b  %s%b\n' "$C_DIM_TEXT" "$*" "$C_RESET"
}

ok() {
  printf '%b  ✓ %s%b\n' "$C_CHECK" "$*" "$C_RESET"
}

# Print primary text with dimmed parenthetical suffix
ok_with_detail() {
  primary="$1"
  detail="$2"
  printf '%b  ✓ %s %b(%s)%b\n' "$C_CHECK" "$primary" "$C_DIM_TEXT" "$detail" "$C_RESET"
}

warn() {
  printf '%b  ! %s%b\n' "$C_WARN" "$*" "$C_RESET" >&2
}

die() {
  printf '%b  ✗ %s%b\n' "$C_ERR" "$*" "$C_RESET" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Install vibe-code-audit skill into local agent skill directories.

Usage:
  sh install.sh [options]
  curl -sSf https://raw.githubusercontent.com/codesoda/vibe-code-audit/main/install.sh | sh

Options:
  --yes          Non-interactive mode; accept default install prompts.
  --skip-deps    Skip dependency checks/install attempts.
  --codex-only   Only install to ~/.codex/skills.
  --claude-only  Only install to ~/.claude/skills.
  --help         Show this help text.

Environment variables:
  CODEX_SKILLS_DIR   Override Codex skills root (default: ~/.codex/skills)
  CLAUDE_SKILLS_DIR  Override Claude skills root (default: ~/.claude/skills)
  VIBE_CODE_AUDIT_REPO_OWNER  Override repo owner for remote fetches.
  VIBE_CODE_AUDIT_REPO_NAME   Override repo name for remote fetches.
  VIBE_CODE_AUDIT_REPO_REF    Override repo ref/branch for remote fetches.
  VIBE_CODE_AUDIT_RAW_BASE    Override full raw base URL for remote fetches.
EOF
}

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Prompt helper
# ---------------------------------------------------------------------------
prompt_yes_no() {
  question="$1"
  default="${2:-yes}"

  if [ "$AUTO_YES" -eq 1 ]; then
    return 0
  fi

  if [ "$default" = "yes" ]; then
    prompt="[Y/n]"
    fallback="yes"
  else
    prompt="[y/N]"
    fallback="no"
  fi

  if [ -r /dev/tty ]; then
    while :; do
      printf '\n%b  %s %b%s%b ' "$C_PROMPT" "$question" "$C_BOLD" "$prompt" "$C_RESET" > /dev/tty
      if ! IFS= read -r answer < /dev/tty; then
        break
      fi
      case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        [Nn]|[Nn][Oo]) return 1 ;;
        "")
          if [ "$fallback" = "yes" ]; then
            return 0
          fi
          return 1
          ;;
        *) printf '%b  Please answer yes or no.%b\n' "$C_DIM_TEXT" "$C_RESET" > /dev/tty ;;
      esac
    done
  fi

  if [ "$fallback" = "yes" ]; then
    info "Non-interactive: auto-accepting '$question'"
    return 0
  fi
  info "Non-interactive: auto-declining '$question'"
  return 1
}

# ---------------------------------------------------------------------------
# Network fetch
# ---------------------------------------------------------------------------
fetch_to_file() {
  url="$1"
  out="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Source resolution
# ---------------------------------------------------------------------------
resolve_source_dir() {
  if [ -f "./${SKILL_NAME}/SKILL.md" ]; then
    SOURCE_DIR="$(pwd)/${SKILL_NAME}"
    SOURCE_MODE="local"
    ok "Using local skill source at ${SOURCE_DIR}"
    return 0
  fi

  case "$0" in
    */*)
      script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
      if [ -n "$script_dir" ] && [ -f "$script_dir/${SKILL_NAME}/SKILL.md" ]; then
        SOURCE_DIR="$script_dir/${SKILL_NAME}"
        SOURCE_MODE="local"
        ok "Using skill source next to install.sh at ${SOURCE_DIR}"
        return 0
      fi
      ;;
  esac

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${SKILL_NAME}.XXXXXX")"
  SOURCE_DIR="${TMP_DIR}/${SKILL_NAME}"
  SOURCE_MODE="remote"
  mkdir -p "$SOURCE_DIR"

  remote_manifest_url="${RAW_BASE}/${SKILL_NAME}/INSTALL_MANIFEST.txt"
  remote_skill_url="${RAW_BASE}/${SKILL_NAME}/SKILL.md"
  remote_report_template_url="${RAW_BASE}/${SKILL_NAME}/REPORT_TEMPLATE.md"
  manifest_tmp="${TMP_DIR}/INSTALL_MANIFEST.txt"

  if fetch_to_file "$remote_manifest_url" "$manifest_tmp"; then
    info "Fetching skill files from ${remote_manifest_url}"
    while IFS= read -r rel_path || [ -n "$rel_path" ]; do
      case "$rel_path" in
        ""|\#*)
          continue
          ;;
      esac

      src_url="${RAW_BASE}/${SKILL_NAME}/${rel_path}"
      dest_path="${SOURCE_DIR}/${rel_path}"
      mkdir -p "$(dirname "$dest_path")"

      if ! fetch_to_file "$src_url" "$dest_path"; then
        if [ "$rel_path" = "SKILL.md" ]; then
          die "Unable to download required file: ${src_url}"
        fi
        warn "Could not download optional file: ${src_url}"
        continue
      fi

      case "$rel_path" in
        scripts/*.sh)
          chmod +x "$dest_path" 2>/dev/null || true
          ;;
      esac
    done < "$manifest_tmp"
  else
    warn "Could not download INSTALL_MANIFEST.txt; falling back to minimal fetch."
  fi

  if [ ! -f "${SOURCE_DIR}/SKILL.md" ]; then
    info "Fetching skill from ${remote_skill_url}"
    if ! fetch_to_file "$remote_skill_url" "${SOURCE_DIR}/SKILL.md"; then
      die "Unable to download SKILL.md (need curl or wget, and network access)."
    fi
  fi

  if [ ! -f "${SOURCE_DIR}/REPORT_TEMPLATE.md" ]; then
    info "Fetching template from ${remote_report_template_url}"
    if ! fetch_to_file "$remote_report_template_url" "${SOURCE_DIR}/REPORT_TEMPLATE.md"; then
      warn "Could not download REPORT_TEMPLATE.md; continuing without it."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Dependency helpers
# ---------------------------------------------------------------------------
ensure_rust_toolchain() {
  if command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  warn "cargo is not installed."
  if ! prompt_yes_no "Install Rust toolchain via rustup now?" yes; then
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is required to install rustup automatically."
    return 1
  fi

  info "Installing Rust toolchain with rustup..."
  if ! sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"; then
    warn "Rust toolchain installation failed."
    return 1
  fi

  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
  fi
  PATH="$HOME/.cargo/bin:$PATH"
  export PATH

  command -v cargo >/dev/null 2>&1
}

install_dependency() {
  dep="$1"

  if command -v "$dep" >/dev/null 2>&1; then
    ok "${dep} found"
    return 0
  fi

  warn "Dependency missing: ${dep}"
  if [ "$SKIP_DEPS" -eq 1 ]; then
    return 1
  fi

  if ! prompt_yes_no "Install missing dependency '${dep}' now?" yes; then
    return 1
  fi

  if ! ensure_rust_toolchain; then
    warn "Cannot auto-install ${dep} without cargo."
    return 1
  fi

  info "Running: cargo install ${dep}"
  if ! cargo install "$dep"; then
    warn "cargo install ${dep} failed."
    return 1
  fi

  PATH="$HOME/.cargo/bin:$PATH"
  export PATH

  if command -v "$dep" >/dev/null 2>&1; then
    ok "${dep} installed"
    return 0
  fi

  warn "Install command completed but ${dep} is still not on PATH."
  return 1
}

brew_or_apt_install() {
  pkg="$1"
  label="${2:-$pkg}"

  if command -v brew >/dev/null 2>&1; then
    info "Running: brew install ${pkg}"
    if brew install "$pkg"; then
      return 0
    fi
    warn "brew install ${pkg} failed"
    return 1
  elif command -v apt-get >/dev/null 2>&1; then
    info "Running: sudo apt-get install -y ${pkg}"
    if sudo apt-get install -y "$pkg"; then
      return 0
    fi
    warn "apt-get install ${pkg} failed"
    return 1
  else
    warn "No supported package manager found (brew or apt-get)"
    warn "Install ${label} manually"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Skill install
# ---------------------------------------------------------------------------
install_skill_to_root() {
  root="$1"
  target="${root}/${SKILL_NAME}"

  mkdir -p "$root"
  rm -rf "$target"

  if [ "$SOURCE_MODE" = "local" ]; then
    ln -s "$SOURCE_DIR" "$target"
    ok "Symlinked ${target} -> ${SOURCE_DIR}"
    return 0
  fi

  mkdir -p "$target"
  cp -R "${SOURCE_DIR}/." "$target/"
  ok "Installed skill to ${target}"
}

# =========================================================================
# Main
# =========================================================================

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)
      AUTO_YES=1
      ;;
    --skip-deps)
      SKIP_DEPS=1
      ;;
    --codex-only)
      INSTALL_CODEX=1
      INSTALL_CLAUDE=0
      ;;
    --claude-only)
      INSTALL_CODEX=0
      INSTALL_CLAUDE=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
  shift
done

# Banner
printf '\n%b%b  vibe-code-audit installer%b\n' "$C_BOLD" "$C_HEADER" "$C_RESET"
printf '%b  =========================%b\n\n' "$C_DIM_TEXT" "$C_RESET"

resolve_source_dir

# --- Core dependencies ---------------------------------------------------

header "Core Dependencies"

if [ "$SKIP_DEPS" -eq 1 ]; then
  dim "Skipping dependency checks (--skip-deps)."
else
  install_dependency "llmcc" || true
  install_dependency "agentroot" || true
fi

# --- Search mode ----------------------------------------------------------

header "Search Mode"

dim "vibe-code-audit can use either:"
printf '\n'
dim "  BM25 text search     No extra dependencies, works out of the box"
dim "  Vector embeddings    Better semantic recall, needs llama-server (~300MB model download)"
printf '\n'

if prompt_yes_no "Enable vector embeddings?" yes; then
  EMBED_REQUESTED=1
  if command -v llama-server >/dev/null 2>&1; then
    ok_with_detail "llama-server already installed" "$(command -v llama-server)"
  elif brew_or_apt_install "llama.cpp" "llama-server"; then
    ok "llama-server installed"
  else
    warn "Could not install llama-server — you can retry manually later"
    EMBED_REQUESTED=0
  fi

  if [ "$EMBED_REQUESTED" -eq 1 ]; then
    EMBED_ENV_FILE="$HOME/.config/vibe-code-audit/embed.env"
    mkdir -p "$(dirname "$EMBED_ENV_FILE")"
    printf 'VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL=1\n' > "$EMBED_ENV_FILE"
    ok "Embedding model will download automatically on first audit run"
    dim "Config: $EMBED_ENV_FILE"
  fi
else
  ok_with_detail "Using BM25 text search" "no extra setup needed"
fi

# --- PDF export -----------------------------------------------------------

header "PDF Export"

dim "Generate PDF reports from audit results."
dim "Requires pandoc + a PDF engine."
printf '\n'

if prompt_yes_no "Install PDF export support?" yes; then
  PDF_OK=1

  if command -v pandoc >/dev/null 2>&1; then
    ok_with_detail "pandoc already installed" "$(command -v pandoc)"
  elif brew_or_apt_install "pandoc" "pandoc"; then
    ok "pandoc installed"
  else
    warn "Could not install pandoc"
    PDF_OK=0
  fi

  if command -v tectonic >/dev/null 2>&1; then
    ok_with_detail "tectonic already installed" "$(command -v tectonic)"
  elif brew_or_apt_install "tectonic" "tectonic"; then
    ok "tectonic installed"
  else
    warn "Could not install tectonic"
    PDF_OK=0
  fi

  if [ "$PDF_OK" -eq 0 ]; then
    warn "PDF export partially installed — some tools are missing"
  fi
else
  dim "Skipped PDF export (you can install pandoc + tectonic later)"
fi

# --- Skill installation ---------------------------------------------------

header "Skill Installation"

if [ "$INSTALL_CODEX" -eq 1 ]; then
  if prompt_yes_no "Install ${SKILL_NAME} to ${CODEX_SKILLS_DIR}?" yes; then
    install_skill_to_root "$CODEX_SKILLS_DIR"
  else
    dim "Skipped Codex install"
  fi
fi

if [ "$INSTALL_CLAUDE" -eq 1 ]; then
  if prompt_yes_no "Install ${SKILL_NAME} to ${CLAUDE_SKILLS_DIR}?" yes; then
    install_skill_to_root "$CLAUDE_SKILLS_DIR"
  else
    dim "Skipped Claude install"
  fi
fi

# --- Summary --------------------------------------------------------------

header "Summary"

missing=0
for dep in llmcc agentroot; do
  if command -v "$dep" >/dev/null 2>&1; then
    ok_with_detail "${dep} ready" "$(command -v "$dep")"
  else
    warn "Still missing: ${dep}"
    missing=1
  fi
done

if command -v llama-server >/dev/null 2>&1; then
  ok_with_detail "llama-server ready" "vector embeddings enabled"
else
  printf '%b  llama-server not installed %b(using BM25 text search)%b\n' "$C_DIM_TEXT" "$C_DIM" "$C_RESET"
fi

if command -v pandoc >/dev/null 2>&1 && { command -v tectonic >/dev/null 2>&1 || command -v xelatex >/dev/null 2>&1; }; then
  ok "PDF export ready"
else
  dim "PDF export not available"
fi

if [ "$missing" -eq 1 ]; then
  printf '\n'
  warn "Skill was installed, but required dependencies are still missing."
  warn "Install them manually, then re-run this script if needed."
  dim "  cargo install llmcc"
  dim "  cargo install agentroot"
  dim "If cargo is missing, install Rust first:"
  dim "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

printf '\n%b%b  Done!%b\n\n' "$C_BOLD" "$C_OK" "$C_RESET"
