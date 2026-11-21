# zig1 Type-Limit Widening — Design

> Status: draft (2026-10-07). Follow-up to the structural live-set plan
> (`docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`), which met the
> ≤16 MB stop-gate by narrowing `Type` columns. This follow-up raises the user-facing
> ceilings those narrowings created, without losing the RSS target.

## Problem

To reach peak RSS ≤16 MB the structural plan narrowed the registry `Type` record
(`sf/src/type_registry.zig`) from 32 B to 16 B: `name_id`→u16, `payload_idx`→u16,
`module_id`→u8, `alignment`→u8 (plus moving the sparse `c_name_id` out to a side map).
Four of those columns are now **user-facing ceilings** that fail a build:

| column | width | ceiling | trips when |
|---|---|---|---|
| `name_id` | u16 | 65,535 | a compilation interns >65,535 distinct strings (it is a **global interner id**, not a type count) |
| `payload_idx` | u16 | 65,535 | a single payload array (fn/struct/ptr/…) exceeds 65,535 entries |
| `module_id` | u8 | 255 | a compilation imports >256 modules |
| `alignment` | u8 | 255 | a computed alignment ≥256 (unreachable in practice) |

Each is guarded: `error: type_registry <field> exceeds <limit> (value <v>)` then exit 1
(`typeDbCeiling`/`typeNarrowU16`/`typeNarrowU8`). The ceilings were **provenance from the
narrowing, not from the plan's main levers**: the ~1 MB the plan saved came mostly from
capacity/pre-sizing, dropping the interner `hash` column, and the comptime `FoldVal`
representation change (with a wide side pool) — none of which creates a ceiling. The
`Type` 32→16 field narrowing contributed only ~40 KB touched.

The ceilings are **correlated with program size** (module count and distinct-string count
both scale with LOC), so raising only `module_id` tends to hand the user the `name_id`
wall next. There is **no build flag and no second "wide" compiler** in the seed model, so
an error cannot offer the user a remedy — the only lever is to raise the limits.

Raising them is **cheap**: the `Type` array is small and already right-sized (len ~2,497,
cap 4,096), and `module_id`/`alignment` widen into existing struct padding.

## Goal

Remove the realistic user-facing ceilings by widening the `Type` ceiling columns, while
keeping peak RSS ≤16,384 K and byte/runtime equivalence.

## Metric

Peak **RSS** (`/usr/bin/time -v` Maximum RSS), median of ≥3 interleaved `-s0`
self-compile runs — unchanged target **≤16,384 K**. Runtime-equivalence battery unchanged.

## Decision

Widen the `Type` ceiling columns:

| column | from | to | cost |
|---|---|---|---|
| `module_id` | u8 | **u16** | free (uses existing padding) |
| `alignment` | u8 | **u16** | free |
| `name_id` | u16 | **u32** | +2 B/type |
| `payload_idx` | u16 | **u32** | +2 B/type |

Resulting `Type` = **20 B** (was 16 B), i.e. **+4 B per type** → ~10 KB at the current
len (2,497), **~16 KB** at the pre-sized cap (4,096), and ~256 KB only for a build whose
type count approaches the old ceiling (a machine that is by definition not the 16 MB
Win9x target). This is ~0.1 % of the 16 MB budget; the structural plan's margin
(~180–440 K) absorbs it.

Remove the now-dead ceiling guards (`typeDbCeiling`, `typeNarrowU16`, `typeNarrowU8`) and
their call-site wrappers, replacing them with plain casts:
- `name_id`/`payload_idx`: u32 → u32 (identity; the fields match the source width again),
- `module_id`/`alignment`: u32 → u16 (u16 ceilings are 65,535 — unreachable for any real project).

**Keep unchanged** (they create no ceiling and are load-bearing for the RSS target):
- the interner narrow/wide bucket switch (`u16` buckets that auto-migrate to `u32` at
  65,535 entries; `sf/src/string_interner.zig`);
- the comptime `FoldVal` 16 B record + wide-integer side pool (`sf/src/comptime_eval.zig`);
- all right-sizing / pre-sizing.

## Residual limits after this change

- `name_id`/`payload_idx`: u32 — identical to the pre-plan compiler; only u32-sized inputs
  could exceed (not realistic).
- `module_id`: u16 → 65,535 modules; `alignment`: u16 → value 65,535. Both effectively
  unreachable.
- No `Type`-column user ceiling remains in practice.

## Non-goals

- Reverting pre-sizing / representation changes (they carry the RSS win and have no ceiling).
- Changing the interner bucket width or the comptime `FoldVal` representation.
- The deferred structures (AST window/value-pool, hash-map interleaving, one-use retention).
- Any change to the accepted input language or emitted C semantics.

## Binding constraints

- Seed model (current seed v93, fixed point `639902d5146233091f6b2f98508ce3eb`, archive md5
  `e1955908f3aa58992592f9c021c36d42`); any changed code must compile with the seed, and the
  fixed point is re-baselined (recorded, never silent).
- Runtime-equivalence oracle for the fix: corpus classify diff-empty
  (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + goldens gol/lisp/json/mud +
  `verify_stdlib` 266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream) + semantic markers
  byte-identical IN-SESSION.
- `edit`/`fastedit` only; re-read the region before each edit; edit bottom-to-top.
- No push. Compression forbidden during a build session. Seed rotation only at closeout.
- Reports under the plan's workspace (`.superpowers/sdd/2026-10-07-zig1-type-limit-widening-plan/`).

## Acceptance

- `Type` columns widened as decided; guards removed; no user-facing `Type`-column ceiling
  remains in practice.
- Battery green; peak RSS median ≤16,384 K (recorded delta vs the ~16,150 K baseline).
- New fixed point recorded; seed rotated v93→v94; docs note the (raised) limits.
