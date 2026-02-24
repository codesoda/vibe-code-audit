# Core Process

## Mode Settings

Use mode-dependent scope controls:

1. `fast`: PageRank top 80 hotspots, max 6 findings, max 4 bundles.
2. `standard`: PageRank top 200 hotspots, max 10 findings, max 8 bundles.
3. `deep`: PageRank top 350 hotspots, broaden semantic expansion.

Map mode to `TOP_K`:

1. `fast` -> `TOP_K=80`
2. `standard` -> `TOP_K=200`
3. `deep` -> `TOP_K=350`

## Phase 0: Scope and Guardrails

1. Resolve repo root.
2. Ask user for output location only when custom path is needed.
3. If user does not choose one, leave output unset and let `run_index.sh` resolve default output path.
4. Set:
   - `OUTPUT_DIR` optional input (may be empty pre-index)
   - `AUDIT_INDEX_DIR` and `AUDIT_REPORT_PATH` after reading resolved output from `run_index.sh`
5. Detect stack markers (`Cargo.toml`, `tsconfig.json`, `package.json`, `Gemfile`).
6. Do not load stack pack files by default.
7. Load matching files from `references/packs/` only when stack-specific behavior is ambiguous.
8. Confirm read-only posture and non-destructive command policy.
9. Set context-budget policy:
   - Use targeted grep + sliced reads.
   - Avoid full-file reads for very large files.
   - Prefer index artifacts and sampled evidence.
10. If running in Claude Code, apply subagent/model routing from:
   - `references/claude/subagents-and-model-routing.md`
11. Resolve `SKILL_DIR`:
   - Prefer runtime-provided skill base directory when available.
   - Fallback to `~/.claude/skills/vibe-code-audit` then `~/.codex/skills/vibe-code-audit`.

## Phase 1: Discovery and Catalog-First Indexing

Preferred path:

```bash
if [ -n "${OUTPUT_DIR:-}" ]; then
  RUN_OUT="$(bash "$SKILL_DIR/scripts/run_index.sh" --repo "$REPO_PATH" --output "$OUTPUT_DIR" --mode "$MODE")"
else
  RUN_OUT="$(bash "$SKILL_DIR/scripts/run_index.sh" --repo "$REPO_PATH" --mode "$MODE")"
fi
OUTPUT_DIR="$(printf '%s\n' "$RUN_OUT" | awk -F= '/^OUTPUT_DIR=/{print $2}' | tail -n1)"
AUDIT_INDEX_DIR="$OUTPUT_DIR/audit_index"
AUDIT_REPORT_PATH="$OUTPUT_DIR/audit_report.md"
MANIFEST_PATH="$AUDIT_INDEX_DIR/manifest.json"

DOC_COUNT="$(sed -n 's/.*"agentroot_document_count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$MANIFEST_PATH" | head -n1)"
QUERY_OK="$(sed -n 's/.*"retrieval_query_ok"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$MANIFEST_PATH" | head -n1)"
VSEARCH_OK="$(sed -n 's/.*"retrieval_vsearch_ok"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$MANIFEST_PATH" | head -n1)"
RETRIEVAL_MODE="$(sed -n 's/.*"retrieval_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST_PATH" | head -n1)"

[ "${DOC_COUNT:-0}" -gt 0 ] || { echo "agentroot document_count is zero"; exit 1; }
[ "${QUERY_OK:-0}" -eq 1 ] || [ "${VSEARCH_OK:-0}" -eq 1 ] || [ "${RETRIEVAL_MODE:-}" = "bm25-only" ] || { echo "retrieval checks failed without bm25 fallback"; exit 1; }
[ -s "$AUDIT_INDEX_DIR/derived/catalog.json" ] || { echo "catalog.json missing"; exit 1; }
[ -s "$AUDIT_INDEX_DIR/derived/hotspots.json" ] || { echo "hotspots.json missing"; exit 1; }
[ -s "$AUDIT_INDEX_DIR/derived/dup_clusters.md" ] || { echo "dup_clusters.md missing"; exit 1; }
```

