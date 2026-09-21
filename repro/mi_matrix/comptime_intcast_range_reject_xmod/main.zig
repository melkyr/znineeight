// comptime_intcast_range_reject_xmod — Task 11S (c) negative control.
//
// DEFECT: `comptime_eval.zig`'s `@intCast` arm masked the operand to the target
// width instead of range-checking it, so `const X = @intCast(u8, 300);` folded
// to `(unsigned char)(44)` and compiled/ran silently (rc=0). Official Zig and
// the Z98 spec reject `@intCast(u8, 300)`: 300 does not fit u8.
//
// FIX (Task 11S): the arm range-checks the folded value against the resolved
// target integer type via `comptimeValFitsType`; an out-of-range cast emits
// error[3000] and stops folding, so the compiler exits rc=2 before emission.
//
// Contract: dump rc=2, 0 `.c`, `error[3000]` (GREEN clean-reject bucket).
//
// Positive controls that must stay ACCEPTED live in
// `stdlib_intcast_range_xmod` (in-range narrow target, signed negative in range).
const X = @intCast(u8, 300);
const Y = @intCast(u8, 256);

pub fn main() void {
    _ = X;
    _ = Y;
}
