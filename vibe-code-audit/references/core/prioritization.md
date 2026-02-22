# Prioritization and Bundling

Convert findings into a short, high-leverage execution plan.

## Scoring Rubric

Score each candidate on:

1. Impact (customer/security/data risk)
2. Likelihood (how often and how easily triggered)
3. Fix leverage (how many call sites collapse)
4. Effort and change risk

Prefer high-impact + high-leverage bundles over low-value cleanup.

## Bundle Rules

1. Produce 3-8 bundles total.
2. Each bundle must collapse duplication or tighten a boundary.
3. Each bundle must have incremental, safe steps.

## Bundle Fields

1. Title and objective
2. Scope (files/domains)
3. Steps (ordered)
4. Rollback/risk notes
5. Expected impact
6. Success metric

## Roadmap Lanes

1. Quick Wins (1-3 days)
2. Deep Work (1-6 weeks)
