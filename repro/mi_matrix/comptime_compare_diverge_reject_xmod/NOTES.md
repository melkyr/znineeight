# comptime_compare_diverge_reject_xmod — documented bounded divergence

Task 9D fix round 3 (operator ruling m1293, option **(b)**).

**Class:** FAIL (rc=2, 0 emitted `.c`, 7 `error[3059]`).

**What it pins.** The comptime comparison fold is deliberately conservative: an
operand's signedness is taken only from (i) a declared integer type, (ii) a
literal's own sign / `negate`, or (iii) an explicit `@intCast`/`@as` target. A
shape outside those — here, an arithmetic expression over a const — makes the
whole comparison unfoldable, so a no-`else` value `if` on it rejects
`error[3059]`. Z98 does **not** guess from `cv.sig`.

**Divergence vs Zig 0.15.2 (oracle-checked).**

| site | Zig 0.15.2 | Z98 | note |
|---|---|---|---|
| `(umax - 1) > 0` | accept | reject | divergence (Zig arbitrary-precision) |
| `0 < (umax - 1)` | accept | reject | divergence |
| `(umax - 1) > zero` | accept | reject | divergence |
| `umax > (0 + 0)` | accept | reject | divergence |
| `(a + 1) == 2` | accept | reject | divergence |
| `(umax - 1) < 0` | reject (`expected type 'i32', found 'void'`) | reject | outcome matches |
| `(u - 300) < 0` | reject (`type 'u8' cannot represent integer value '300'`) | reject | outcome matches |

The already-supported cases stay in `repro/mi_matrix/stdlib_comptime_true_if_xmod`
(`umax > 0`, `umax > zero`, `uu > -1`, `-1 < uu`, `uu > (0 - 1)`).

**Why not full parity.** Computing these would require propagating peer types /
arbitrary precision through the fold; the operator ruled a bounded, documented
divergence instead (m1293 (b)). Recorded in
`repro/mi_matrix/EXPECTED_FAIL.md` (v199) and the `docs/sf/QUICK_REF.md` Task 9D
entry.
