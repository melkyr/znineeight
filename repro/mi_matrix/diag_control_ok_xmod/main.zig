// diag_control_ok_xmod — control fixture for A7F failure diagnostics.
// Proves the new diagnostics do NOT flag correct Zig:
//   * `if`/`else` where BOTH branches return;
//   * `switch` whose every prong returns (with `else`);
//   * an explicit `var y: i32 = undefined;` escape.
// Contract (GREEN): compiles + runs, prints "1\n".
const std = @import("std");

fn pick(x: i32) i32 {
    if (x > 0) {
        return 1;
    } else {
        return 0;
    }
}

fn pick2(x: i32) i32 {
    switch (x) {
        0 => return 0,
        else => return 1,
    }
}

pub fn main() void {
    var y: i32 = undefined;
    y = pick(1) + pick2(0);
    std.io.printInt(@intCast(i32, y));
    std.io.writeByte('\n');
}
