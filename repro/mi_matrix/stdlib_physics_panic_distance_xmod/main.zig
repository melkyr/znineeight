// stdlib_physics_panic_distance_xmod — over-capacity pbdAddDistance
// expected-failure probe (spec §6.8 precondition).
//
// pbdInit reserves one constraint slot; the second pbdAddDistance call is a
// caller bug and MUST terminate at @panic (SIGTRAP, rc 133) before any stdout
// is produced. The trailing write is only reached if the guard is dropped.
//
// Expected-failure contract: empty stdout, rc 133.
const std = @import("std");
const phys = @import("std_physics.zig");

var storage: [4096]u8 = undefined;

pub fn main() void {
    var ar = std.arena.init(storage[0..]);
    var w = phys.pbdInit(&ar, 2, 1, 1) catch @panic("init");
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 1.0, 0.0, 0.0 }, 1.0);
    _ = phys.pbdAddDistance(&w, 0, 1, 1.0);
    _ = phys.pbdAddDistance(&w, 0, 1, 1.0);
    std.io.write("physics distance panic no-trap FAIL\n");
}
