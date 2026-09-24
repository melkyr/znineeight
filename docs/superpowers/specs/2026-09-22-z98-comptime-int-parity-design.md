# Z98 comptime-int parity — design

**Status:** implemented (Part I — comptime-int core, Tasks 2–5; closed out by Task 6, 2026-09-24; residuals in §6). **Authority:** official Zig 0.15.2 (`/tmp/zig-x86_64-linux-0.15.2/zig`), never zig0.

## 1. Gap

Z98's comptime values are 64-bit `ComptimeVal { bits: u64, sig: bool }`. Zig's `comptime_int` is **arbitrary-precision and signedness-free until coerced**. Task 9D closed its scope with a ruled **bounded divergence**: comparisons over comptime shapes whose signedness cannot be recovered from a declared type, a literal, `@intCast`/`@as`, or `0 - X` are not folded, so a comptime-true no-`else` value `if` rejects `error[3059]` where Zig accepts (e.g. `const umax: u64 = 18446744073709551615; if ((umax - 1) > 0) 1;`). The over-acceptance direction was removed in the same round.

The real fix is representation-level: arbitrary-precision comptime arithmetic with signedness-free comparison, coerced (range-checked) only when materialised into a typed slot.

## 2. Pre-change baseline (verified at `81be07d3`; superseded by §3 as built)

- `sf/src/comptime_eval.zig`: `ComptimeVal { bits, sig, width_bits }`; `comptimeEvalSignClass` (`:385-458`) infers a three-valued sign class (declared type / literal sign / `@intCast`/`@as` target / `0 - X`); `comptimeEvalOperandCompareSigned` (`:307-317`) returns unknown → the comparison fold returns null (`comptimeEvalCompare` `:165-166`). Fold arms: `cmp_eq/ne/lt/le/gt/ge`, short-circuit `bool_and/or/not` (`:152-250`).
- Consumers: `comptimeEvalBinOp` integer paths, `comptimeValFitsType` (`sf/src/type_resolver.zig` `intValueFitsType` is the separate type-layer twin), `evalConstSignClass`, the `@intCast`/`@as` folds, array-size/enum folds (`evalConstU32Full`/`evalConstI64Full`).

## 3. Target design

1. **Representation** — `ComptimeInt { mag: [N]u32 limbs, len: u8, neg: bool }` (little-endian magnitude; a small fixed cap, e.g. 8 limbs = 256 bits, with a documented overflow → unfoldable). Signedness is **not** stored; sign is carried by `neg`.
2. **Arithmetic** — add/sub/mul/div/mod (truncating toward zero as Zig does), negate, bitwise `and/or/xor/not`, shifts; all arbitrary-precision within the cap.
3. **Comparison** — signedness-free: compare magnitudes, using `neg` semantics (`-0` = `0`); this makes `(umax - 1) > 0`, `-1 < 18446744073709551615` etc. Zig-exact without any sign-class inference.
4. **Coercion** — only at materialisation: into a typed slot (`var`/`const` decl, parameter, return, `@intCast`/`@as` target, array size, enum backing) → range-check against the target's width/signedness, preserving the existing diagnostics (`error[3000]`/`error[3050]`/`error[3055]`/`error[3059]` semantics).
5. **Removal of the divergence** — with (3), the 9D bounded divergence disappears; the `error[3059]` sites in `repro/mi_matrix/comptime_compare_diverge_reject_xmod` were **split, not flipped wholesale** (as built): the five arithmetic-derived sites (`subGt0`, `zeroLtSub`, `subGtZeroConst`, `gtAddZero`, `arithEq`) plus the `i64`-extreme shapes are Zig-accepted positives (`repro/mi_matrix/stdlib_comptime_compare_xmod`), while `subLt0` (`(umax - 1) < 0`) and `u8SubLt0` (`(u - 300) < 0` on `u8`) stay rejected because official Zig rejects them (`repro/mi_matrix/comptime_compare_reject_xmod`); the old fixture was removed and the spec §7.2 note replaced.
6. **Kept boundaries** — float comparison folding is **pending Part II Task 9** of the implementation plan (not a permanent residual; R4); float comptime arithmetic precision stays a non-goal (§5); the `0 - X` special case is removed once comparisons are signedness-free; the pre-existing void-expr residuals (`_ = foo();`, `return if (c) foo();`) are untouched (Part II Task 8).

