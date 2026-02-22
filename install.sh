#!/bin/sh
set -eu

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

info() {
  printf "[%s] %s\n" "$SKILL_NAME" "$*"
}

warn() {
  printf "[%s] WARNING: %s\n" "$SKILL_NAME" "$*" >&2
}

die() {
  printf "[%s] ERROR: %s\n" "$SKILL_NAME" "$*" >&2
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
      printf "%s %s " "$question" "$prompt" > /dev/tty
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
        *) printf "Please answer yes or no.\n" > /dev/tty ;;
      esac
    done
  fi

  [ "$fallback" = "yes" ]
}

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

resolve_source_dir() {
  if [ -f "./${SKILL_NAME}/SKILL.md" ]; then
    SOURCE_DIR="$(pwd)/${SKILL_NAME}"
    SOURCE_MODE="local"
    info "Using local skill source at ${SOURCE_DIR}."
    return 0
  fi

  case "$0" in
    */*)
      script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
      if [ -n "$script_dir" ] && [ -f "$script_dir/${SKILL_NAME}/SKILL.md" ]; then
        SOURCE_DIR="$script_dir/${SKILL_NAME}"
        SOURCE_MODE="local"
        info "Using skill source next to install.sh at ${SOURCE_DIR}."
        return 0
      fi
      ;;
  esac

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${SKILL_NAME}.XXXXXX")"
  SOURCE_DIR="${TMP_DIR}/${SKILL_NAME}"
  SOURCE_MODE="remote"
  mkdir -p "$SOURCE_DIR"

  remote_skill_url="${RAW_BASE}/${SKILL_NAME}/SKILL.md"
  remote_report_template_url="${RAW_BASE}/${SKILL_NAME}/REPORT_TEMPLATE.md"
  info "Fetching skill from ${remote_skill_url}."

  if ! fetch_to_file "$remote_skill_url" "${SOURCE_DIR}/SKILL.md"; then
    die "Unable to download SKILL.md (need curl or wget, and network access)."
  fi

  info "Fetching template from ${remote_report_template_url}."
  if ! fetch_to_file "$remote_report_template_url" "${SOURCE_DIR}/REPORT_TEMPLATE.md"; then
    warn "Could not download REPORT_TEMPLATE.md; continuing without it."
  fi
}

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

  info "Installing Rust toolchain with rustup."
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
    info "Dependency found: ${dep}"
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
    info "Dependency installed: ${dep}"
    return 0
  fi

  warn "Install command completed but ${dep} is still not on PATH."
  return 1
}

install_skill_to_root() {
  root="$1"
  target="${root}/${SKILL_NAME}"

  mkdir -p "$root"
  rm -rf "$target"

  if [ "$SOURCE_MODE" = "local" ]; then
    ln -s "$SOURCE_DIR" "$target"
    info "Symlinked skill to ${target} -> ${SOURCE_DIR}"
    return 0
  fi

  mkdir -p "$target"
  cp -R "${SOURCE_DIR}/." "$target/"
  info "Installed skill to ${target}"
}

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

resolve_source_dir

if [ "$SKIP_DEPS" -eq 1 ]; then
  info "Skipping dependency checks (--skip-deps)."
else
  install_dependency "llmcc" || true
  install_dependency "agentroot" || true
fi

if [ "$INSTALL_CODEX" -eq 1 ]; then
  if prompt_yes_no "Install ${SKILL_NAME} to ${CODEX_SKILLS_DIR}?" yes; then
    install_skill_to_root "$CODEX_SKILLS_DIR"
  else
    info "Skipped Codex install."
  fi
fi

if [ "$INSTALL_CLAUDE" -eq 1 ]; then
  if prompt_yes_no "Install ${SKILL_NAME} to ${CLAUDE_SKILLS_DIR}?" yes; then
    install_skill_to_root "$CLAUDE_SKILLS_DIR"
  else
    info "Skipped Claude install."
  fi
fi

missing=0
for dep in llmcc agentroot; do
  if command -v "$dep" >/dev/null 2>&1; then
    info "Ready: ${dep} ($(command -v "$dep"))"
  else
    warn "Still missing: ${dep}"
    missing=1
  fi
done

if [ "$missing" -eq 1 ]; then
  warn "Skill was installed, but required dependencies are still missing."
  warn "Install them manually, then re-run this script if needed."
  warn "If cargo is installed:"
  warn "  cargo install llmcc"
  warn "  cargo install agentroot"
  warn "If cargo is missing, install Rust first:"
  warn "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

info "Done."
