// comptime_cast64_range_reject_xmod — Task B3 item 2 clean-reject control.
//
// Before the fix, `comptime_eval.zig`'s `comptimeValFitsType` returned `true`
// for every `wb >= 64` target, so an out-of-range cast to a 64-bit target
// folded silently:
//   - `@intCast(u64, -1)` emitted `18446744073709551615` (the wrapped value);
//   - `@as(u64, -1)` likewise;
//   - `@intCast(i64, @as(u64, 18446744073709551615))` emitted `-1`.
// All three are invalid Zig: the value does not fit the target.
//
// FIX (Task B3 item 2): `comptimeValFitsType` classifies the operand
// syntactically (a `negate` is negative; a non-negative literal/unsigned
// source above i64 max is non-negative) and rejects the mismatches. The
// compiler exits rc=2 with `error[3000]` and emits 0 `.c`.
//
// Contract (post-fix): dump rc=2, 0 `.c`, `error[3000]` — the canonical
// classifier's GREEN clean-reject bucket.
//
//   error[3000]: @intCast value does not fit the target type   (line A)
//   error[3000]: @as value does not fit the target type        (line B)
//   error[3000]: @intCast value does not fit the target type   (line C)
const A = @intCast(u64, -1);
const B = @as(u64, -1);
const C = @intCast(i64, @as(u64, 18446744073709551615));

pub fn main() void {
    _ = A;
    _ = B;
    _ = C;
}
