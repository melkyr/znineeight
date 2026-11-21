// diag_ignored_error_xmod — compile-time diagnostic: ignored error union.
// Contract (GREEN): a statement whose expression is an error union and whose
//   result is unused is an ERROR (error[3015]), dump rc=2, 0 emitted .c.
//   Scope is error-union-only (spec §3.4); require try/catch/assignment.
// RED (today, pre-A7F): silently accepted, error discarded, runs (prints blank).
const std = @import("std");

fn mightFail() !void {
    return error.Bad;
}

pub fn main() void {
    mightFail();
    std.io.writeByte('\n');
}
