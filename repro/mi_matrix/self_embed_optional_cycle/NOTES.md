# self_embed_optional_cycle — GREEN-GUARD (correct rejection)  [Defensive repros — Plan 1, 2026-08-04; reclassified 2026-08-24]

## What it tests
Self-referential struct through an optional VALUE payload (`next: ?X`). Z98's optional is a
struct with a `has_value` flag + the payload **by value**, so `struct X { next: ?X }` is an
infinite-size C type — correctly rejected with `error[24]: circular type dependency detected`.

## Real-Zig oracle (verified 2026-08-24 — the previous "optional breaks the cycle" framing was WRONG)
The Zig language reference shows that **optional POINTERS** (`?*X`) are the mechanism that
breaks self-reference: an optional pointer "secretly compiles down to a normal pointer, since
we know we can use 0 as the null value" — i.e. it is pointer-sized. The langref's canonical
self-referential example (a linked list) declares fields as:
```zig
prev: ?*Node,
next: ?*Node,
```
An optional **value** `?X` embeds `X` by value, so `struct X { next: ?X }` is infinite-size
and real Zig rejects it too (the "type depends on itself" error). Therefore Z98's `error[24]`
rejection of `next: ?X` is CORRECT behavior — the construct a program must use for
self-reference is `next: ?*X` (optional pointer).

## Classification
**GREEN-GUARD** (correct rejection, 2026-08-24): dump rc=2 with clean `error[24]`, 0 `.c`, no
ICE/crash. Reclassified from FAIL (the corpus was counting a correct rejection as a defect).
Corpus: OK=313 → FAIL=0 / GREEN=9 → GREEN=10 over 323 dirs.

## Deferred item (original, 2026-08-04)
Originally guarded the F-8 residual (infinite-size C type for `struct X { next: ?X }`). The
F-8 framing is superseded by the oracle correction above: rejection is correct. Whether Z98
supports the real-Zig `?*X` optional-pointer self-reference pattern is a SEPARATE, open
question (recorded; not a blocker).
