# vibe-code-audit

Repo-wide audit skill for "vibe-coded" codebases (parallel feature development, semantic duplication, inconsistent cross-cutting concerns, and architectural drift).

## Install

Install from GitHub:

```sh
curl -sSf https://raw.githubusercontent.com/codesoda/vibe-code-audit/main/install.sh | sh
```

Install from a cloned repo:

```sh
sh install.sh
```

## What `install.sh` does

1. Finds the local skill source (`./vibe-code-audit/SKILL.md`) when available.
2. Falls back to downloading `vibe-code-audit/SKILL.md` from GitHub raw when run via `curl | sh`.
3. Checks for required dependencies: `llmcc` and `agentroot`.
4. Offers to install missing dependencies (via `cargo install`).
5. Offers to install the skill into:
   - `~/.codex/skills/vibe-code-audit`
   - `~/.claude/skills/vibe-code-audit`

## Installer options

```sh
sh install.sh --help
```

Supported flags:

- `--yes`: non-interactive mode; accept default install prompts.
- `--skip-deps`: skip dependency checks/install attempts.
- `--codex-only`: only install to `~/.codex/skills`.
- `--claude-only`: only install to `~/.claude/skills`.

Example non-interactive install:

```sh
curl -sSf https://raw.githubusercontent.com/codesoda/vibe-code-audit/main/install.sh | sh -s -- --yes
```

If dependency auto-install fails, run manually:

```sh
cargo install llmcc
cargo install agentroot
```

## Override paths or repo source

Environment overrides:

- `CODEX_SKILLS_DIR`
- `CLAUDE_SKILLS_DIR`
- `VIBE_CODE_AUDIT_REPO_OWNER`
- `VIBE_CODE_AUDIT_REPO_NAME`
- `VIBE_CODE_AUDIT_REPO_REF`
- `VIBE_CODE_AUDIT_RAW_BASE`

Example:

```sh
CODEX_SKILLS_DIR="$HOME/custom/codex-skills" sh install.sh
```
