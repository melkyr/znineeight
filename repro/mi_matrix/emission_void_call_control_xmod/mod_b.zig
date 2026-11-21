const mod_a = @import("mod_a.zig");

pub fn callVoid() void {
    var f: fn (i32) void = mod_a.foo;
    f(3);
}
