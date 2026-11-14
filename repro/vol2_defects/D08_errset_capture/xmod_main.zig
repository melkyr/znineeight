// D8 cross-module RED: capture of an error-set value returned by an imported
// module prints numeric.
const std = @import("std");
const errors = @import("errors.zig");

pub fn main() void {
    const direct: errors.E = error.Bar;
    std.io.print("direct={}\n", .{direct});
    const ok = errors.mightFail() catch |e| {
        std.io.print("capture={}\n", .{e});
        return;
    };
    std.io.print("ok={}\n", .{ok});
}
