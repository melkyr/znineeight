const std = @import("std.zig");
const E = error{ Bad };
fn f() E!i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        if (err == error.Bad) { std.io.printInt(@intCast(i32, 1)); }
        else { std.io.printInt(@intCast(i32, 0)); }
        return;
    };
    _ = r;
}
