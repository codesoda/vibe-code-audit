# Output Schema

Use these normalized shapes when possible.

## Finding Object

```json
{
  "id": "F-001",
  "title": "Inconsistent retry policy in payment calls",
  "severity": "S1",
  "confidence": 0.88,
  "effort": "M",
  "blast_radius": "billing",
  "evidence": ["src/payments/client.rs", "src/payments/retry.ts"],
  "risk": "Can cause duplicate charges or silent drops under transient failures",
  "recommendation": "Centralize retry/backoff policy in one adapter"
}
```

## Bundle Object

```json
{
  "id": "B-01",
  "title": "Unify HTTP client and retry policy",
  "goal": "Collapse 4 client patterns into 1 shared adapter",
  "scope": ["backend/http", "frontend/api"],
  "steps": ["Introduce shared adapter", "Migrate top 3 call sites", "Remove legacy wrappers"],
  "risk": "Medium; migration sequencing required",
  "impact": "Lower incident rate and simpler observability",
  "success_metric": "4 implementations -> 1; timeout/retry defaults standardized"
}
```

## Report Constraints

1. Max 10 findings.
2. Max 8 bundles.
3. No lint/style-only findings.
4. Every finding includes evidence and confidence.
