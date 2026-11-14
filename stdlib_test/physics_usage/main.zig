// stdlib_test/physics_usage — std_physics (L5) usage program (R7b pattern).
//
// Builds two identical seeded PBD worlds (3-particle chain, first pinned,
// gravity down), advances both in lockstep, and asserts:
//   - the two worlds remain bit-identical (seeded constraint shuffle);
//   - the pinned particle never moves (pos and prev);
//   - the pinned distance constraints stay near their rest length.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0), ending
// `physics ok`. A mismatch calls @panic.
const std = @import("std");
const phys = @import("std_physics.zig");

const SEED: u64 = 42;

var g_storage: [65536]u8 = undefined;
var g_arena = std.arena.init(g_storage[0..]);

fn bitsOf(v: f32) u32 {
    var p: *u32 = @ptrCast(*u32, &v);
    return p.*;
}

fn samePos(a: [3]f32, b: [3]f32) bool {
    return bitsOf(a[0]) == bitsOf(b[0]) and bitsOf(a[1]) == bitsOf(b[1]) and bitsOf(a[2]) == bitsOf(b[2]);
}

fn absF64(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

fn distance(a: [3]f32, b: [3]f32) f64 {
    var dx: f64 = @floatCast(f64, b[0]) - @floatCast(f64, a[0]);
    var dy: f64 = @floatCast(f64, b[1]) - @floatCast(f64, a[1]);
    var dz: f64 = @floatCast(f64, b[2]) - @floatCast(f64, a[2]);
    return std.math.sqrt(dx * dx + dy * dy + dz * dz);
}

fn buildWorld() phys.PbdWorld {
    var w = phys.pbdInit(&g_arena, 3, 2, SEED) catch @panic("pbdInit");
    w.gravity[0] = 0.0;
    w.gravity[1] = -9.81;
    w.gravity[2] = 0.0;
    w.damping = 0.0;
    w.iterations = 8;
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 2.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 1.0, 2.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 2.0, 2.0, 0.0 }, 1.0);
    phys.pbdPin(&w, 0);
    _ = phys.pbdAddDistance(&w, 0, 1, 1.0);
    _ = phys.pbdAddDistance(&w, 1, 2, 1.0);
    return w;
}

pub fn main() void {
    var w1 = buildWorld();
    var w2 = buildWorld();
    var pin_pos = w1.particles[0].pos;
    var pin_prev = w1.particles[0].prev;
    var dt: f32 = @floatCast(f32, 1.0 / 60.0);

    var s: u32 = 0;
    while (s < 240) : (s += 1) {
        phys.pbdStep(&w1, dt);
        phys.pbdStep(&w2, dt);
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            if (!samePos(w1.particles[@intCast(usize, i)].pos, w2.particles[@intCast(usize, i)].pos)) {
                @panic("seeded worlds diverged");
            }
        }
    }

    if (!samePos(w1.particles[0].pos, pin_pos)) @panic("pin pos moved");
    if (!samePos(w1.particles[0].prev, pin_prev)) @panic("pin prev moved");
    var d1: f64 = distance(w1.particles[0].pos, w1.particles[1].pos);
    var d2: f64 = distance(w1.particles[1].pos, w1.particles[2].pos);
    if (absF64(d1 - 1.0) >= 1e-3 or absF64(d2 - 1.0) >= 1e-3) @panic("rest length");

    std.io.write("physics_usage\n");
    std.io.write("worlds-identical: 1\n");
    std.io.write("pin-fixed: 1\n");
    std.io.write("distance-ok: 1\n");
    std.io.write("physics ok\n");
}
