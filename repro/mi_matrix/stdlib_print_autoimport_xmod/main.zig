// stdlib_print_autoimport_xmod — Task 1 (z98-print-formatting) auto-import pin.
//
// This program imports `std_io.zig` DIRECTLY (not through `std`) and calls the
// two-argument `print` entry. std_io.zig does not import std_fmt.zig, so the
// only thing that puts the formatting module in the graph is the compiler's
// auto-import in the print path (phase_ImportResolution -> std_fmt.zig);
// without it the mangled `std.fmt` call sites would have no definition and the
// gcc link would fail. It also pins the width of the auto-import trigger: a
// call whose callee is named `print`.
//
// Expected stdout (exact) and rc 0:
//   auto=9 ok=true
const io = @import("std_io.zig");

pub fn main() void {
    var n: i32 = 9;
    io.print("auto={}", .{n});
    var b: bool = true;
    io.print(" ok={}\n", .{b});
}