If script path is unavailable, execute the manual sequence below.
If `build_derived_artifacts.sh` is unavailable, still create `catalog.json`, `hotspots.json`, and `dup_clusters.md` manually before analysis.
If `build_read_plan.sh` is unavailable, still create `read_plan.tsv` and `read_plan.md` manually with bounded limits from `references/core/context-budget.md`.
When running through Claude Code tools, use a larger timeout for indexing (`>=900000 ms` recommended) or run in background and poll output.

### Preflight

Command policy:

1. Preferred route is the single scripted command above.
2. Execute manual commands only if scripted path is unavailable.
3. Avoid exploratory/repeated `--help` calls; allow one targeted `--help` probe per tool for CLI compatibility detection.
4. Do not run standalone timestamp commands for output path generation.
5. Run from repo root (`cd "$REPO_PATH"`).
6. If `run_index.sh` fails, rerun it once after checking stderr; avoid manual command sprawl unless scripted path is unavailable.
7. Use portable search syntax only (`rg`, `grep -E`, `grep -oE`); do not use `grep -P`.
8. Do not `Read` generated graph/image artifacts (`*.dot`, `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.pdf`).
9. If a required file read fails, retry sequentially instead of launching sibling `Read` calls in parallel.

Run:

```bash
cd "$REPO_PATH"
llmcc --version
agentroot --version
```

Create deterministic output tree:

```bash
rm -rf "$AUDIT_INDEX_DIR"
mkdir -p "$AUDIT_INDEX_DIR/llmcc/rust" "$AUDIT_INDEX_DIR/llmcc/ts"
mkdir -p "$AUDIT_INDEX_DIR/agentroot" "$AUDIT_INDEX_DIR/derived"

AGENTROOT_DB="$AUDIT_INDEX_DIR/agentroot/index.sqlite"
export AGENTROOT_DB
```

Use excludes:

```text
.git
node_modules
target
dist
build
.next
coverage
```

Write `$AUDIT_INDEX_DIR/manifest.json` with:

1. `generated_at`
2. `repo_root`
3. `output_dir`
4. `llmcc_version`
5. `llmcc_mode`
6. `agentroot_version`
7. `agentroot_mode`
8. `agentroot_db`
9. `agentroot_collection` (or `null`)
10. `agentroot_collections`
11. `agentroot_document_count`
12. `agentroot_embedded_count`
13. `agentroot_embed_attempted`
14. `agentroot_embed_ok`
15. `agentroot_embed_backend`
16. `agentroot_embed_utf8_panic`
17. `retrieval_mode`
18. `retrieval_query_ok`
19. `retrieval_vsearch_ok`
20. `exclude_patterns`
21. `modes_enabled`
22. `pagerank_top_k`
23. `budget_mode`
24. `command_runner`

### Structural Graphs

Detect llmcc command style:

```bash
if llmcc --help | grep -q -- '--dir <DIR>'; then
  LLMCC_MODE="flag-depth"
else
  LLMCC_MODE="legacy-depth-subcommands"
fi
```

If `Cargo.toml` exists:

```bash
if [ "$LLMCC_MODE" = "flag-depth" ]; then
  llmcc --dir "$REPO_PATH" --lang rust --graph --depth 1 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth1.dot"
  llmcc --dir "$REPO_PATH" --lang rust --graph --depth 2 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth2.dot"
  llmcc --dir "$REPO_PATH" --lang rust --graph --depth 3 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth3.dot"
  llmcc --dir "$REPO_PATH" --lang rust --graph --depth 3 --pagerank-top-k "$TOP_K" -o "$AUDIT_INDEX_DIR/llmcc/rust/depth3_topk.dot"
else
  llmcc depth1 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth1.dot"
  llmcc depth2 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth2.dot"
  llmcc depth3 -o "$AUDIT_INDEX_DIR/llmcc/rust/depth3.dot"
  llmcc depth3 --pagerank-top-k "$TOP_K" -o "$AUDIT_INDEX_DIR/llmcc/rust/depth3_topk.dot"
fi
test -s "$AUDIT_INDEX_DIR/llmcc/rust/depth3_topk.dot"
```

If `tsconfig.json` exists:

