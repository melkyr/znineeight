const std = @import("std.zig");
const E = error{ Bad, Other };
fn f() E!i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        switch (err) {
            error.Bad => std.io.printInt(@intCast(i32, 1)),
            error.Other => std.io.printInt(@intCast(i32, 2)),
            else => std.io.printInt(@intCast(i32, 0)),
        }
        return;
    };
    _ = r;
}
