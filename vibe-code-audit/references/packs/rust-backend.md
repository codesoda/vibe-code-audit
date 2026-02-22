# Pack: Rust Backend

Use this pack when `Cargo.toml` exists.

## Typical Entrypoints

1. `src/main.rs`
2. `src/lib.rs`
3. `src/bin/*`
4. framework routers/handlers (axum/actix/rocket)
5. worker binaries and background job loops

## Inventory Hints

1. Locate route registration and middleware layers.
2. Locate DB access (`sqlx`, `diesel`, custom repositories).
3. Locate shared error types and response mapping.
4. Locate retry/timeouts around outbound clients.

## Common Footguns

1. Inconsistent error conversion (`anyhow` vs typed errors).
2. Missing transaction boundaries around multi-step writes.
3. Ad hoc permission checks in handlers.
4. Duplicate request validation in handler and service layers.
5. Divergent timeout/retry defaults across clients.
