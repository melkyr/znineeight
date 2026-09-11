// safe_unwrap_guard_xmod — A16 null-unwrap guard EMIT-LEVEL pin (C89-AHEAD).
//
// `.?` is not parsed by this compiler, so the `.unwrap_optional` path is only
// reached through `if (o) |cap| ...` capture and `orelse` (both already
// branch-guarded, so there is no runtime RED->GREEN trap). This fixture pins the
// EMIT-LEVEL guard: under `-fsafe` the emitted C for the capture must contain
// `if (!(<opt>.has_value)) { pal_trap(); }`; under `-ffast` the guard is absent.
//
// A16 moves that guard into the backend-neutral `unwrap_optional_checked` LIR op
// (emitted by lowering only under `-fsafe` for non-void payloads); the emitter
// only maps it to the dumb guard + `.value` read. `v` is non-null, so both
// modes run rc 0 and print `-5`.
const std = @import("std");

fn take_cap(o: ?i32) i32 {
    var x: i32 = if (o) |cap| cap else 0;
    return x;
}

pub fn main() void {
    var v: i32 = take_cap(-5);
    std.io.printInt(v);
    std.io.writeByte('\n');
}
