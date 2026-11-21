// nested_mod_deep_chain_reject_xmod — Task 6B deep-chain guard fixture.
//
// A deeply nested callee chain (`std.io.a.b.c.d`) has no such member anywhere
// and must clean-reject (rc=2, 0 `.c`, `error[3042]`).
//
// DEFECT (before the fix): two compounding problems in `sf/src/lower.zig`'s
// `fn_call` nested-chain block:
//   1. the chain buffer was `[4]u32` while `chain_len` reaches 5 for a base
//      with >=4 field-access levels (`std.io.a.b.c.d()`), i.e. an
//      out-of-bounds stack write (observed benign, rc=0, no trap);
//   2. the failure path early-returned temp 0, silently dropping the call.
//
// FIX (Task 6B): the walk loop is bounded (`chain_len < 4`) so the buffer is
// never overrun, and an unresolvable chain now falls through to the generic
// call path instead of returning.
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3042]` + `warning[3023]`,
// no crash.
const std = @import("std");

pub fn main() void {
    std.io.a.b.c.d();
}
