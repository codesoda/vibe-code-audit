# Specialist Agent Roles

Use one catalog-producing pass plus specialist passes.

## Recommended Topology

1. Catalog agent (system inventory source of truth)
2. Architecture and boundaries agent
3. Semantic duplication and consolidation agent
4. Security and authZ consistency agent
5. Data integrity agent
6. Performance and caching consistency agent
7. Observability and operability agent
8. API consistency agent
9. DX and maintainability agent

## Coordination Rules

1. Specialists consume catalog and hotspot artifacts.
2. Merge duplicate findings by intent and evidence.
3. Apply confidence thresholds before final ranking.
4. Generate bundles only after filtered findings are finalized.
