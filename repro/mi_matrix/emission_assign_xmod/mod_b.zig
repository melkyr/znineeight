const std = @import("std");
const mod_a = @import("mod_a.zig");
const Type = mod_a.Type;
const CoercionKind = mod_a.CoercionKind;

pub fn run() void {
    {
        var ck: Type = mod_a.makeType();
        std.io.printInt(@intCast(i32, ck.id));
    }
    {
        var ck: CoercionKind = mod_a.makeCoercion();
        std.io.printInt(@intCast(i32, @enumToInt(ck)));
    }
}
