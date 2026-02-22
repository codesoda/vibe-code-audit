# Architecture and Boundaries

Infer current architecture from import graphs and catalog edges, then propose consolidation moves.

## Checks

1. Cross-layer violations
2. Circular dependencies
3. God modules and dumping grounds
4. Inversion failures (low-level importing high-level)
5. Feature-slice drift and inconsistent layering

## Signals

1. High-centrality files with unrelated responsibilities.
2. Controller/route handlers containing domain or persistence logic.
3. Service layers reaching UI/controller layers.
4. Repeated orchestration logic across entrypoints.

## Output

Provide 3-5 boundary clarification moves. For each move include:

1. Target end state
2. Affected boundaries and files
3. Sequenced migration steps
4. Risk notes
