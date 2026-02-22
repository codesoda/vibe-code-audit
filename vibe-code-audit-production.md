---
allowed-tools: shell filesystem
description: Production-hardened repo audit skill with explicit command
  invocations, deterministic artifact layout, and strict failure modes.
license: Apache-2.0
metadata:
  version: 1.0.0-production
name: vibe-code-audit
---

# vibe-code-audit (Production Hardened)

This version includes explicit shell invocations and deterministic
behavior.

# Required Commands

## Validate Tools

    llmcc --version
    agentroot --version

Fail immediately if non-zero exit code.

# Indexing Commands

## Rust

    llmcc depth1 -o audit_index/llmcc/rust/depth1.dot
    llmcc depth2 -o audit_index/llmcc/rust/depth2.dot
    llmcc depth3 -o audit_index/llmcc/rust/depth3.dot
    llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/rust/depth3_topk.dot

## TypeScript

    llmcc depth2 -o audit_index/llmcc/ts/depth2.dot
    llmcc depth3 -o audit_index/llmcc/ts/depth3.dot
    llmcc depth3 --pagerank-top-k 200 -o audit_index/llmcc/ts/depth3_topk.dot

## agentroot Index

    agentroot index .   --exclude .git   --exclude node_modules   --exclude target   --exclude dist   --exclude build   --exclude .next   --exclude coverage   --output audit_index/agentroot

Validate hybrid search:

    agentroot query "retry backoff"
    agentroot vsearch "permission check"

# Failure Modes

-   If llmcc fails → stop.
-   If agentroot fails → stop.
-   If no results from search → stop.
-   If audit_index not created → stop.

# Determinism Rules

-   Always overwrite previous audit_index.
-   Always record versions in manifest.json.
-   Always record exclude list.
-   Never modify source files.

# Output Requirements

-   audit_report.md
-   audit_index/derived/\*
-   Strict section ordering

Generated: 2026-02-22T08:36:34.555096 UTC
