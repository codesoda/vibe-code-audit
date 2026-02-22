# Maintainability and DX

Assess what makes safe iteration slow or error-prone.

## Focus Areas

1. Test strategy coherence for high-risk flows
2. Naming/folder taxonomy drift
3. Boilerplate repetition suitable for generators/templates
4. Documentation mismatch with actual architecture
5. Feature onboarding friction

## Signals

1. Similar behavior covered by very different test styles.
2. New feature paths requiring copy-modify from multiple locations.
3. Dead or orphaned code paths after feature iteration.
4. Runbooks or READMEs describing outdated paths.

## Output

For each maintainability finding include:

1. Friction source
2. Evidence files
3. Impact on delivery speed/risk
4. Suggested structural fix