```bash
if [ "$LLMCC_MODE" = "flag-depth" ]; then
  llmcc --dir "$REPO_PATH" --lang typescript --graph --depth 2 -o "$AUDIT_INDEX_DIR/llmcc/ts/depth2.dot"
  llmcc --dir "$REPO_PATH" --lang typescript --graph --depth 3 -o "$AUDIT_INDEX_DIR/llmcc/ts/depth3.dot"
  llmcc --dir "$REPO_PATH" --lang typescript --graph --depth 3 --pagerank-top-k "$TOP_K" -o "$AUDIT_INDEX_DIR/llmcc/ts/depth3_topk.dot"
else
  llmcc depth2 -o "$AUDIT_INDEX_DIR/llmcc/ts/depth2.dot"
  llmcc depth3 -o "$AUDIT_INDEX_DIR/llmcc/ts/depth3.dot"
  llmcc depth3 --pagerank-top-k "$TOP_K" -o "$AUDIT_INDEX_DIR/llmcc/ts/depth3_topk.dot"
fi
test -s "$AUDIT_INDEX_DIR/llmcc/ts/depth3_topk.dot"
```

### Hybrid Search Index

```bash
if agentroot --help | grep -Eq '^[[:space:]]+index([[:space:]]|$)'; then
  AGENTROOT_MODE="index-subcommand"
else
  AGENTROOT_MODE="collection-update"
fi

if [ "$AGENTROOT_MODE" = "index-subcommand" ]; then
  agentroot index . \
    --exclude .git \
    --exclude node_modules \
    --exclude target \
    --exclude dist \
    --exclude build \
    --exclude .next \
    --exclude coverage \
    --output "$AUDIT_INDEX_DIR/agentroot"
  AGENTROOT_COLLECTION=""
else
  AGENTROOT_COLLECTION="vca-$(basename "$REPO_PATH")-$(date -u +%Y%m%d%H%M%S)"
  # Prefer stack-specific single masks. Brace expansion masks are not reliable.
  if [ -f Cargo.toml ]; then
    MASK='**/*.rs'
  elif [ -f tsconfig.json ] || [ -f package.json ]; then
    MASK='**/*.ts'
  else
    MASK='**/*.md'
  fi
  agentroot collection add "$REPO_PATH" --name "$AGENTROOT_COLLECTION" --mask "$MASK" > "$AUDIT_INDEX_DIR/agentroot/collection_add.txt" 2>&1
  agentroot update > "$AUDIT_INDEX_DIR/agentroot/update.txt" 2>&1
  agentroot status --format json > "$AUDIT_INDEX_DIR/agentroot/status.json" 2>&1
  printf '%s\n' "$AGENTROOT_COLLECTION" > "$AUDIT_INDEX_DIR/agentroot/collection_name.txt"
fi
```

### Retrieval Validation

```bash
if [ "$AGENTROOT_MODE" = "index-subcommand" ]; then
  agentroot query "retry backoff" --format json > "$AUDIT_INDEX_DIR/agentroot/query_check.txt"
  agentroot vsearch "permission check" --format json > "$AUDIT_INDEX_DIR/agentroot/vsearch_check.txt"
else
  agentroot query "retry backoff" --format json > "$AUDIT_INDEX_DIR/agentroot/query_check.txt"
  agentroot vsearch "permission check" --format json > "$AUDIT_INDEX_DIR/agentroot/vsearch_check.txt"
fi
test -s "$AUDIT_INDEX_DIR/agentroot/query_check.txt"
test -s "$AUDIT_INDEX_DIR/agentroot/vsearch_check.txt"
```

If output indicates missing vectors, continue in BM25-only mode and mark `retrieval_mode` accordingly in `manifest.json`.

If `agentroot_embedded_count == 0` (auto-embed is enabled by default):

1. Prefer `run_index.sh` auto flow (it invokes `run_agentroot_embed.sh`).
2. Do not hand-roll ad-hoc embed orchestration unless troubleshooting.
3. If embed still fails, keep the run non-fatal and proceed in BM25-only mode.

### Required Derived Artifacts

Generate:

