# vibe-code-audit

Repo-wide audit skill for "vibe-coded" codebases (parallel feature development, semantic duplication, inconsistent cross-cutting concerns, and architectural drift).

## Prerequisites

Required:

- **Rust toolchain** (`cargo`) — the installer can set this up for you via [rustup](https://rustup.rs)

The installer checks for dependencies and offers to install them automatically.

The installer will ask whether you want **vector embeddings** or **BM25-only text search**:

- **BM25-only** — no extra dependencies, works out of the box
- **Vector embeddings** — the installer handles `llama-server` installation and flags the embedding model (~300MB) for automatic download on first audit run

Optional (for PDF export):

- `pandoc` + a PDF engine (`tectonic`, `typst`, `xelatex`, `pdflatex`, `wkhtmltopdf`, or `weasyprint`)
- `dot` (Graphviz) for system map diagrams

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
Avoid `Read` on generated graph/image artifacts (`*.dot`, `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.pdf`); extract with shell tools instead.
Use portable search commands (`rg`, `grep -E`, `grep -oE`) rather than `grep -P`.

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

Stack marker detection is recursive (not only repo root), so nested Rust/TS workspaces are detected for indexing masks and graph generation.

`run_index.sh` auto-detects `llmcc` and `agentroot` CLI variants (legacy vs current syntax), so you should not need to run manual `--help` probes in normal audit flow.

`run_index.sh` auto-runs bounded read-plan generation, producing:
- `audit_index/derived/read_plan.tsv`
- `audit_index/derived/read_plan.md`

`run_index.sh` also auto-runs deterministic derived-artifact bootstrap, producing:
- `audit_index/derived/catalog.json`
- `audit_index/derived/hotspots.json`
- `audit_index/derived/dup_clusters.md`

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
- Runs retrieval checks (`query` + `vsearch`).
- If retrieval checks fail due embed instability (for example agentroot UTF-8 panic or embedding transport failures), run continues in degraded BM25 mode by default.
- Set `VIBE_CODE_AUDIT_RETRIEVAL_STRICT=1` to keep strict failure behavior.
- Continues in degraded mode when vectors are unavailable:
  - `retrieval_mode = "bm25-only"` in `manifest.json`
  - analysis should rely on stronger direct-file evidence in this mode.

Auto-embed attempt (enabled by default):

```sh
bash vibe-code-audit/scripts/run_index.sh --repo /path/to/repo --mode standard
```

Disable auto-embed (for troubleshooting or explicitly BM25-only runs):

```sh
VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0 \
bash vibe-code-audit/scripts/run_index.sh --repo /path/to/repo --mode standard
```

Auto-embed behavior:

- `run_index.sh` calls `vibe-code-audit/scripts/run_agentroot_embed.sh`.
- It first tries `agentroot embed` directly.
- If `agentroot` reports HTTP embedding connection failures, it:
  - retries against an already-running service on `127.0.0.1:8000`, or
  - optionally boots `llama-server` locally (when available) with larger ctx/batch defaults.
- When `run_index.sh` invokes the helper, it keeps a helper-started local embedding server alive through retrieval validation and then cleans it up.
- If embedding still fails (including known `agentroot` UTF-8 chunk panic cases), indexing continues in BM25 mode and does not fail the audit run.
- Manifest now records:
  - `agentroot_embed_attempted`
  - `agentroot_embed_ok`
  - `agentroot_embed_backend`
  - `agentroot_embed_utf8_panic`

Useful embed environment toggles:

```sh
VIBE_CODE_AUDIT_AGENTROOT_AUTO_EMBED=0
VIBE_CODE_AUDIT_EMBED_START_LOCAL=1
VIBE_CODE_AUDIT_EMBED_KEEP_SERVER=1
VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS=60
VIBE_CODE_AUDIT_EMBED_MODEL_PATH="$HOME/.local/share/agentroot/nomic-embed.gguf"
VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL=0
VIBE_CODE_AUDIT_RETRIEVAL_STRICT=0
```

Manual embedding retry (against an existing audit index):

```sh
bash vibe-code-audit/scripts/run_agentroot_embed.sh \
  --db /path/to/output/audit_index/agentroot/index.sqlite \
  --output-dir /path/to/output/audit_index/agentroot
```

CI now runs `tests/run_index_mock_smoke.sh`, which exercises compatibility/fallback paths using mocked `llmcc` and `agentroot` binaries.

## Optional PDF export

After `audit_report.md` is written, you can generate a PDF copy:

```sh
bash vibe-code-audit/scripts/render_report_pdf.sh \
  --report /path/to/output/audit_report.md \
  --map-mode crate
```

Behavior:

- If tools are available, it writes `audit_report.pdf` and prints `PDF_PATH=...`.
- If tools are missing, it exits successfully and prints `PDF_SKIPPED=1` with a reason.
- It also tries to render `system_map.png` first (non-fatal) using `render_system_map.sh`.
- If PDF render fails due oversized diagram content, it retries without embedding the system map image.
- On fallback success, it also prints `PDF_NOTE=rendered_without_system_map`.

Required tools for PDF generation:

- `pandoc`
- one supported PDF engine: `tectonic`, `typst`, `xelatex`, `pdflatex`, `wkhtmltopdf`, or `weasyprint`

Optional tools for system map diagram rendering:

- `dot` (Graphviz)
- a dot source file (preferred: `<output_dir>/system_map.dot`; fallback: llmcc depth graph artifacts)

Optional diagram control:

```sh
bash vibe-code-audit/scripts/render_system_map.sh \
  --report /path/to/output/audit_report.md \
  --mode crate
```

Modes:
- `auto` (default): prefers smaller crate/module graphs first
- `crate`: strongly prefers crate-level readability
- `full`: prefers dense full graphs

## Claude subagents + models

When running through Claude Code, use subagents and model routing by phase:

- `haiku`: exploration and evidence lookup
- `sonnet`: indexing orchestration, pattern mining, synthesis
- `opus`: high-severity ambiguity resolution only

See `vibe-code-audit/references/claude/subagents-and-model-routing.md` for concrete templates and routing rules.

Timeout guidance for Claude Code:

- `run_index.sh` with auto-embed can exceed 5 minutes on medium repos.
- Prefer background execution + `TaskOutput` polling.
- Use a larger tool timeout for blocking waits (recommended: `900000` to `1800000` ms).

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
