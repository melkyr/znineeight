// D8 sibling shape: the capture printed in isolation.
const std = @import("std");

const E = error{ Foo, Bar };

fn mightFail() E!i32 {
    return error.Bar;
}

pub fn main() void {
    const ok = mightFail() catch |e| {
        std.io.print("capture={}\n", .{e});
        return;
    };
    std.io.print("ok={}\n", .{ok});
}
