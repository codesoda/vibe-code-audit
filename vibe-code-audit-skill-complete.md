---
allowed-tools: shell filesystem
compatibility: Requires local filesystem access and permission to
  execute shell commands. Assumes `llmcc` and `agentroot` are installed
  and available on PATH.
description: Complete repo-wide audit skill optimized for vibe-coded
  systems. Includes strict duplication detection, production-hardened
  execution steps, deterministic artifact layout, and structured
  refactor bundle synthesis.
license: Apache-2.0
metadata:
  focus: Rust + React/TypeScript optimized
  version: 1.1.0-complete
name: vibe-code-audit
---

# vibe-code-audit (Complete Edition)

This is the **complete, production-ready** version of the
vibe-code-audit skill.

It combines:

-   Structural hotspot detection (llmcc)
-   Hybrid semantic search (agentroot)
-   Aggressive duplication detection
-   Deterministic artifact generation
-   Strict failure modes
-   Refactor bundle synthesis
-   Standardized reporting (see REPORT_TEMPLATE.md)

------------------------------------------------------------------------

# 1. Prerequisites & Environment Validation

## Required Binaries

Must exist on PATH:

-   llmcc
-   agentroot

Validate before proceeding:

    llmcc --version
    agentroot --version

If either exits non-zero → STOP immediately.

Record versions in:

    audit_index/manifest.json

------------------------------------------------------------------------

# 2. Repository Conditions

Run from repo root or provide path.

At least one of:

-   Cargo.toml
-   package.json
-   tsconfig.json

------------------------------------------------------------------------

# 3. Deterministic Execution Rules

-   Always overwrite existing audit_index
-   Never modify source files
-   Always record:
    -   Tool versions
    -   Timestamp
    -   Exclude list
-   Fail fast on any indexing error
-   If search returns zero results → fail

------------------------------------------------------------------------

# 4. Default Excludes

.git\
node_modules\
target\
dist\
build\
.next\
coverage

------------------------------------------------------------------------

# 5. Indexing Phase (Explicit Commands)

## Rust (if Cargo.toml exists)

    llmcc depth1 -o audit_index/llmcc/rust/depth1.dot
    llmcc depth2 -o audit_index/llmcc/rust/depth2.dot
    llmcc depth3 -o audit_index/llmcc/rust/depth3.dot
    llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/rust/depth3_topk.dot

## TypeScript (if tsconfig.json exists)

    llmcc depth2 -o audit_index/llmcc/ts/depth2.dot
    llmcc depth3 -o audit_index/llmcc/ts/depth3.dot
    llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/ts/depth3_topk.dot

## agentroot Index

    agentroot index .   --exclude .git   --exclude node_modules   --exclude target   --exclude dist   --exclude build   --exclude .next   --exclude coverage   --output audit_index/agentroot

Validate search:

    agentroot query "retry backoff"
    agentroot vsearch "permission check"

------------------------------------------------------------------------

# 6. Strict Duplication Policy

This version applies an aggressive stance.

## Duplication Detection Rules

-   Minimum cluster size: ≥ 2
-   Flag same-intent logic even with naming differences
-   Flag repeated API patterns
-   Flag repeated permission checks
-   Flag forked abstractions
-   Semantic similarity threshold: ≥ 0.82 (review manually)

Duplication is treated as architectural debt.

------------------------------------------------------------------------

# 7. System Map Construction

Document:

-   Backend entrypoints
-   Frontend entrypoints
-   Core domains/modules
-   Data stores/integrations
-   Cross-cutting concerns

Produce:

    audit_index/derived/catalog.json

------------------------------------------------------------------------

# 8. Pattern Inconsistency Scan

Using hybrid search, identify inconsistent implementations of:

-   Auth / authorization
-   Validation
-   Error handling
-   Retry / timeout logic
-   DB access
-   Logging / telemetry
-   Caching
-   API DTO shaping
-   Config management

Inconsistency = risk multiplier.

------------------------------------------------------------------------

# 9. Semantic Duplication Clustering

1.  Use llmcc PageRank top-K as candidate set.
2.  For each hotspot:
    -   Run agentroot semantic similarity.
3.  Form clusters:
    -   Size ≥ 2
    -   Prefer cross-directory clusters
4.  Output:

```{=html}
<!-- -->
```
    audit_index/derived/dup_clusters.md

------------------------------------------------------------------------

# 10. Architecture Drift Analysis

Identify:

-   Cross-layer violations
-   Circular dependencies
-   God modules
-   High centrality files
-   Suspicious cross-domain edges

Propose 3--5 boundary clarifications.

------------------------------------------------------------------------

# 11. Risk Audit

Prioritize:

-   Auth gaps
-   Missing transaction boundaries
-   Partial writes
-   Unsafe input handling
-   Retry inconsistencies
-   Idempotency issues
-   Sensitive logging
-   Silent failures

Each finding must include:

-   Evidence
-   Severity
-   Confidence ≥ 0.65
-   Suggested remediation

------------------------------------------------------------------------

# 12. Refactor Bundle Synthesis

Produce 3--8 bundles.

Each bundle must include:

-   Goal
-   Files affected
-   Step-by-step incremental plan
-   Risk assessment
-   Expected impact
-   Success metric (e.g., collapse N implementations → 1)

Explicitly quantify duplication collapse where possible.

------------------------------------------------------------------------

# 13. Output Requirements

Primary output:

    audit_report.md

Report must follow structure defined in:

    REPORT_TEMPLATE.md

Strict limits:

-   Max 10 findings
-   Max 8 bundles
-   No lint/style noise
-   No speculative issues

------------------------------------------------------------------------

# 14. Definition of Success

This audit succeeds if:

-   Real duplication clusters are identified
-   Architectural drift is surfaced
-   High-leverage consolidation is proposed
-   Output is actionable and prioritized
-   Codebase health improves measurably

------------------------------------------------------------------------

Generated: 2026-02-22T08:45:05.360383 UTC
