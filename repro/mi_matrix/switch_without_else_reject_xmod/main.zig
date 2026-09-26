// switch_without_else_reject_xmod — FA-a reject fixture for error[3068]
// `switch must have an 'else' prong` (Language Spec §3.1: the `else` prong is
// mandatory in ALL switch expressions, value AND statement position).
//
// Pre-FA-a the missing `else` was accepted (semantic_analyzer.zig tombstone)
// and a value switch that matched no prong read an uninitialized result temp
// (D3 garbage). FA-a fills the tombstone; every no-`else` switch below must
// reject with rc 2 / 0 `.c` and exactly one dedicated diagnostic per switch
// node (deduped per node — the exhaustive enum/TU switches are deliberately
// listed without `else` here to pin that the strict rule is unconditional).
//
// Exact diagnostic census: 7 x error[3068]
//   1. partial i32 value switch              (main.zig partial)
//   2. exhaustive enum value switch          (main.zig exhaustiveEnum)
//   3. exhaustive enum statement switch      (main.zig stmtNoElse)
//   4. exhaustive tagged-union value switch  (main.zig exhaustiveTU)
//   5. partial i32 value switch in helper.zig (cross-module helper.pick)
//   6. zero-prong value switch               (main.zig zeroProngValue)
//   7. zero-prong statement switch           (main.zig zeroProngStmt)
// rc 2 / 0 emitted `.c`.
const helper = @import("helper.zig");
const std = @import("std");

const Color = enum { Red, Green, Blue };
const Value = union(enum) { Nil, Int: i32 };

fn partial(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
    };
}

fn exhaustiveEnum(c: Color) i32 {
    return switch (c) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}

fn stmtNoElse(c: Color) void {
    switch (c) {
        .Red => {},
        .Green => {},
        .Blue => {},
    }
}

fn exhaustiveTU(v: Value) i32 {
    return switch (v) {
        .Nil => 0,
        .Int => |x| x,
    };
}

// FA-a fix round 1: `switch (x) {}` used to escape the gate through the
// zero-prong early returns (accepted rc 0; in value position it read the
// poisoned result temp). Both positions must reject.
fn zeroProngValue(x: i32) i32 {
    return switch (x) {};
}

fn zeroProngStmt(c: Color) void {
    switch (c) {}
}

pub fn main() void {
    std.io.print("{} {} {}\n", .{ partial(1), exhaustiveEnum(Color.Red), exhaustiveTU(Value.Nil) });
    std.io.print("{}\n", .{zeroProngValue(1)});
    stmtNoElse(Color.Red);
    zeroProngStmt(Color.Red);
    _ = helper.pick(1);
}
