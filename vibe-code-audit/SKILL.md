---
name: vibe-code-audit
description: Catalogue-first repo audit for vibe-coded systems. Use when Codex must run llmcc and agentroot, discover semantic duplication and architecture drift, and produce evidence-based refactor bundles with high-confidence findings. Supports progressive disclosure via references/core and stack-specific references/packs.
allowed-tools:
  - Bash(*run_index.sh*)
  - Bash(*build_read_plan.sh*)
  - Bash(*render_system_map.sh*)
  - Bash(*render_report_pdf.sh*)
  - Bash(llmcc *)
  - Bash(agentroot *)
  - Bash(rg *)
  - Bash(sed -n *)
  - Bash(cat *)
  - Read(vibe-code-audit/**)
  - Read
---

# Vibe Code Audit

Run a deterministic, read-only audit optimized for messy, organically grown codebases where the same intent is implemented multiple ways.

## Progressive Disclosure

Read only what is needed:

1. For normal runs, execute scripts first; avoid opening references before script execution.
2. Do not read `references/packs/*.md` in default flow.
3. Load `references/core/process.md` only when script fallback or troubleshooting is required.
4. Load `references/core/*.md` based on the active phase.
5. Load `references/packs/*.md` only when stack-specific behavior is ambiguous.
6. If running in Claude Code, load `references/claude/subagents-and-model-routing.md` only when setting up subagents/models.

Stack pack selection:

1. `Cargo.toml` -> `references/packs/rust-backend.md`
2. `package.json` + `tsconfig.json` + `next.config.*` -> `references/packs/react-next.md`
3. `package.json` + `express` usage -> `references/packs/node-express.md`
4. `Gemfile` + Rails markers -> `references/packs/rails.md`

If no pack matches, continue with core language-agnostic rules.

## Inputs

1. `repo_path` (default `.`)
2. Optional `output_dir` (if omitted, `run_index.sh` auto-creates `<repo_path>/vibe-code-audit/<UTC-timestamp>/`)
3. Optional focus areas: `duplication`, `risk`, `architecture`, `maintainability`
4. Optional budget mode: `fast`, `standard`, `deep` (default `standard`)
5. `skill_dir` (path to this installed skill directory; resolve from runtime context)

Budget behavior:

1. `fast`: prioritize top-central hotspots and strongest evidence.
2. `standard`: full V1 flow.
3. `deep`: broaden duplication and boundary analysis coverage.

## Output Location

Resolve output path at the beginning of the run:

1. Ask user where to write audit artifacts only if they care to customize location.
2. If no explicit output is provided, let `run_index.sh` choose the default path.
3. Do not run standalone timestamp shell commands to construct output paths.
4. Write index artifacts to `<output_dir>/audit_index/`.
5. Write final report to `<output_dir>/audit_report.md`.
6. Only create/overwrite files under `<output_dir>`.

## Guardrails

1. Stay read-only against source files.
2. Avoid destructive commands.
3. Avoid lint/style-only findings.
4. Avoid speculative findings.
5. Do not run full test suites unless user asks.

## Context Budget Rules

Prevent context-window failures during large-repo audits:

1. Do not read entire large source files by default.
2. Start with file discovery (`rg --files`) and targeted search (`rg <pattern>`).
3. Read only relevant slices around evidence (`sed -n start,endp`), not whole files.
4. If a file exceeds ~800 lines, read only targeted sections unless user explicitly asks for full-file review.
5. Avoid parallel bulk file reads across the whole repo.
6. Prefer artifact-driven analysis (`manifest`, `catalog`, `hotspots`, `dup_clusters`) over exhaustive raw-file ingestion.
7. Do not open raw `audit_index/llmcc/**/*.dot` files in normal flow; use `derived/hotspots.json` and catalog artifacts instead.

## Claude Execution Mode

When running this skill via Claude Code:

1. Use subagents to keep main-thread context small.
2. Route by task complexity:
   - `haiku` for exploration and evidence lookup
   - `sonnet` for indexing orchestration, pattern mining, and synthesis
   - `opus` only for ambiguous high-severity adjudication
3. Use bounded objectives per subagent; avoid long multi-purpose prompts.
4. Follow `references/claude/subagents-and-model-routing.md`.

## Allowed Tools

Use only the following tool classes for this skill unless the user explicitly expands scope:

1. `Bash(<skill_dir>/scripts/run_index.sh ...)` for deterministic preflight + indexing.
2. `Bash(<skill_dir>/scripts/build_read_plan.sh ...)` for bounded evidence slice planning.
3. `Bash(<skill_dir>/scripts/render_report_pdf.sh ...)` for optional report PDF generation.
4. `Bash(<skill_dir>/scripts/render_system_map.sh ...)` for optional system map rendering.
5. `Bash(llmcc ...)` for structural graph generation and PageRank hotspot extraction.
6. `Bash(agentroot ...)` for hybrid indexing, lexical query, and semantic search.
7. `Read(vibe-code-audit/**)` for reading skill instructions, references, and templates.
8. `Read(<target-repo-files>)` for read-only audit evidence collection.

Do not run unrelated command families during the audit flow.

## Required Tools

Dependencies:
- `llmcc`
- `agentroot`

Optional PDF dependencies:
- `pandoc`
- one PDF engine (`tectonic`, `typst`, `xelatex`, `pdflatex`, `wkhtmltopdf`, or `weasyprint`)

Validation policy:

1. In normal flow, `run_index.sh` performs dependency validation.
2. Do not run standalone version checks before calling `run_index.sh`.
3. Run direct version checks only in manual fallback or troubleshooting mode.

## Tool Invocation Policy

Use deterministic command execution for indexing:

1. Resolve `skill_dir` first.
2. Execute a single Bash action:
   - `<skill_dir>/scripts/run_index.sh --repo <repo_path> --mode <budget_mode>`
3. If custom output is needed, pass `--output <output_dir>` to the same command.
4. `run_index.sh` auto-runs read-plan generation unless `--skip-read-plan` is used.
5. Do not run separate preflight commands (`llmcc --version`, `agentroot --version`) outside scripts in normal flow.
6. Use direct `llmcc`/`agentroot` commands only if script execution is unavailable.
7. Do not run exploratory `llmcc --help` or `agentroot --help` during normal audit flow.
8. Use `--help` only as fallback when an expected command fails with an unknown command/flag error.
9. Run all index commands from the resolved `repo_path`.
10. Verify expected artifact files/directories after each indexing stage.
11. Read `<output_dir>/audit_index/manifest.json` before analysis and enforce:
   - `agentroot_document_count > 0`
   - `retrieval_query_ok == 1` or `retrieval_vsearch_ok == 1`
12. If `retrieval_mode` is `bm25-only`, continue in degraded mode (do not abort), but rely more on direct file evidence and explicit `rg` corroboration.
13. Avoid `Read` on large generated artifacts (`*.dot`, huge logs) unless recovery mode requires it.
14. `run_index.sh` already includes CLI-compatibility fallbacks; if it fails, rerun once and inspect its stderr instead of manually re-implementing indexing with many ad-hoc commands.
15. After writing `<output_dir>/audit_report.md`, run:
   - `<skill_dir>/scripts/render_report_pdf.sh --report <output_dir>/audit_report.md`
16. `render_report_pdf.sh` attempts `render_system_map.sh` automatically first (non-fatal).
17. Treat system map and PDF export as optional:
   - if script output contains `SYSTEM_MAP_PATH=...`, reference the generated image
   - if script output contains `SYSTEM_MAP_SKIPPED=1`, continue without failing the audit
18. For PDF:
   - if script output contains `PDF_PATH=...`, reference the generated PDF
   - if script output contains `PDF_SKIPPED=1`, continue without failing the audit

## Required Outputs

Must produce:

1. `<output_dir>/audit_index/manifest.json`
2. `<output_dir>/audit_index/llmcc/` artifacts
3. `<output_dir>/audit_index/agentroot/` artifacts
4. `<output_dir>/audit_index/agentroot/status.json` (or equivalent status artifact)
5. `<output_dir>/audit_index/derived/catalog.json`
6. `<output_dir>/audit_index/derived/hotspots.json`
7. `<output_dir>/audit_index/derived/dup_clusters.md`
8. `<output_dir>/audit_index/derived/read_plan.tsv`
9. `<output_dir>/audit_index/derived/read_plan.md`
10. `<output_dir>/audit_report.md`

Optional output:

11. `<output_dir>/audit_report.pdf` (only when PDF tooling is available)
12. `<output_dir>/system_map.png` (only when Graphviz and a dot source are available)

## Execution Contract

Execute phases from `references/core/process.md` in order:

1. Phase 0: Scope and stack detection
2. Phase 1: Discovery and catalog-first indexing
3. Phase 2: Pattern mining for inconsistent implementations
4. Phase 3: Semantic duplication clustering
5. Phase 4: Architecture and boundaries audit
6. Phase 5: Risk audit
7. Phase 6: Maintainability and DX audit
8. Phase 7: Prioritization and refactor bundle synthesis
9. Phase 8: Optional system map rendering and PDF export

Use supporting references as needed:

1. `references/core/inventory.md`
2. `references/core/pattern-mining.md`
3. `references/core/duplication.md`
4. `references/core/architecture.md`
5. `references/core/risk.md`
6. `references/core/maintainability.md`
7. `references/core/prioritization.md`
8. `references/core/agent-roles.md`
9. `references/core/output-schema.md`
10. `references/core/context-budget.md`
11. `references/claude/subagents-and-model-routing.md`

## Findings Rules

1. Cap findings to top `10`.
2. Cap bundles to `3` to `8`.
3. Every finding must include evidence file paths.
4. Every finding must include severity, confidence, effort, and blast radius.
5. Apply severity-aware confidence thresholds:
   - `S0/S1`: keep only if confidence `>= 0.70`
   - `S2/S3`: keep only if confidence `>= 0.85`
6. Treat inconsistency as a risk multiplier.
7. If `manifest.retrieval_mode == "bm25-only"`, lower confidence for semantic-duplication claims unless corroborated by direct code evidence.

## Report Contract

Write `<output_dir>/audit_report.md` using this exact section order:

1. Executive Summary
2. System Map
3. Hotspots Overview
4. Pattern Inconsistencies
5. Duplication Clusters
6. Risk Findings
7. Refactor Bundles
8. Roadmap

If `./REPORT_TEMPLATE.md` exists in this skill directory, align headings and table layout to it.

Roadmap must include two lanes:

1. Quick Wins (1-3 days)
2. Deep Work (1-6 weeks)

## Definition of Done

Complete only when:

1. Required artifacts exist and are populated.
2. Retrieval validation succeeded (`agentroot_document_count > 0` and at least one retrieval check succeeded).
3. Findings are confidence-filtered and evidence-backed.
4. Refactor bundles are actionable and sequenced.
5. Report emphasizes consolidation leverage over issue count.
