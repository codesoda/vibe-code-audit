---
name: vibe-code-audit
description: Repo-wide code audit for vibe-coded systems with parallel feature development, semantic duplication, inconsistent cross-cutting concerns, and architectural drift. Use when Codex must run llmcc and agentroot locally, generate deterministic audit_index artifacts, and produce an evidence-based audit_report.md with prioritized refactor bundles for Rust and React/TypeScript codebases.
---

# Vibe Code Audit (V1)

Execute a deterministic, read-only repository audit optimized for organically grown systems with mixed patterns and duplicated intent.

## Operational Rules

1. Run from repo root unless the user provides an explicit target path.
2. Operate read-only against source code; never edit application files during the audit.
3. Overwrite prior audit artifacts for deterministic output.
4. Fail fast on prerequisite or indexing failures.
5. Avoid lint or style findings; focus on architectural and behavioral risks.

## Required Inputs

1. Require local shell execution and filesystem write access for:
`audit_index/` and `audit_report.md`.
2. Require `llmcc` and `agentroot` on `PATH`.
3. Detect stack markers:
`Cargo.toml`, `tsconfig.json`, `package.json`.

## Preflight

Run and validate:

```bash
llmcc --version
agentroot --version
```

Stop immediately if either command exits non-zero.

Initialize deterministic workspace:

```bash
rm -rf audit_index
mkdir -p audit_index/llmcc audit_index/agentroot audit_index/derived
```

Use this exclude set for all indexing/retrieval steps:

```text
.git
node_modules
target
dist
build
.next
coverage
```

Write `audit_index/manifest.json` with:

1. `generated_at` (UTC ISO-8601 timestamp)
2. `repo_root` (absolute or normalized repo path)
3. `llmcc_version`
4. `agentroot_version`
5. `exclude_patterns`
6. `modes_enabled` (`rust`, `typescript`, `generic`)
7. `pagerank_top_k` (default `200`)

## Indexing Phase

### Rust Structural Graphs (if `Cargo.toml` exists)

Create `audit_index/llmcc/rust/` and run:

```bash
llmcc depth1 -o audit_index/llmcc/rust/depth1.dot
llmcc depth2 -o audit_index/llmcc/rust/depth2.dot
llmcc depth3 -o audit_index/llmcc/rust/depth3.dot
llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/rust/depth3_topk.dot
```

### TypeScript Structural Graphs (if `tsconfig.json` exists)

Create `audit_index/llmcc/ts/` and run:

```bash
llmcc depth2 -o audit_index/llmcc/ts/depth2.dot
llmcc depth3 -o audit_index/llmcc/ts/depth3.dot
llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/ts/depth3_topk.dot
```

### Hybrid Index (always)

Run:

```bash
agentroot index . \
  --exclude .git \
  --exclude node_modules \
  --exclude target \
  --exclude dist \
  --exclude build \
  --exclude .next \
  --exclude coverage \
  --output audit_index/agentroot
```

Stop on any indexing error.

## Retrieval Validation

Confirm both lexical and semantic retrieval produce results:

```bash
agentroot query "retry backoff"
agentroot vsearch "permission check"
```

If either returns zero usable results, stop and report retrieval failure.

## Derived Artifact Generation

Generate all files below before writing the final report:

1. `audit_index/derived/catalog.json`
2. `audit_index/derived/hotspots.json`
3. `audit_index/derived/dup_clusters.md`

### `catalog.json` Requirements

Capture a normalized map of:

1. Backend entrypoints
2. Frontend entrypoints
3. Core domains/modules
4. Integrations and data stores
5. Cross-cutting concerns (auth, validation, logging, retries, config, DTO shaping)

For each item, include evidence paths.

### `hotspots.json` Requirements

Build hotspots primarily from `depth3_topk.dot` outputs.

For each hotspot include:

1. `path_or_symbol`
2. `language` (`rust` or `ts`)
3. `source_graph` (`depth3_topk`)
4. `centrality_hint` (rank/score if available)
5. `reason` (why this is architecturally central)

If both Rust and TS graphs exist, merge and de-duplicate hotspots by path/symbol.

### `dup_clusters.md` Heuristic (V1)

Use llmcc PageRank hotspots as candidate seeds, then expand with semantic similarity queries.

Apply all rules:

1. Include clusters only when size is `>= 3`.
2. Prefer cross-directory clusters over same-folder repetition.
3. Group by shared intent, not by textual sameness.
4. Call out divergence points (error handling, retries, DTO shape, permission checks).
5. Omit weak clusters with low evidence quality.

For each cluster include:

1. Cluster ID
2. Common intent
3. Member files/symbols
4. Key divergence
5. Proposed consolidation target
6. Confidence score

## Analysis Workflow

Perform these analyses in order:

1. System map synthesis from `catalog.json` and graph structure.
2. Hotspot review from `hotspots.json`.
3. Pattern inconsistency scan for:
auth/authorization, validation, error handling, retries/timeouts, DB access, logging/telemetry, caching, DTO shaping, config management.
4. Semantic duplication clustering using the V1 heuristic.
5. Architecture drift analysis:
cross-layer violations, dependency cycles, god-modules, suspicious cross-domain edges.
6. Risk audit focused on high-impact failures:
auth gaps, transaction boundary issues, partial writes, unsafe input handling, idempotency/retry issues, sensitive logging, silent failure patterns.

## Findings Constraints

Enforce all constraints:

1. Cap risk findings to top `10`.
2. Every finding must include concrete evidence file paths.
3. Every finding must include severity and confidence.
4. Minimum confidence is `0.70`.
5. Exclude lint-level or purely stylistic findings.
6. Exclude speculative findings without concrete evidence.

## Refactor Bundle Synthesis

Produce `3` to `8` prioritized bundles.

For each bundle include:

1. Bundle title and objective
2. Affected files/domains
3. Incremental implementation steps
4. Risk and rollback notes
5. Expected impact
6. Success metric

Bias bundles toward consolidation and boundary clarity rather than piecemeal cleanup.

## Final Report

Write `audit_report.md` with this exact section order:

1. Executive Summary
2. System Map
3. Hotspots Overview
4. Pattern Inconsistencies
5. Duplication Clusters
6. Risk Findings
7. Refactor Bundles
8. Roadmap

If bundled template `./REPORT_TEMPLATE.md` is available (relative to this skill directory), align headings and table shape to it while preserving the required section order above.

## Definition of Done

Mark the audit complete only when:

1. All required artifacts exist under `audit_index/`.
2. Retrieval validation succeeded.
3. `audit_report.md` satisfies required sections and constraints.
4. Findings are evidence-backed and confidence-filtered.
5. Output is actionable, prioritized, and focused on consolidation leverage.
