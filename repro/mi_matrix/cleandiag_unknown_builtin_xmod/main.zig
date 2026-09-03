// cleandiag_unknown_builtin_xmod — CLEAN-DIAG fixture (unsupported builtin).
// Feature: unknown @builtin names get a clean error, not silent mis-emission.
// RED today: @totallyBogus parses as builtin_call, no sema/lower handler ->
//   silent dump rc=0, valid C, result dropped -> prints 0 (or invalid C).
// GREEN (contract): dump rc=2, 0 .c, error[3000]: unsupported builtin function.
const std = @import("std");

pub fn main() void {
    var r = @totallyBogus(i32, 5);
    std.io.printInt(r);
    std.io.writeByte('\n');
}
