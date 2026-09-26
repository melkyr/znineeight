// FE (D8 + D11) positive fixture — error-set capture printing (local +
// cross-module) and qualified/shorthand switch prong captures (tagged-union
// and enum operands, used and unused).
//
// D8: `catch |e| print("{}", .{e})` must print `error.Name` (the capture temp
// is typed as the sema error set, not hard i32).
// D11: `Shape.circle => |r|` binds exactly like `.circle => |r|`; enum-operand
// captures bind the operand value Zig-style and never SIGSEGV when unused.
const std = @import("std");
const helper = @import("helper.zig");

const E = error{ Foo, Bar };

fn mightFail(flag: bool) E!i32 {
    if (flag) return error.Bar;
    return 7;
}

fn showError(e: E) void {
    std.io.print("show={}\n", .{e});
}

const Shape = union(enum) {
    circle: i32,
    rect: struct { w: i32, h: i32 },
    empty,
};

fn shapeQualified(s: Shape) i32 {
    return switch (s) {
        Shape.circle => |r| r,
        .rect => |rc| rc.w * rc.h,
        else => 0,
    };
}

fn shapeUnused(s: Shape) i32 {
    return switch (s) {
        Shape.circle => |v| 5,
        .rect => |v| 4,
        else => 0,
    };
}

const Color = enum { red, green, blue };

fn useColor(c: Color) i32 {
    std.io.print("ecap={}\n", .{c});
    return 1;
}

fn colorUsed(c: Color) i32 {
    return switch (c) {
        Color.red => |v| useColor(v),
        .green => |v| useColor(v),
        else => 0,
    };
}

fn colorUnused(c: Color) i32 {
    return switch (c) {
        .blue => |v| 3,
        Color.red => |v| 9,
        else => 0,
    };
}

fn captureLocal() void {
    const ok = mightFail(true) catch |e| {
        std.io.print("cap={}\n", .{e});
        return;
    };
    std.io.print("unreached {}\n", .{ok});
}

fn captureXmod() void {
    const ok = helper.mightFail(true) catch |e| {
        std.io.print("xcap={}\n", .{e});
        return;
    };
    std.io.print("unreached {}\n", .{ok});
}

pub fn main() void {
    const direct: E = error.Bar;
    std.io.print("direct={}\n", .{direct});
    showError(error.Bar);

    captureLocal();
    captureXmod();

    var a: Shape = Shape{ .circle = 12 };
    var b: Shape = Shape{ .rect = .{ .w = 2, .h = 3 } };
    std.io.print("tucap={}\n", .{shapeQualified(a)});
    std.io.print("tucap2={}\n", .{shapeQualified(b)});
    std.io.print("tucap3={}\n", .{shapeUnused(a)});
    std.io.print("tucap4={}\n", .{shapeUnused(b)});

    var bx: helper.Box = helper.Box{ .num = 8 };
    std.io.print("tucap5={}\n", .{helper.boxVal(bx)});
    var bx2: helper.Box = helper.Box{ .num = 6 };
    const q6 = switch (bx2) {
        helper.Box.num => |v| v,
        else => 0,
    };
    std.io.print("tucap6={}\n", .{q6});

    const e1 = colorUsed(Color.red);
    std.io.print("enumcap={}\n", .{e1});
    const e2 = colorUsed(Color.green);
    std.io.print("enumcap2={}\n", .{e2});
    std.io.print("enumcap3={}\n", .{colorUnused(Color.blue)});
    std.io.print("enumcap4={}\n", .{colorUnused(Color.red)});
    std.io.print("done\n", .{});
}
