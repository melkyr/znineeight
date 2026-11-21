// stdlib_physics_basic_xmod — std_physics (L5) PBD GREEN fixture.
//
// Checks (spec §6.8):
//   - free fall: 1 particle, g=-9.81 y, dt=1/60, 600 steps within 1% of the
//     continuous analytic 0.5*g*T^2;
//   - pinned distance constraint with an initial velocity converges back to
//     the rest length;
//   - stiffness=1 restores the rest length in one projection, stiffness=0.5
//     moves halfway;
//   - a 10-particle chain (first pinned, spacing 1, gravity {0,-9.81,0},
//     dt=1/60, 8 iterations, stiffness 1) has max adjacent stretch < 5%;
//   - a no-force particle is bit-identical after 1000 steps;
//   - a pinned particle is bit-identical under gravity + constraints;
//   - an 8-seed asymmetric scenario yields at least two distinct final
//     position vectors (a dead constraint shuffle would yield one).
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0). A mismatch
// calls @panic.
const std = @import("std");
const phys = @import("std_physics.zig");

const DT_DEN: f64 = 60.0;
const ANALYTIC_FALL: f64 = 490.5;

var g_storage: [65536]u8 = undefined;
var g_arena = std.arena.init(g_storage[0..]);

fn bitsOf(v: f32) u32 {
    var p: *u32 = @ptrCast(*u32, &v);
    return p.*;
}

fn samePos(a: [3]f32, b: [3]f32) bool {
    return bitsOf(a[0]) == bitsOf(b[0]) and bitsOf(a[1]) == bitsOf(b[1]) and bitsOf(a[2]) == bitsOf(b[2]);
}

fn sameBits(a: [3]u32, b: [3]u32) bool {
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2];
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

fn makeWorld(np: u32, nc: u32, seed: u64) phys.PbdWorld {
    std.arena.reset(&g_arena);
    return phys.pbdInit(&g_arena, np, nc, seed) catch @panic("pbdInit");
}

fn setGravity(w: *phys.PbdWorld, x: f32, y: f32, z: f32) void {
    w.gravity[0] = x;
    w.gravity[1] = y;
    w.gravity[2] = z;
}

fn setPos(w: *phys.PbdWorld, i: u32, x: f32, y: f32, z: f32) void {
    var ii: usize = @intCast(usize, i);
    w.particles[ii].pos[0] = x;
    w.particles[ii].pos[1] = y;
    w.particles[ii].pos[2] = z;
}

fn setPrev(w: *phys.PbdWorld, i: u32, x: f32, y: f32, z: f32) void {
    var ii: usize = @intCast(usize, i);
    w.particles[ii].prev[0] = x;
    w.particles[ii].prev[1] = y;
    w.particles[ii].prev[2] = z;
}

fn freeFall() void {
    var w = makeWorld(1, 0, 1);
    setGravity(&w, 0.0, -9.81, 0.0);
    w.damping = 0.0;
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
    var dt: f32 = @floatCast(f32, 1.0 / DT_DEN);
    var s: u32 = 0;
    while (s < 600) : (s += 1) phys.pbdStep(&w, dt);
    var got: f64 = -@floatCast(f64, w.particles[0].pos[1]);
    var rel: f64 = absF64(got - ANALYTIC_FALL) / ANALYTIC_FALL;
    if (rel >= 0.01) @panic("freefall tolerance");
    std.io.write("freefall ok\n");
}

fn pinnedVelocity() void {
    var w = makeWorld(2, 1, 7);
    setGravity(&w, 0.0, 0.0, 0.0);
    w.iterations = 4;
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 1.0, 0.0, 0.0 }, 1.0);
    phys.pbdPin(&w, 0);
    _ = phys.pbdAddDistance(&w, 0, 1, 1.0);
    var dt: f32 = @floatCast(f32, 1.0 / DT_DEN);
    var vz: f32 = @floatCast(f32, 3.0) * dt;
    var px: f32 = w.particles[1].pos[0];
    setPrev(&w, 1, px - vz, w.particles[1].pos[1], w.particles[1].pos[2]);
    var s: u32 = 0;
    while (s < 120) : (s += 1) phys.pbdStep(&w, dt);
    var d: f64 = distance(w.particles[0].pos, w.particles[1].pos);
    if (absF64(d - 1.0) >= 1e-4) @panic("pinned velocity convergence");
    std.io.write("pinned ok\n");
}

fn stiffnessCase(stiffness: f32, want: f64) void {
    var w = makeWorld(2, 1, 9);
    setGravity(&w, 0.0, 0.0, 0.0);
    w.iterations = 1;
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 1.0, 0.0, 0.0 }, 1.0);
    phys.pbdPin(&w, 0);
    _ = phys.pbdAddDistance(&w, 0, 1, stiffness);
    setPos(&w, 1, 2.0, 0.0, 0.0);
    setPrev(&w, 1, 2.0, 0.0, 0.0);
    phys.pbdStep(&w, 0.0);
    var d: f64 = distance(w.particles[0].pos, w.particles[1].pos);
    if (absF64(d - want) >= 1e-5) @panic("stiffness projection");
}

