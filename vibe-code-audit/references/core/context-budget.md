# Context Budget

Keep audits inside context limits by treating evidence as a bounded sample.

## Hard Limits by Mode

1. `fast`: up to 20 files and 60 slices
2. `standard`: up to 45 files and 140 slices
3. `deep`: up to 80 files and 260 slices

Use `scripts/build_read_plan.sh` to enforce these limits.

## Read Strategy

1. Prefer artifact-first analysis (`manifest`, `catalog`, `hotspots`, `dup_clusters`, `read_plan`).
2. Read file slices around evidence lines, not entire files.
3. Escalate to full-file reads only for top-risk findings or when user asks.
4. Record when you exceeded slice budget and why.

## Anti-Patterns to Avoid

1. Reading every source file in parallel.
2. Dumping large files into context without targeted line windows.
3. Mixing broad file ingestion with broad multi-agent fanout.
4. Repeating the same long file reads across phases.

## If Limits Are Hit

1. Reduce scope to top hotspots and highest severity signals.
2. Drop low-confidence/low-impact candidates early.
3. Continue with sampled evidence and explicitly note confidence impact.
