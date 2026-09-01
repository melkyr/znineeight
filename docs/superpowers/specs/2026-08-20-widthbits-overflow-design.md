# Self-Compile Width-Bits Overflow Design

> **Date:** 2026-08-20. **Status:** design (pre-implementation). Branch `zig1_start`.

## Problem

Self-compile now aborts in C emission with:

```
PANIC: integer cast overflow at /tmp/fx_subfolder/zig_runtime.h:154
```

Locus: `sf/src/c89_emit.zig:5002` in the `.int_const` emitter:

```zig
width_bits = @intCast(u8, bty.size * @intCast(u32, 8));
```

`width_bits` is declared `u8` (`:4992`). When the `.int_const` result temp's hoisted type is a **40-byte tagged union**, `40 * 8 = 320` overflows `u8` → the runtime `@intCast` PANIC (rc=134, SIGABRT) before any `.c` is produced.

**Key structural fact:** `width_bits` is only ever *read* inside the `is_signed != 0` branch (`:5018-5034`, the signed-value masking). A tagged union is never signed (`is_signed=0` at `:5001`, tagged_union_type is not in the int-kind list `:4999`). The tagged-union `.int_const` path (`:5009-5011`) emits `.tag = <value>` and never consumes `width_bits`. So the overflow is a **dead-computation on non-int types** — the cast is computed unconditionally but its result is only meaningful/consumed for integer temps (max size 8 bytes → max width 64).

## Blast radius — same `@intCast(u8, size*8)` class

Three sites compute a bit-width as `u8` from `ty.size * 8`:

| Site | Reachable types | Status |
|---|---|---|
| `c89_emit.zig:5002` (`.int_const`) | any hoisted temp type (tagged union, struct, …) | **PANIC (live)** |
| `c89_emit.zig:3190` (`emitSatBinary`) | integer types only (sat math) | same class, safe today (size ≤ 8) |
| `comptime_eval.zig:139` (`int_cast` fold) | **any resolvable `@intCast` target type** (the fold computes `wb` from the TARGET type) | **PANIC (live, R1 probe-verified 2026-08-20)** — `@intCast(Big, 5)` on a >31B union PANICs rc=134; control `@intCast(Small, 5)` on a 4B union emits `.tag = 5;`. Pre-fix `== 64` guard makes the `1 << wb` shift only reachable for int/char/bool targets; **post-widen the guards become `>= 64`** (STOP ruling) so >31B non-int targets do not shift `u64` by ≥ 64 (UB). |

Supporting `width_bits: u8` surface: `c89_emit.zig:3160/3167/3174/3181` (`satMaxLit/satMinLit/satMinMagLit/satMaxULit` params), `comptime_eval.zig:16` (`ComptimeVal.width_bits: u8`), `comptime_eval.zig:56-57` (width max arithmetic).

## Root cause

`width_bits: u8` is too narrow to hold `size*8` for any type wider than 31 bytes. The `u8` width type is a **systemic gap**, not a per-site bug: any non-int type ≥32 bytes that reaches a width computation re-introduces the overflow.

## Fix options (adjudicated at STOP; default = Option B)

**Option A — surgical guard:** compute `width_bits` only for integer-kind temps; leave default 32 otherwise.
- Edge cases (why A is weaker): the guard predicate must enumerate every integer-like kind (`:4999` list is incomplete for enum/error-set/char/bool which are not signed but are width-bearing); A leaves `width_bits: u8` fragile for any future type >31 bytes — patches the symptom, not the gap.

**Option B — widen the width type (gap-fill; DEFAULT):** widen `width_bits` from `u8` to `u32` (exact width adjudicated at STOP: u16 also fits 40*8=320, u32 future-proofs) so the computation can never overflow for any type size.
- `c89_emit.zig:4992/5002` (`.int_const`): `width_bits` → u32.
- `c89_emit.zig:3190` (`emitSatBinary`) + `satMaxLit/satMinLit/satMinMagLit/satMaxULit` (`:3160/:3167/:3174/:3181`) params → u32 in lockstep.
- `comptime_eval.zig:139` (`wb: u8`) + `ComptimeVal.width_bits: u8` (`:16`) + width-max arithmetic (`:56-57`) → u32.
- **Safety invariant (I-task records):** `1 << width_bits` masking (`c89_emit.zig:5021/5025/5029`) is reached only when `is_signed != 0`; tagged unions are never signed, so a widened value (e.g. 320) is never shifted — zero shift-UB risk on the failing path. Integer temps keep width ≤ 64, so signed shifts stay in range.

## Constraints

- Z98 dialect: no `anytype`/`@Type`; `@intCast` for width coercions; u32 aligns with existing `u32` size/offset conventions.
- 4 MD5 gates must stay byte-identical (gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `9720478c937409a29fe23ae0199821cf`). No gate uses a tagged-union `.int_const`, so byte-identity holds by construction.
- Corpus 286 dirs unchanged; matrix 21/21; test_analyzer `5 passed, 4 failed`.
- Verification MUST scan the WHOLE tree for the defect class (all `@intCast(u8, size*8)` + all `width_bits` reads), never stop at first error (M4 lesson).
- `sf/build/out_release/` WEDGED — never touch/ls; timeout-gated runs only.
- Build: `bash sf/scripts/build_release.sh` gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; WIPES /tmp/fx_subfolder — reinstall std after every rebuild (`cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`).
- I-task READ-ONLY mandate (operator-strict): ZERO committed source changes; /tmp-only instrumentation + revert; tree clean verified before finish. Fixes belong ONLY in F-tasks. Fallbacks NEVER allowed on prod compiler.

## Success criteria

1. Reproducer: a minimal tagged-union program that emits `.int_const` on a >31-byte union temp → currently PANIC rc=134; post-fix emits correct `.tag = <value>` C, dump/gcc rc=0.
2. Self-compile advances past `c89_emit.zig:5002` (PANIC gone); next frontier blocker recorded, NOT fixed.
3. 4 MD5s byte-identical; corpus 286 unchanged; matrix 21/21; test_analyzer 5/4.
4. Whole-tree scan: zero remaining `@intCast(u8, size*8)` width computations.
