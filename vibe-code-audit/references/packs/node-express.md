# Pack: Node / Express

Use this pack when `express`-style server markers are present.

## Typical Entrypoints

1. `server.*` and `app.*`
2. `routes/` registration files
3. middleware and guard layers
4. background worker/bootstrap files

## Inventory Hints

1. Map middleware order and auth insertion points.
2. Map error middleware and response shape rules.
3. Map DB access layers and transaction helpers.
4. Map outbound client wrappers.

## Common Footguns

1. Missing centralized async error handling.
2. Authorization checks implemented in handlers instead of middleware.
3. Per-route timeout/retry differences for outbound calls.
4. Inconsistent request validation libraries/patterns.
5. Mixed transaction handling for similar write flows.
