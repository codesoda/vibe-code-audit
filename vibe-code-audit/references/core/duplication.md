# Semantic Duplication

Focus on same-intent code, not only textual clones.

## Candidate Generation

1. Seed from llmcc PageRank top-K hotspots.
2. For each hotspot, run semantic similarity retrieval.
3. Expand candidates by shared dependency patterns and control-flow shape.

## Cross-Language Heuristics

1. Similar function or method intent tokens.
2. Similar import/dependency sets.
3. Similar branching and data transformation shape.
4. Similar query structure with minor filter differences.

## Clustering Rules

1. Standard mode: include cluster only if size `>= 3`.
2. Deep mode: size `>= 2` allowed only with strong evidence.
3. Prefer cross-directory clusters.
4. Record divergence points within each cluster.

## Required Cluster Fields

1. Cluster ID
2. Common intent
3. Members (paths/symbols)
4. Divergence summary
5. Consolidation target
6. Confidence
