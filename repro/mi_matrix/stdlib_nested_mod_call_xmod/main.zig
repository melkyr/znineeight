// stdlib_nested_mod_call_xmod — Task 6B positive control for the
// nested-module undefined-member fix.
//
// A call to a *valid* member of a nested module (`std.io.<fn>`) must keep
// compiling and running. This fixture exists so the Task 6B fix cannot
// over-reject: only the unresolved-callee path changed, and a resolved nested
// callee is emitted before the field-access chain code is ever reached.
//
// DEFECT (before the fix): `sf/src/lower.zig`'s `fn_call` nested-chain block
// (`:3984-4007`) early-returned temp 0 whenever the chain walk failed, so an
// undefined nested member call (`std.io.printt(...)`) was silently dropped
// (rc=0, no diagnostic, call absent from the emitted C). The fix makes the
// failure fall through to the generic call path (diagnoses) instead of
// returning.
//
// This fixture is the positive runtime control: every call below is a valid
// nested `std.io.<name>` member and must emit a direct call, link, and run.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   nested-ok
//   int=42
//   done
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        @panic(what);
    }
}

pub fn main() void {
    ck(true, "start");
    std.io.print("nested-ok\n");
    std.io.write("int=");
    std.io.printInt(42);
    std.io.write("\n");
    std.io.write("done\n");
}
