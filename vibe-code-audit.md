---
allowed-tools: shell filesystem
compatibility: Requires local filesystem access and permission to
  execute shell commands. Assumes `llmcc` and `agentroot` are installed
  and available on PATH.
description: Repo-wide code audit designed for "vibe coded" software.
  Automatically runs llmcc (multi-depth structural graphs) and agentroot
  (hybrid BM25 + embedding search) locally, then produces a prioritized
  audit report focused on semantic duplication, inconsistent patterns,
  architectural drift, and high-leverage refactor bundles.
license: Apache-2.0
metadata:
  focus: Rust + React/TypeScript optimized
  version: 0.1.0
name: vibe-code-audit
---

# vibe-code-audit

A repo-wide audit skill optimized for "vibe coded" systems: - Parallel
feature development - Duplicated logic with slight variations -
Inconsistent cross-cutting patterns - Architectural drift - Unclear
boundaries

This skill runs structural analysis (llmcc) and hybrid semantic search
(agentroot) and synthesizes findings into actionable **refactor
bundles**, not just issue lists.

------------------------------------------------------------------------

# 1. Prerequisites & Environment Validation

## Required Binaries

The following must be available on PATH:

-   `llmcc`
-   `agentroot`

Validate before proceeding:

    llmcc --version
    agentroot --version

If either fails → stop immediately and output a clear error.

## Repository Conditions

Run from repo root or provide a repo path.

At least one of: - `Cargo.toml` - `package.json` - `tsconfig.json`

If none found → warn and continue in generic mode.

## Required Permissions

-   Read access to entire repo
-   Permission to create:
    -   `./audit_index/`
    -   `./audit_report.md`
-   Permission to execute shell commands

Fail fast if restricted.

------------------------------------------------------------------------

# 2. Output Contract

Artifacts written to:

    ./audit_index/

Final report written to:

    ./audit_report.md

------------------------------------------------------------------------

# 3. Execution Phases

## Phase A --- Indexing

1.  Create `audit_index/`
2.  Write `manifest.json` with:
    -   llmcc version
    -   agentroot version
    -   timestamp
    -   exclude patterns

Default excludes:

    .git
    node_modules
    target
    dist
    build
    .next
    coverage

### Run llmcc

If `Cargo.toml` exists: - depth1 (crate graph) - depth2 (module graph) -
depth3 (file/symbol graph) - depth3 PageRank top-K

Store under:

    audit_index/llmcc/rust/

If `tsconfig.json` exists: - depth2 - depth3 - depth3 PageRank top-K

Store under:

    audit_index/llmcc/ts/

### Run agentroot

Index repository with excludes.

Store under:

    audit_index/agentroot/

Validate: - Hybrid search returns results - Semantic similarity returns
results

------------------------------------------------------------------------

## Phase B --- System Map

Document: - Backend entrypoints - Frontend entrypoints - Core
domains/modules - Data stores/integrations - Cross-cutting concerns

Produce: - System Map section - `catalog.json`

------------------------------------------------------------------------

## Phase C --- Pattern Inconsistency Scan

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

## Phase D --- Semantic Duplication Discovery (V1 Heuristic)

1.  Use llmcc PageRank top-K as hotspot candidates.
2.  For each hotspot:
    -   Run semantic similarity search.
    -   Identify similar chunks.
3.  Form clusters:
    -   Minimum size ≥ 3
    -   Prefer cross-directory clusters

Produce:

    audit_index/derived/dup_clusters.md

------------------------------------------------------------------------

## Phase E --- Architecture Drift

Identify: - Cross-layer violations - Circular dependency risks - God
modules - High-centrality files - Suspicious cross-domain edges

Propose 3--5 boundary clarification moves.

------------------------------------------------------------------------

## Phase F --- Risk Audit

Prioritize: - Auth gaps - Missing transaction boundaries - Partial
writes - Unsafe input handling - Retry inconsistencies - Idempotency
issues - Sensitive logging - Silent failures

Each finding must include: - Evidence - Severity - Confidence ≥ 0.7 -
Suggested remediation

------------------------------------------------------------------------

## Phase G --- Refactor Bundles

Convert findings into 3--8 bundles.

Each bundle must include: - Clear goal - Affected areas - Incremental
steps - Risk assessment - Expected impact - Success metric

------------------------------------------------------------------------

# 4. Quality Bar

The audit must:

-   Avoid lint noise
-   Avoid style nitpicks
-   Avoid speculative findings
-   Cite concrete evidence
-   Cap findings to top 10
-   Cap bundles to 3--8
-   Prefer depth over breadth

------------------------------------------------------------------------

# 5. Report Structure

`audit_report.md` must include:

1.  Executive Summary
2.  System Map
3.  Hotspots Overview
4.  Pattern Inconsistencies
5.  Duplication Clusters
6.  Risk Findings
7.  Refactor Bundles
8.  Suggested Roadmap

------------------------------------------------------------------------

Generated: 2026-02-22T08:35:29.517981 UTC
