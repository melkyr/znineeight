// D8 control: typed error-set values (direct const, parameter, return value,
// struct field) all print `error.Bar`.
const std = @import("std");

const E = error{ Foo, Bar };

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
}
