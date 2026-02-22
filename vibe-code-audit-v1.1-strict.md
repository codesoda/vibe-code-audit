---
allowed-tools: shell filesystem
description: Strict repo-wide audit optimized for aggressively detecting
  semantic duplication, architectural drift, and cross-cutting
  inconsistency in vibe-coded systems.
license: Apache-2.0
metadata:
  version: 0.1.1-strict
name: vibe-code-audit
---

# vibe-code-audit (Strict v1.1)

This version applies a **more aggressive duplication stance**.

## Strict Duplication Policy

The audit must:

-   Treat similar logic with small variations as duplication.
-   Flag copy-modify patterns immediately.
-   Flag parallel abstractions as consolidation candidates.
-   Prefer consolidation even if logic is not identical.
-   Highlight divergence in error handling, validation, retries, and DTO
    shaping.

### Duplication Detection Rules

1.  Minimum cluster size: ≥ 2 (not 3).
2.  Flag clusters even within same directory.
3.  Flag "nearly identical control flow" even if naming differs.
4.  Treat repeated API call patterns as duplication.
5.  Treat repeated permission checks as duplication.

If semantic similarity ≥ 0.82 → review cluster manually.

## Refactor Bias

When in doubt: - Recommend shared abstraction. - Recommend
centralization. - Recommend boundary tightening.

## Bundle Expectations

Bundles must explicitly state:

-   How many implementations collapse to one.
-   Estimated LOC reduction.
-   Risk reduction vector.

## Confidence Threshold

Findings allowed if confidence ≥ 0.65 (more aggressive threshold).

Generated: 2026-02-22T08:36:34.555096 UTC
