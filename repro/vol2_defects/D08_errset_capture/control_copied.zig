// D8 sibling shape: copying the capture into an annotated error-set variable
// does NOT restore the name -- provenance is lost at the capture.
const std = @import("std");

const E = error{ Foo, Bar };

fn mightFail() E!i32 {
    return error.Bar;
}

pub fn main() void {
    const ok = mightFail() catch |e| {
        const copied: E = e;
        std.io.print("copied={}\n", .{copied});
        return;
    };
    std.io.print("ok={}\n", .{ok});
}
