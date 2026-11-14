// nonfn_member_call_reject_xmod — Task 6D regression fixture.
//
// A call whose callee is a DEFINED non-function member of a nested module
// (`std.io.INVALID_FD`, where `INVALID_FD` is a `usize` const) is invalid Zig
// and must be rejected at compile time with a diagnostic and 0 emitted `.c`.
//
// DEFECT (before the fix): `sf/src/lower.zig`'s generic `fn_call` path lowered
// the callee as a VALUE and emitted an indirect call without checking that the
// lowered callee temp was callable. So `std.io.INVALID_FD()` compiled rc=0 with
// NO diagnostic and emitted `(void)zG_CC81CC5F_INVALID_FD();` — C that gcc
// rejects (`called object ... is not a function`).
//
// FIX (Task 6D): after `callee_temp = lowerExpr(...)` the generic call path
// inspects the lowered callee temp's type; a type that is neither a `fn_type`
// nor a pointer to a `fn_type` (and is not `TYPE_VOID`/`TYPE_UNDEFINED`, so the
// Task 6B undefined-member `error[3042]` path is preserved) emits the new
// `error[3056]: expression is not callable`, rc=2, 0 `.c`.
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3056]`.
const std = @import("std");

pub fn main() void {
    std.io.INVALID_FD();
}
