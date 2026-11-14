// safe_null_unwrap_xmod — emit-level `-fsafe` defense-in-depth fixture (A4F).
//
// `. ?` is not parsed yet and every reachable `unwrap_optional` emit is already
// control-flow-guarded by a preceding `check_optional`, so this check cannot be
// a runtime RED->GREEN trap. GREEN ships an emit-level assertion only: the
// `.unwrap_optional` arm must emit `if (!(<src>.has_value)) { pal_trap(); }`
// immediately before the `<src>.value` read. Runtime trapping is unverifiable
// until `.?` lands.
//
// Runtime contract (both modes): `o` is null, so `orelse` takes the 42
// fallback and stdout is deterministic `7\n` (rc 0). The fixture exists to
// inspect the emitted C, not to trap.
const std = @import("std");

fn get() ?i32 {
    return null;
}

pub fn main() void {
    var x = get() orelse 7;
    std.io.printInt(x);
    std.io.writeByte('\n');
}
