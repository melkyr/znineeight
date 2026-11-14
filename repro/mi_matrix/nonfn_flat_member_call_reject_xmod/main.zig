// nonfn_flat_member_call_reject_xmod — Task 6D regression fixture.
//
// Pins the lowering (variant C) placement: a call to a DEFINED non-function
// member reached through a FLAT direct-import module base. `INVALID_FD` is a
// NON-pub `usize` const of `std_io`, so the semantic analyzer's ident-module
// value arm returns `TYPE_VOID` (its `pub` bit gate fails) and a resolved-type
// callability check would MISS this shape. The lowered callee temp, however,
// resolves to a `load_global` of type `usize`, so the lowering check catches it.
//
// DEFECT (before the fix): rc=0, no diagnostic, emitted
// `(void)zG_CC81CC5F_INVALID_FD();` (gcc: called object is not a function).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3056]`.
const io = @import("std_io.zig");

pub fn main() void {
    io.INVALID_FD();
}
