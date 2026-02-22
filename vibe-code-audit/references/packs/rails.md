# Pack: Rails

Use this pack when Rails project markers are present.

## Typical Entrypoints

1. `config/routes.rb`
2. `app/controllers/`
3. `app/jobs/`
4. `app/services/` or equivalent patterns
5. `app/models/` and migration history

## Inventory Hints

1. Map controller concerns vs domain/service boundaries.
2. Map authorization pattern usage (`Pundit`, `CanCanCan`, custom).
3. Map transaction use in multi-model write paths.
4. Map background job retry/idempotency behavior.

## Common Footguns

1. Business logic drift into controllers.
2. Divergent authZ checks across comparable actions.
3. Mixed error envelope handling in API controllers.
4. Callback-heavy flows with hidden side effects.
5. Duplicated query and serialization logic across controllers/services.