fn chain() void {
    var w = makeWorld(10, 9, 12345);
    setGravity(&w, 0.0, -9.81, 0.0);
    w.damping = 0.0;
    w.iterations = 8;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        _ = phys.pbdAddParticle(&w, [3]f32{ @intToFloat(f32, i), 0.0, 0.0 }, 1.0);
        if (i > 0) _ = phys.pbdAddDistance(&w, i - 1, i, 1.0);
    }
    phys.pbdPin(&w, 0);
    var dt: f32 = @floatCast(f32, 1.0 / DT_DEN);
    var s: u32 = 0;
    while (s < 600) : (s += 1) phys.pbdStep(&w, dt);
    var worst: f64 = 0.0;
    var j: u32 = 1;
    while (j < 10) : (j += 1) {
        var d: f64 = distance(w.particles[j - 1].pos, w.particles[j].pos);
        var err: f64 = absF64(d - 1.0);
        if (err > worst) worst = err;
    }
    if (worst >= 0.05) @panic("chain stretch");
    std.io.write("chain ok\n");
}

fn noForce() void {
    var w = makeWorld(1, 0, 3);
    setGravity(&w, 0.0, 0.0, 0.0);
    w.damping = 0.0;
    var start = [3]f32{ 1.25, -3.5, 2.75 };
    _ = phys.pbdAddParticle(&w, start, 1.0);
    var dt: f32 = @floatCast(f32, 1.0 / DT_DEN);
    var s: u32 = 0;
    while (s < 1000) : (s += 1) phys.pbdStep(&w, dt);
    if (!samePos(w.particles[0].pos, start)) @panic("no-force drift");
    std.io.write("noforce ok\n");
}

fn pinnedFixed() void {
    var w = makeWorld(2, 1, 4);
    setGravity(&w, 0.0, -9.81, 0.0);
    w.iterations = 4;
    _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
    _ = phys.pbdAddParticle(&w, [3]f32{ 1.0, 0.0, 0.0 }, 1.0);
    phys.pbdPin(&w, 0);
    _ = phys.pbdAddDistance(&w, 0, 1, 1.0);
    var p0_pos = w.particles[0].pos;
    var p0_prev = w.particles[0].prev;
    var dt: f32 = @floatCast(f32, 1.0 / DT_DEN);
    var s: u32 = 0;
    while (s < 100) : (s += 1) phys.pbdStep(&w, dt);
    if (!samePos(w.particles[0].pos, p0_pos)) @panic("pinned pos moved");
    if (!samePos(w.particles[0].prev, p0_prev)) @panic("pinned prev moved");
    std.io.write("pin ok\n");
}

fn seedSpread() void {
    var distinct: u32 = 0;
    var seen: [8][3]u32 = undefined;
    var bump_a: f32 = 0.15;
    var bump_b: f32 = 0.2;
    var bump_c: f32 = 0.1;
    var seed: u64 = 1;
    while (seed <= 8) : (seed += 1) {
        var w = makeWorld(4, 5, seed);
        setGravity(&w, 0.0, 0.0, 0.0);
        w.damping = 0.0;
        w.iterations = 1;
        _ = phys.pbdAddParticle(&w, [3]f32{ 0.0, 0.0, 0.0 }, 1.0);
        _ = phys.pbdAddParticle(&w, [3]f32{ 1.2, 0.3, 0.0 }, 1.0);
        _ = phys.pbdAddParticle(&w, [3]f32{ 2.1, -0.2, 0.1 }, 1.0);
        _ = phys.pbdAddParticle(&w, [3]f32{ 3.0, 0.5, -0.1 }, 1.0);
        _ = phys.pbdAddDistance(&w, 0, 1, 0.6);
        _ = phys.pbdAddDistance(&w, 1, 2, 0.6);
        _ = phys.pbdAddDistance(&w, 2, 3, 0.6);
        _ = phys.pbdAddDistance(&w, 0, 2, 0.6);
        _ = phys.pbdAddDistance(&w, 1, 3, 0.6);
        w.particles[1].pos[0] = w.particles[1].pos[0] + bump_a;
        w.particles[1].prev[0] = w.particles[1].pos[0];
        w.particles[1].prev[1] = w.particles[1].pos[1];
        w.particles[1].prev[2] = w.particles[1].pos[2];
        w.particles[2].pos[1] = w.particles[2].pos[1] + bump_b;
        w.particles[2].prev[0] = w.particles[2].pos[0];
        w.particles[2].prev[1] = w.particles[2].pos[1];
        w.particles[2].prev[2] = w.particles[2].pos[2];
        w.particles[3].pos[0] = w.particles[3].pos[0] - bump_c;
        w.particles[3].prev[0] = w.particles[3].pos[0];
        w.particles[3].prev[1] = w.particles[3].pos[1];
        w.particles[3].prev[2] = w.particles[3].pos[2];
        phys.pbdStep(&w, 0.0);
        var si: usize = @intCast(usize, seed - 1);
        seen[si][0] = bitsOf(w.particles[3].pos[0]);
        seen[si][1] = bitsOf(w.particles[3].pos[1]);
        seen[si][2] = bitsOf(w.particles[3].pos[2]);
    }
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        var novel: bool = true;
        var j: u32 = 0;
        while (j < i) : (j += 1) {
            if (sameBits(seen[@intCast(usize, i)], seen[@intCast(usize, j)])) novel = false;
        }
        if (novel) distinct += 1;
    }
    if (distinct < 2) @panic("dead constraint shuffle");
    std.io.write("distinct: ");
    std.io.printInt(@intCast(i32, distinct));
    std.io.write("\n");
}


pub fn main() void {
    freeFall();
    pinnedVelocity();
    stiffnessCase(1.0, 1.0);
    std.io.write("stiff1 ok\n");
    stiffnessCase(0.5, 1.5);
    std.io.write("stiff05 ok\n");
    chain();
    noForce();
    pinnedFixed();
    seedSpread();
    std.io.write("physics basic ok\n");
}
