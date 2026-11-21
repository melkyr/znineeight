const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_b.Emitter{ .buf = undefined, .pos = 0 };
    var cases: [2]mod_a.SwitchCase = undefined;
    cases[0] = mod_a.makeCase(1, 3);
    cases[1] = mod_a.makeCase(2, 4);
    var inst = mod_a.makeSwitchBr(0, 2, 5);
    mod_b.emitInst(&em, inst, cases[0..]);
    std.io.printInt(@intCast(i32, @intCast(u32, em.pos)));
}
