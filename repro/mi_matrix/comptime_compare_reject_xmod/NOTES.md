# comptime_compare_reject_xmod — over-acceptance comparison shapes, rejected

Task 3 (signedness-free comparisons). Replaces
`repro/mi_matrix/comptime_compare_diverge_reject_xmod` (Task 9D ruling m1293
(b)), whose five divergence sites are now ACCEPTED and runtime-pinned in
`repro/mi_matrix/stdlib_comptime_compare_xmod`; the two outcome-matching sites
(`subLt0`, `u8SubLt0`) stay here, plus the `umax < 0` / `(0 - umax) < 0` /
`(u + 1000) < 0` over-acceptance family and the nested peer-fit control
`((u - 1) - 300) < 0`.

**Class:** FAIL (rc=2, 0 emitted `.c`, 7 `error[3059]`).

**Why each site rejects (oracle-checked, official Zig 0.15.2).**

| site | Z98 | Zig 0.15.2 |
|---|---|---|
| `u64Lt0`: `umax < 0` | folds false → `error[3059]` | reject (`expected type 'i32', found 'void'`) |
| `subLt0`: `(umax - 1) < 0` | folds false → `error[3059]` | reject (`expected type 'i32', found 'void'`) |
| `u8SubLt0`: `(u - 300) < 0` | peer-fit declines `u - 300` → `error[3059]` | reject (`type 'u8' cannot represent integer value '300'`) |
| `zeroSubUmaxLt0`: `(0 - umax) < 0` | result does not fit the u64 peer → decline → `error[3059]` | reject (`overflow of integer type 'u64' with value '-18446744073709551615'`) |
| `u8AddBigLt0`: `(u + 1000) < 0` | literal does not fit the u8 peer → decline → `error[3059]` | reject (`type 'u8' cannot represent integer value '1000'`) |
| `nestedU8SubLt0`: `((u - 1) - 300) < 0` | the recursive operand-type mirror gives the outer sub the sema type `u8`, so `- 300` declines → `error[3059]` | reject (`type 'u8' cannot represent integer value '300'`) |
| `modU64Lt0`: module `MUMAX < 0` | folds false → `error[3059]` | reject (`expected type 'i32', found 'void'`) |

Outcome matches on every site (both compilers reject). The exact magnitude+sign
comparison is deliberately exempt from the arithmetic peer-fit rule (Task 1
§5.4): comparisons are mathematical, so no operand range check is applied to
the comparison itself — the arithmetic fold beneath it does the range ruling.
The nested site pins the recursion requirement: a non-recursive syntactic
operand-type lookup let `((u - 1) - 300) < 0` fold to `true` and accept the
program, whose runtime u8 arithmetic wraps (`(u - 1) - 300` = 155, not -101) —
a silent miscompile. `comptimeEvalOperandType` therefore mirrors sema's
integer typing recursively (negate/bit_not propagate, binops use the
wider-wins/ties-lhs rule).
