# Inventory Rules

Create `audit_index/derived/catalog.json` as a machine-usable system map.

## Required Sections

1. `entrypoints`
2. `domains`
3. `data_stores`
4. `integrations`
5. `cross_cutting`

## Evidence Requirements

Each catalog item must include:

1. `name`
2. `kind`
3. `paths` (one or more file paths)
4. `notes`

## Entrypoints to Capture

1. HTTP routes and handlers
2. Background jobs/workers
3. CLI command entrypoints
4. Webhook receivers
5. Scheduled tasks

## Cross-Cutting Targets

1. Auth/authZ
2. Validation
3. Logging/tracing
4. Feature flags
5. Configuration loading
6. Error shaping

## Quality Rules

1. Prefer explicit file evidence over inferred claims.
2. Avoid duplicate entities with alternate names.
3. Record unknowns explicitly when evidence is incomplete.
