# Pattern Mining

Detect where the same concept is implemented differently.

## Detector Families

1. Auth/authZ checks
2. Validation rules and placement
3. Error handling and error shape
4. Retry/backoff/timeouts
5. DB access and transaction boundaries
6. HTTP client wrappers and defaults
7. DTO/serialization conventions
8. Config key loading and defaults

## Detection Method

1. Use catalog entities as the search boundary.
2. Use hybrid retrieval to collect examples for each family.
3. Compare behavior, not naming.
4. Flag inconsistent defaults as risk multipliers.

## Typical Inconsistency Signals

1. Most paths validate input, some skip validation.
2. Most clients set timeout/retry, one omits both.
3. Mixed error envelope shapes across equivalent APIs.
4. Different permission checks for similar endpoints.
5. Mixed transaction usage on similar write paths.

## Output Expectations

For each inconsistency finding include:

1. Family
2. Affected files
3. Divergent behavior summary
4. Risk explanation
5. Suggested standardization move
