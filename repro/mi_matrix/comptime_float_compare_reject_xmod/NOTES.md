# comptime_float_compare_reject_xmod — Task 9 fix round 1 (review Critical)

Float comparisons whose integer operand needs more significant bits than the
float peer's significand (53 for f64/`comptime_float`, 24 for f32) must NOT
fold: official Zig compares such operands exactly, while the fold would have
to use an f64-rounded value. Z98 declines and the no-`else` value `if` rejects
`error[3059]`, matching Zig's `expected type 'i32', found 'void'`.

Sites (all comptime-false, rc 2, 0 `.c`):

| site | exact truth | Zig | Z98 (fixed) |
|---|---|---|---|
| `((1 << 64) + 1) == 18446744073709551616.0` | 2^64 + 1 != 2^64 | reject | `error[3059]` (sig 65 declines) |
| `((1 << 64) + 1) <= 18446744073709551616.0` | 2^64 + 1 > 2^64 | reject | `error[3059]` (sig 65 declines) |
| `((1 << 53) + 1) == 9007199254740992.0` | 2^53 + 1 != 2^53 | reject | `error[3059]` (sig 54 declines) |

RED: commit `f342794a` (the buggy `ciSignificantBits` undercounted multi-limb
magnitudes) folded all three TRUE with the f64-rounded value, ACCEPTED the
program and classified it OK. GREEN: fix round 1 rejects all three.

Oracle: Zig 0.15.2 rejects the first with `expected type 'i32', found 'void'`
and rejects the other two with the same no-`else`/void error (checked with
`/tmp/task9/fix/probe/za.zig` + `zr` shapes).
