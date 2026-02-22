# Pack: React / Next.js

Use this pack when TypeScript frontend markers are present.

## Typical Entrypoints

1. `app/` routes (App Router)
2. `pages/` routes (Pages Router)
3. API route handlers (`app/api` or `pages/api`)
4. shared client/server utility layers

## Inventory Hints

1. Map server vs client boundary files.
2. Map data-fetching layers and API wrappers.
3. Map shared DTO/serialization utilities.
4. Map auth/session guard patterns.

## Common Footguns

1. Repeated API clients with inconsistent timeout/error behavior.
2. Divergent form validation stacks and error UX.
3. Silent failures in server actions and API handlers.
4. Inconsistent permission gating across routes/components.
5. Multiple conflicting DTO transforms for same domain object.