1. `$AUDIT_INDEX_DIR/derived/catalog.json`
2. `$AUDIT_INDEX_DIR/derived/hotspots.json`
3. `$AUDIT_INDEX_DIR/derived/dup_clusters.md`
4. `$AUDIT_INDEX_DIR/derived/read_plan.tsv`
5. `$AUDIT_INDEX_DIR/derived/read_plan.md`

`catalog.json` is the source of truth for system mapping.
`run_index.sh` should call `build_derived_artifacts.sh` so these files exist before analysis starts.

Fallback rule (only when needed):

1. If a documented command fails due CLI drift, run one targeted `--help` call for that tool.
2. If `agentroot` fails due DB-path issues, set `AGENTROOT_DB` to a writable file under `audit_index/agentroot/`.
3. Adapt the command, continue the run, and record the adaptation in `manifest.json`.

## Phase 2: Pattern Mining

Follow `references/core/pattern-mining.md` and emit findings for inconsistent implementations of:

1. Auth/authZ
2. Validation
3. Error handling
4. Retry/timeout policies
5. DB access patterns
6. Logging/telemetry
7. Caching
8. DTO/serialization shape
9. Config defaults and key naming

Treat inconsistency as risk multiplier.

Execution constraints for this phase:

1. Use pattern-first retrieval (`rg`, `agentroot query`, `agentroot vsearch`), then open only high-signal files.
2. Use slices from `$AUDIT_INDEX_DIR/derived/read_plan.tsv` as the primary evidence budget.
3. For large files, read only relevant sections around matched lines.
4. Do not launch broad parallel reads of every source file.
5. If tool output indicates token/size limits, reduce file scope and continue with sampled evidence.
6. For generated graph data, use shell extraction (`rg`/`grep`/`head`) instead of `Read` on raw dot files.
7. Do not compute hotspot LOC using overlapping shell globs (for example `src/*.rs src/**/*.rs`) because that double-counts files.

## Phase 3: Semantic Duplication

Follow `references/core/duplication.md`:

1. Seed from PageRank hotspots.
2. Expand with semantic similarity.
3. Keep clusters of size `>= 3` in standard mode.
4. Prefer cross-directory clusters.

## Phase 4: Architecture and Boundaries

Follow `references/core/architecture.md`:

1. Identify boundary violations and cycles.
2. Identify god modules and suspicious high-centrality hubs.
3. Propose 3-5 boundary clarification moves.

## Phase 5: Risk Audit

Follow `references/core/risk.md`:

1. Security and authZ consistency.
2. Data integrity and transactional safety.
3. Reliability and operability gaps.

## Phase 6: Maintainability and DX

Follow `references/core/maintainability.md`:

1. Test strategy coherence.
2. Taxonomy and naming drift.
3. Boilerplate duplication and missing generators.
4. Documentation and runbook drift.

## Phase 7: Prioritization and Refactor Bundles

Follow `references/core/prioritization.md` and `references/core/output-schema.md`:

1. Filter by confidence threshold and evidence quality.
2. Keep top 10 findings max.
3. Produce 3-8 refactor bundles.
4. Build two-lane roadmap (quick wins vs deep work).

## Phase 8: Optional Diagram and PDF Export

After writing `$AUDIT_REPORT_PATH`, run:

```bash
PDF_OUT="$(bash "$SKILL_DIR/scripts/render_report_pdf.sh" --report "$AUDIT_REPORT_PATH" --map-mode crate)"
printf '%s\n' "$PDF_OUT"
```

Interpretation:

1. `render_report_pdf.sh` attempts `render_system_map.sh` automatically (non-fatal).
2. Prefer `--map-mode crate` for default report exports to keep diagrams readable and PDF-safe.
3. If output/logs contain `SYSTEM_MAP_PATH=...`, include that image as an additional artifact.
4. If output/logs contain `SYSTEM_MAP_SKIPPED=1`, continue without failing the audit.
5. If output contains `PDF_PATH=...`, include that file as an additional artifact.
6. If output contains `PDF_SKIPPED=1`, continue without failing the audit.
7. If output contains `PDF_NOTE=rendered_without_system_map`, mention that the PDF fallback removed the system map image.
8. Do not install Graphviz or PDF tooling during the audit run unless the user explicitly asks.
