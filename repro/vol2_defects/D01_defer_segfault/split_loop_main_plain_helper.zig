// D1 boundary control: `for`-body `defer` in main.zig, plain `defer` in
// helper_plain.zig. The inverse split also avoids the crash.
const std = @import("std");
const helper = @import("helper_plain.zig");

fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("m-loop-defer\n", .{});
        std.io.print("m-loop {}\n", .{v});
    }
}

pub fn main() void {
    helper.plain();
    loopDefer();
}
