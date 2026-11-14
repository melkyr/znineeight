// D1 boundary control: plain `defer` in main.zig, `for`-body `defer` in
// helper_loop.zig. Splitting the two shapes across modules avoids the crash.
const std = @import("std");
const helper = @import("helper_loop.zig");

fn plain() void {
    defer std.io.print("xmod-plain-defer\n", .{});
    std.io.print("xmod-plain-body\n", .{});
}

pub fn main() void {
    plain();
    helper.loopDefer();
}
