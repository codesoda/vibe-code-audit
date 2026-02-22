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

## Allowed tool scope

The skill is intentionally constrained to:

- `Bash(llmcc ...)`
- `Bash(agentroot ...)`
- `Read(vibe-code-audit/**)` for skill docs/templates
- `Read(<target-repo-files>)` for audit evidence

Avoid unrelated command families during the audit flow unless explicitly requested by the user.

## Audit output location

The skill should ask where to write audit artifacts.

Default when not specified:

- `<repo>/vibe-code-audit/<UTC-timestamp>/`

Within that directory:

- `audit_index/` for index + derived artifacts
- `audit_report.md` for the final report

## Indexing script

Use the deterministic index runner:

```sh
bash vibe-code-audit/scripts/run_index.sh \
  --repo /path/to/repo \
  --mode standard
```

If `--output` is omitted, the script automatically uses:
`<repo>/vibe-code-audit/<UTC-timestamp>/`

Modes:

- `fast` (top-k 80)
- `standard` (top-k 200)
- `deep` (top-k 350)

`run_index.sh` auto-detects `llmcc` and `agentroot` CLI variants (legacy vs current syntax), so you should not need to run manual `--help` probes in normal audit flow.

`run_index.sh` auto-runs bounded read-plan generation, producing:
- `audit_index/derived/read_plan.tsv`
- `audit_index/derived/read_plan.md`

## Reliability / non-failure behavior

`run_index.sh` now includes explicit health gates:

- Uses a run-local agentroot database at:
  - `<output_dir>/audit_index/agentroot/index.sqlite`
- Self-heals across CLI syntax drift:
  - `llmcc`: retries across `depthN` and `--dir/--depth` modes.
  - `agentroot`: retries across `index` and `collection add + update` modes.
  - `agentroot query/vsearch`: retries without `--format json` when needed.
- Validates indexing quality via `agentroot status --format json`.
- Fails fast if `agentroot_document_count == 0` after fallback indexing.
- Runs retrieval checks (`query` + `vsearch`) and requires at least one to succeed.
- Continues in degraded mode when vectors are unavailable:
  - `retrieval_mode = "bm25-only"` in `manifest.json`
  - analysis should rely on stronger direct-file evidence in this mode.

Optional auto-embed attempt:

```sh
VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=1 \
bash vibe-code-audit/scripts/run_index.sh --repo /path/to/repo --mode standard
```

CI now runs `tests/run_index_mock_smoke.sh`, which exercises compatibility/fallback paths using mocked `llmcc` and `agentroot` binaries.

## Optional PDF export

After `audit_report.md` is written, you can generate a PDF copy:

```sh
bash vibe-code-audit/scripts/render_report_pdf.sh \
  --report /path/to/output/audit_report.md
```

Behavior:

- If tools are available, it writes `audit_report.pdf` and prints `PDF_PATH=...`.
- If tools are missing, it exits successfully and prints `PDF_SKIPPED=1` with a reason.
- It also tries to render `system_map.png` first (non-fatal) using `render_system_map.sh`.

Required tools for PDF generation:

- `pandoc`
- one supported PDF engine: `tectonic`, `typst`, `xelatex`, `pdflatex`, `wkhtmltopdf`, or `weasyprint`

Optional tools for system map diagram rendering:

- `dot` (Graphviz)
- a dot source file (preferred: `<output_dir>/system_map.dot`; fallback: llmcc depth graph artifacts)

## Claude subagents + models

When running through Claude Code, use subagents and model routing by phase:

- `haiku`: exploration and evidence lookup
- `sonnet`: indexing orchestration, pattern mining, synthesis
- `opus`: high-severity ambiguity resolution only

See `vibe-code-audit/references/claude/subagents-and-model-routing.md` for concrete templates and routing rules.

## What `install.sh` does

1. Finds the local skill source (`./vibe-code-audit/SKILL.md`) when available.
2. Falls back to downloading skill files from `vibe-code-audit/INSTALL_MANIFEST.txt` when run via `curl | sh`.
3. Symlinks local installs to your checked-out `vibe-code-audit/` folder (so updates in repo are immediately reflected).
4. Copies files for remote installs (`curl | sh` path).
5. Checks for required dependencies: `llmcc` and `agentroot`.
6. Offers to install missing dependencies (via `cargo install`).
7. Offers to install the skill into:
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
