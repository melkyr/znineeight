# self_embed_optional_cycle — RED  [Defensive repros — Plan 1, 2026-08-04]

## What it tests
Self-referential struct through an optional payload (`next: ?X`). Tests whether the
optional-wrap makes the recursion finite (optional = struct with has_value flag + payload
by value).

## Expected classification
Either ICE on topo 2-cycle or gcc incomplete-type: naive C emission produces
`struct X { struct X next; int has_value; }` — infinite-size C type.

## Deferred item
This repro GUARDS the F-8 residual (infinite-size C type for `struct X { next: ?X }`),
not a fix. Expected to be FAIL/ICE today.
