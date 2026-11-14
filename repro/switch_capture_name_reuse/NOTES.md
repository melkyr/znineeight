# RED repro: switch capture-name reuse — READ bug (STUDY / quantify only)

## Summary
Two sequential `switch`es over payload-carrying tagged-union values that REUSE the same
capture name (`|v|`) mis-read on the READ side: the **second switch's capture read binds the
FIRST switch's captured value**. The payload STORE is correct (Task 28 / `T28`); this is a
SEPARATE pre-existing capture-name-lowering bug. Deterministic, predictable: output = `N * A`
(N = number of switches, A = first switch's payload); every later payload is ignored.

## Form (RED — reused capture name)
`repro/switch_capture_name_reuse/main.zig`:
```zig
var a: Value = Value{ .Int = @intCast(i64, 10) };
switch (a) { .Int => |v| ra = @intCast(i32, v), .Flag => |f| ra = f, .Nil => ra = @intCast(i32, 0) }
var b: Value = Value{ .Int = @intCast(i64, 5) };
switch (b) { .Int => |v| rb = @intCast(i32, v), .Flag => |f| rb = f, .Nil => rb = @intCast(i32, 0) }
__bootstrap_print_int(ra + rb);   // both prongs reuse |v|
```
`Value = union(enum) { Nil: void, Int: i64, Flag: i32 }`.

## Expected vs actual (HEAD `ba7e8031`)
- Expected: **15** (10 + 5).
- Actual RED: **20** — i.e. `10 + 10` = `2*A`. dump rc=0, gcc 0 errors, run rc=0 (links, wrong value).
- **Deterministic**: prints `20` on every run (5 consecutive runs identical); this is NOT an
  uninitialized-memory bug — it is a fixed mis-binding.

## CONTROL (distinct capture names → correct)
Same program with DISTINCT capture names (`|va|` / `|vb|` for the two `.Int` prongs, `|fa|`/`|fb|`
for `.Flag`):
```zig
switch (a) { .Int => |va| ra = @intCast(i32, va), .Flag => |fa| ra = fa, .Nil => ra = @intCast(i32, 0) }
switch (b) { .Int => |vb| rb = @intCast(i32, vb), .Flag => |fb| rb = fb, .Nil => rb = @intCast(i32, 0) }
```
prints **15** (correct). Emitted C reads `va = a.payload.Int._0; ... vb = b.payload.Int._0;` and
casts each independently. This proves the defect is triggered SPECIFICALLY by name reuse.

## Build / run recipe (existing binary, not rebuilt)
```
sf/build/out_release/zig1 --dump-c89 repro/switch_capture_name_reuse/main.zig > /tmp/cn.c 2>/tmp/cn.err  # dump rc=0
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/cn.c \
    sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/cn && /tmp/cn                            # prints 20, run rc=0
```

## Quantified shift (Step 2)
Matrix: first-switch payload A ∈ {10,20,50}, second-switch payload B ∈ {5,7,100}. Expected = A+B.

| A  | B   | expected (A+B) | actual | pattern |
|----|-----|----------------|--------|---------|
| 10 | 5   | 15             | 20     | 2*A     |
| 10 | 7   | 17             | 20     | 2*A     |
| 10 | 100 | 110            | 20     | 2*A     |
| 20 | 5   | 25             | 40     | 2*A     |
| 20 | 7   | 27             | 40     | 2*A     |
| 20 | 100 | 120            | 40     | 2*A     |
| 50 | 5   | 55             | 100    | 2*A     |
| 50 | 7   | 57             | 100    | 2*A     |
| 50 | 100 | 150            | 100    | 2*A     |

**Exact substitution pattern (PREDICTABLE):** `actual = 2*A`; the second switch's payload `B` is
entirely ignored — the second capture read reuses the FIRST switch's captured value. Generalizes:
a 3-switch variant `(10,20,30)` (expected 60) prints **30** = `3*A` (all three read the first). So
`actual = N * A` for N same-name switches; every non-first payload is dropped.

Boundary probe: if the second switch's active variant has a DIFFERENT type from the first
(`.Int` i64 then `.Flag` i32, both `|v|`), it is correctly disambiguated (renamed `v_1`) and the
result is correct (15). The bug fires ONLY when the reused name binds the SAME variant type.

## Emitted-C evidence
First switch prong (`z_bb_1`) — correct read into `v`:
```c
z_bb_1:
    v = a.payload.Int._0;   /* v = 10 */
    zT_8 = (int)v;
    ra = zT_8;              /* ra = 10 */
```
Second switch prong (`z_bb_6`) — fresh temp loaded but NEVER read; cast reads stale `v`:
```c
z_bb_6:
    zT_18 = b.payload.Int._0;  /* correct payload read into a NEW temp zT_18 (= 5) ... */
    zT_19 = (int)v;            /* ... but the cast reads the C variable `v` (still 10), NOT zT_18 */
    rb = zT_19;                /* rb = 10, not 5  -> ra+rb = 20 */
```
`zT_18` is dead: the second switch's payload load is emitted correctly but the capture READ binds
to the first switch's `v`. There is a SINGLE C variable `v` for both switches.

## Root cause (LOCATION — study only, NOT edited)
1. **`sf/src/lower.zig:494-520` `maybeDisambiguateCapture`** — renames a reused capture name ONLY
   when the variant TYPE differs (`if (self.local_decl_types[eli] != variant_type_id)`, line 500).
   Same-typed reuse across sibling switches is left colliding (returns the name unchanged, line 519).
2. **Scope not reset:** after a switch, only `self.capture_shadow.count = 0` is reset
   (`sf/src/lower.zig:2815`); the `local_decl_*` arrays are NOT popped, so the completed switch's
   `v` decl persists and the second switch re-declares the same name → duplicate `local_decl` entry.
3. **First-match binding cements it:** the capture READ resolves via first-match lookup
   (`findLocalTemp` `sf/src/lower.zig:931`, and the ident_expr loop `sf/src/lower.zig:1592` that
   `break`s on the first name match) → returns the FIRST switch's payload temp. Additionally
   c89_emit's decl-collection dedup (`sf/src/c89_emit.zig:1655-1682`, `ldup` at line 1660) keeps
   only the FIRST name→temp mapping, so even the second `decl_local` temp resolves to the first
   `v` when rendered (`resolveTempName` walks `fl_temps`, `sf/src/c89_emit.zig:2175-2186`).

Net: the second switch's fresh payload load (`zT_18`) is orphaned; the capture read binds the first
switch's value → `N*A`.

## Recommendation
Fix in a SEPARATE follow-on plan (out of scope for the tagged-union-payload-store plan). The fix
should scope/pop capture local-decls per switch (or always disambiguate reused capture names, not
only on type mismatch) so each switch's capture read binds its OWN payload temp. Do NOT fix inside
the payload-store plan.

## Cross-links
- Discovered during Task 3 of `.superpowers/sdd/` tagged-union-payload-store plan (the Task 1 repro
  `repro/tagged_union_payload` prints `84` = `2*42` for the same reason).
- Payload STORE correctness is `T28` (done); this READ bug is tracked as `T29` in
  `sf/docs/milestone_lisp_gaps.md`.
