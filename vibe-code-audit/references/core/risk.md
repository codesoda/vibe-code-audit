# Risk Audit

Prioritize security, data integrity, and reliability risks with concrete evidence.

## Security and AuthZ

1. Missing or inconsistent authorization checks
2. Input validation gaps at trust boundaries
3. Unsafe query or command construction patterns
4. Sensitive data logging
5. Secret handling weaknesses

## Data Integrity

1. Missing transaction boundaries on multi-step writes
2. Partial write risk and inconsistent rollback behavior
3. Idempotency gaps in retried operations
4. Migration and schema drift hazards

## Reliability and Operability

1. Retry/backoff inconsistency
2. Timeout inconsistency
3. Silent failures with weak observability
4. Critical paths without metrics/logging

## Confidence Thresholds

1. `S0/S1` findings: keep if confidence `>= 0.70`.
2. `S2/S3` findings: keep if confidence `>= 0.85`.
3. Drop findings without direct file evidence.
