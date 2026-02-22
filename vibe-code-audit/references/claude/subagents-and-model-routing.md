# Claude Subagents and Model Routing

Use this profile when running vibe-code-audit through Claude Code.

## Why

Claude subagents run in separate contexts, which preserves main-thread context and prevents audit runs from hitting context limits.

Each custom subagent can declare its own `model` in frontmatter, and an optional global fallback model for subagents can be set with `CLAUDE_CODE_SUBAGENT_MODEL`.

## Phase Routing

Use this phase-to-agent/model mapping:

1. Phase 0-1 (preflight, indexing, read-plan build)
   - Runner: main thread
   - Model: `sonnet`
   - Action: run deterministic scripts only
2. Discovery and codebase exploration
   - Runner: built-in Explore subagent (read-only)
   - Model: `haiku` (built-in Explore is optimized for this)
   - Action: gather path-level evidence and references
3. Pattern mining and duplication analysis
   - Runner: custom or general-purpose subagent
   - Model: `sonnet`
   - Action: compare implementations and build clusters from bounded read plan
4. Architecture/risk adjudication for high-severity findings
   - Runner: custom or general-purpose subagent
   - Model: `opus` for ambiguous/high-impact reasoning
   - Action: severity/confidence resolution and boundary decisions
5. Report and bundle synthesis
   - Runner: main thread or synthesis subagent
   - Model: `sonnet`
   - Action: produce concise, evidence-backed report

## Model Selection Guidance

1. Use `haiku` for broad search and lightweight extraction.
2. Use `sonnet` for day-to-day coding/audit implementation and synthesis.
3. Use `opus` only for highest-complexity reasoning or disputed high-severity findings.
4. In long sessions, consider `sonnet[1m]` if available.

## Recommended Session Setup

1. Start or switch model:
   - `/model sonnet`
2. For long audits with large context needs:
   - `/model sonnet[1m]`
3. Optional hybrid planning/execution mode:
   - `/model opusplan`

Environment fallback option:

```bash
export CLAUDE_CODE_SUBAGENT_MODEL=haiku
```

## Optional Subagent Templates

Use `/agents` and create focused agents. Keep each single-purpose.

### `vca-explorer`

```yaml
---
name: vca-explorer
description: Read-only repo exploration for vibe-code-audit. Use proactively for discovery, evidence path lookup, and stack marker detection.
tools: Read,Glob,Grep,Bash
model: haiku
maxTurns: 8
---
Perform read-only exploration. Return concise path-first findings and suggested slices. Do not edit files.
```

### `vca-pattern-miner`

```yaml
---
name: vca-pattern-miner
description: Pattern inconsistency and duplication analysis for vibe-code-audit. Use after read_plan.tsv exists.
tools: Read,Glob,Grep,Bash
model: sonnet
maxTurns: 12
---
Use read_plan.tsv and index artifacts as primary inputs. Compare behavior across implementations and produce high-confidence clusters.
```

### `vca-risk-judge`

```yaml
---
name: vca-risk-judge
description: High-severity risk adjudication for vibe-code-audit. Use when S0/S1 confidence is uncertain.
tools: Read,Glob,Grep,Bash
model: opus
maxTurns: 8
---
Evaluate only top-risk candidates. Require concrete evidence. Resolve severity and confidence with explicit rationale.
```

## Constraints

1. Keep subagents read-only for audit phases.
2. Limit each subagent run to a bounded objective and short output.
3. Feed subagents artifacts and read-plan slices, not full-repo raw content.
4. Merge subagent results in main thread and enforce final confidence thresholds.
