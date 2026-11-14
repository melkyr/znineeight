// nested_mod_undef_member_reject_xmod — Task 6B regression fixture.
//
// A call to an undefined member of a NESTED module (`std.io.printt`, where
// `printt` does not exist) is invalid Zig and must be rejected at compile time
// with a diagnostic and 0 emitted `.c`.
//
// DEFECT (before the fix): `sf/src/lower.zig`'s `fn_call` nested-chain block
// (`:3984-4007`) early-returned temp 0 when the chain walk failed, bypassing
// the generic call path. So `std.io.printt("y\n")` compiled rc=0 with NO
// diagnostic and the call was silently dropped from the emitted C (the program
// ran, but the typo'd call vanished). The flat base `std.nope()` was already
// correctly diagnosed (`error[3042]`).
//
// FIX (Task 6B): the chain failure now sets `chain_valid = 0` and falls through
// to the generic call path (`:4193`), which lowers the callee as a value and
// emits the existing `error[3042]: non-value base expression in field access`
// (plus `warning[3023]`), rc=2, 0 `.c` — exact parity with the flat case.
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3042]` + `warning[3023]`.
const std = @import("std");

pub fn main() void {
    std.io.printt("y\n");
}
