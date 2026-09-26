// D8 in-module RED: a `catch |e|` error-set capture prints numeric (the error
// code) where the same error-set value printed directly prints `error.Bar`.
// Copying the capture into an annotated variable keeps the numeric form.
const std = @import("std");

const E = error{ Foo, Bar };

fn mightFail(flag: bool) E!i32 {
    if (flag) return error.Bar;
    return 1;
}

fn show(e: E) void {
    std.io.print("param={}\n", .{e});
}

fn getErr() E {
    return error.Bar;
}

const Holder = struct { e: E };

pub fn main() void {
    const direct: E = error.Bar;
    std.io.print("direct={}\n", .{direct});
    show(error.Bar);
    const ret = getErr();
    std.io.print("return={}\n", .{ret});
    var h: Holder = .{ .e = error.Bar };
    std.io.print("field={}\n", .{h.e});

    const ok = mightFail(false) catch 0;
    std.io.print("ok={}\n", .{ok});
    const caught = mightFail(true) catch |e| {
        const copied: E = e;
        std.io.print("capture={}\n", .{e});
        std.io.print("copied={}\n", .{copied});
        return;
    };
    std.io.print("unreached {}\n", .{caught});
}
