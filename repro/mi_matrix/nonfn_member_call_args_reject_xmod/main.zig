// nonfn_member_call_args_reject_xmod — Task 6D regression fixture.
//
// Same defect as `nonfn_member_call_reject_xmod`, but the callee is invoked WITH
// arguments. The callability check runs before the arguments are lowered, so
// the argument count is irrelevant — the callee is still a non-function value.
//
// DEFECT (before the fix): rc=0, no diagnostic, emitted
// `(void)zG_CC81CC5F_INVALID_FD(zT_1, zT_2);` (gcc: called object is not a
// function).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3056]`.
const std = @import("std");

pub fn main() void {
    std.io.INVALID_FD(1, 2);
}
