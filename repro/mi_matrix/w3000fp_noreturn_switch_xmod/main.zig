// w3000fp_noreturn_switch_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `const y: i32 = switch (x) { 0 => return 10, else => return 20 };` — every
// prong diverges, so the switch expression is `noreturn`. The switch resolver
// skips `noreturn` prongs (`sf/src/semantic_analyzer.zig:2003`) leaving
// `unified == 0`, then materializes `TYPE_VOID` (`:2040`), so the var-decl warns
// `source: void / target: i32` (`:2978-2993`).
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `10`; the diverging prong returns correctly.
const std = @import("std");

fn pick(x: i32) i32 {
    const y: i32 = switch (x) {
        0 => return 10,
        else => return 20,
    };
    return y;
}

pub fn main() void {
    std.io.printInt(pick(0));
    std.io.writeByte('\n');
}