## 4. Blast radius

- `sf/src/comptime_eval.zig` (core), `sf/src/type_resolver.zig` (fit checks / array-size & enum folds), possibly `sf/src/semantic_analyzer.zig` (the `error[3059]`/`error[3058]` plumbing).
- Emitted C for programs using comptime folds may change (constant forms), so the self-emission fixed point moves and the seed rotates at the plan closeouts (Task 6 for Part I, Task 19 for the whole plan; operator ruling R2).
- 4-MD5 gates are expected UNCHANGED (no gate program exercises the affected folds — verify); corpus movement = the fixtures.
- Docs (as built): `docs/reference/Language_Spec_Z98.md` §7.2, tech docs 03/04/05/07/09/INDEX, `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`.

## 5. Non-goals

- Full Zig `comptime` (generics/`@typeInfo`/reflection).
- Float comptime arithmetic precision (separate, bounded).
- Any behaviour change for runtime values.

## 6. Closeout status and residuals (Task 6, 2026-09-24)

**Implemented (Part I, Tasks 2–5).** The representation (§3.1), exact arithmetic (§3.2), signedness-free comparison (§3.3) and materialisation-time coercion (§3.4) are as-built in `sf/src/comptime_eval.zig`, `type_resolver.zig`, `semantic_analyzer.zig`, `lower.zig` and `main.zig`; the Task 9D divergence is retired (§3.5). Two conservative rules were added beyond the §3 bullet list (Task 1 §9.2) and are part of the as-built contract: the arithmetic operand peer-fit rule and the typed-slot fold-consistency rule (exact semantics in `docs/reference/Language_Spec_Z98.md` §7.2).

**Verified at closeout.** Fixed point hop1 == hop2 == `1e389c5739aea89550d149015f0031d3` (seed rebuild of the committed `sf/src`); frozen Step-0 35-shape table: 28 accepted shapes all official-Zig-0.15.2-equal (deterministic 3×), 7 rejects with the oracle rejecting too; 4-MD5 emitted-C unchanged; corpus `-s0` 996 = 872 OK / 44 GREEN / 80 FAIL / 0 ICE / 0 CRASH (zero class movement); stdlib 223 PASS / 0 FAIL; example matrix 24/24; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Seed rotated v82 → v83 at this closeout (operator R2).

**Residuals (bounded, documented; not part of Part I).**
- **Float comparisons** fold as of **Part II Task 9** (the f64-precision `comptimeEvalCompareFloat` with the exact-representability peer rule; Task 19's whole-plan closeout owns the final spec status). Float arithmetic precision remains a non-goal (§5); the bounded residuals (an `f32` operand against a non-`f32`-exact untyped literal declines, an integer beyond the peer significand declines, `comptime_float` literals compare at f64) are pinned in `repro/mi_matrix/stdlib_comptime_float_compare_xmod` and `sf/docs/tech_docs/04_comptime_eval.md` KI 6.
- **256-bit cap** (8×u32 limbs): a result needing more than 256 magnitude bits is unfoldable (the existing reject/runtime path) where Zig computes it exactly (`1 << 300` class). Source literals `>= 2^64` are already `u64`-lossy at lex/parse time, so the cap governs arithmetic results, not literal spellings.
- **Other bounded divergences** kept as-is (full list + fixtures in `docs/reference/Language_Spec_Z98.md` §7.2 and `sf/docs/tech_docs/04_comptime_eval.md` Known Issues): `const BIGFOLD = 1 << 100;` rejects `error[3000]` (no >64-bit runtime slot); an over-u32 array size (`[1 << 40]u8`) rejects `error[3050]`; `%` on signed comptime ints and `~` on `comptime_int` are Z98-only (a `~`-on-typed-unsigned shape depending on the wrapped value can false-reject); `@intToFloat` of a value above 2^53 may differ by 1 ulp; a module-scope annotated out-of-range const (`const W: i8 = 200;`) is accepted (truncates silently; gcc-invalid C in the anonymous-struct-argument shape) where Zig rejects.
