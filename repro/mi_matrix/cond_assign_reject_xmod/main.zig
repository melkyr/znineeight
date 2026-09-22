// cond_assign_reject_xmod — Task 9B (a): assignment in a condition is invalid
// Z98/Zig. Official Zig 0.15.2 rejects `if (a = 3)` / `if (a += 1)` /
// `while (a = 0)` / `switch (a = 3)` with a PARSE error ("expected ')', found
// '='"), because assignment is a statement, not an expression. Task 9B fixes
// the condition `min_prec` (`sf/src/parser.zig`) to `Prec.prec_orelse`, which
// excludes `Prec.assignment`; the `)` expect then fails with error[2000].
// The same class covers a parenthesized assignment as an expression
// (`var b = (a = 3);`, m1240 ruling 5) via parserParseGroupedExpr.
//
// Contract: rc=2, 0 emitted `.c`, `error[2000]` (parse-level).
const std = @import("std");

pub fn main() void {
    var a: i32 = 1;
    if (a = 3) {
        std.io.print("x\n");
    }
    if (a += 1) {
        std.io.print("x\n");
    }
    while (a = 0) {
        std.io.print("x\n");
    }
    switch (a = 3) {
        3 => { std.io.print("x\n"); },
        else => {},
    }
    var b: i32 = (a = 3);
    _ = b;
}
