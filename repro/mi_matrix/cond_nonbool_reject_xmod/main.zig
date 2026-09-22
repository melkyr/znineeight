// cond_nonbool_reject_xmod — Task 9B (c): a non-`bool` `if`/`while` condition
// and a non-optional capture condition are invalid Z98/Zig. Official Zig 0.15.2
// rejects `if (a)` (i32) with "expected type 'bool', found 'i32'", and
// `if (q) |v|` with a non-optional `q` with "expected optional type, found
// 'i32'". Task 9B adds `semanticAnalyzerCheckConditionType`
// (`sf/src/semantic_analyzer.zig`) to the shared if/while header: no capture
// requires `bool` (error[3058]); a capture requires an optional or error-union
// condition (also error[3058]).
//
// Contract: rc=2, 0 emitted `.c`, `error[3058]` per site.
const std = @import("std");

const Color = enum { red, green };

pub fn main() void {
    var a: i32 = 1;
    if (a) {
        std.io.print("x\n");
    }
    var u: u32 = 1;
    while (u) {
        std.io.print("x\n");
    }
    var p: *i32 = undefined;
    if (p) {
        std.io.print("x\n");
    }
    var c: Color = Color.red;
    if (c) {
        std.io.print("x\n");
    }
    var o: ?i32 = 1;
    if (o) {
        std.io.print("x\n");
    }
    var q: i32 = 5;
    if (q) |v| {
        std.io.print("{}\n", .{v});
    }
}
