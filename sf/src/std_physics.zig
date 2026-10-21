// std_physics.zig — Z98 std lib L5: Position-Based Dynamics (PBD).
//
// Contract (spec §6.8): alloc arena at pbdInit | errors {OutOfMemory} |
// coroutine no. Imports L1 `std_arena`, L0 `std_mem`, L5 `std_math` and
// `std_rand` (program dependency order: physics -> rand).
//
//   Particle           { pos: [3]f32, prev: [3]f32, inv_mass: f32 }
//   DistanceConstraint { a: u32, b: u32, rest: f32, stiffness: f32 }
//   PbdWorld           { particles, constraints, order, particle_count,
//                        constraint_count, gravity, damping, iterations, rng }
//
// Slices are capacities; *_count are live entries; order.len == constraints.len.
// pbdStep integrates every non-pinned particle with
// `new = pos + (pos-prev)*(1-damping) + g*dt^2`, then stores prev = old pos.
// Each projection iteration identity-fills order[0..constraint_count],
// Fisher–Yates shuffles it with xoshiroBounded(i+1) for i = count-1..1, and
// projects the constraints in order sequence. A distance projection computes
// `len = f32(sqrt(f64(dx*dx+dy*dy+dz*dz)))` (std_math sqrt, f32 store),
// `corr = (len-rest)/len*stiffness`, and moves `a` by
// `dx*corr*wa/(wa+wb)` and `b` by `-dx*corr*wb/(wa+wb)`; len==0 or
// wa+wb==0 is skipped. v1 has no collision constraints. Stiffness is the
// per-iteration fraction (1 = exact in one projection).
const arena_mod = @import("std_arena.zig");
const mem_mod = @import("std_mem.zig");
const math_mod = @import("std_math.zig");
const rand_mod = @import("std_rand.zig");

pub const Particle = struct {
    pos: [3]f32,
    prev: [3]f32,
    inv_mass: f32,
};

pub const DistanceConstraint = struct {
    a: u32,
    b: u32,
    rest: f32,
    stiffness: f32,
};

pub const PbdWorld = struct {
    particles: []Particle,
    constraints: []DistanceConstraint,
    order: []u32,
    particle_count: u32,
    constraint_count: u32,
    gravity: [3]f32,
    damping: f32,
    iterations: u8,
    rng: rand_mod.Xoshiro256,
};

fn particleSlice(ar: *arena_mod.Arena, count: u32) arena_mod.ArenaError![]Particle {
    var n: usize = @intCast(usize, count);
    var bytes: usize = n * @sizeOf(Particle);
    var raw = try arena_mod.alloc(ar, bytes);
    mem_mod.zeroU8(raw, bytes);
    return @ptrCast([*]Particle, raw)[0..n];
}

fn constraintSlice(ar: *arena_mod.Arena, count: u32) arena_mod.ArenaError![]DistanceConstraint {
    var n: usize = @intCast(usize, count);
    var bytes: usize = n * @sizeOf(DistanceConstraint);
    var raw = try arena_mod.alloc(ar, bytes);
    mem_mod.zeroU8(raw, bytes);
    return @ptrCast([*]DistanceConstraint, raw)[0..n];
}

fn orderSlice(ar: *arena_mod.Arena, count: u32) arena_mod.ArenaError![]u32 {
    var n: usize = @intCast(usize, count);
    var bytes: usize = n * @sizeOf(u32);
    var raw = try arena_mod.alloc(ar, bytes);
    mem_mod.zeroU8(raw, bytes);
    return @ptrCast([*]u32, raw)[0..n];
}

pub fn pbdInit(arena: *arena_mod.Arena, particle_count: u32, constraint_count: u32, seed: u64) !PbdWorld {
    var particles = try particleSlice(arena, particle_count);
    var constraints = try constraintSlice(arena, constraint_count);
    var order = try orderSlice(arena, constraint_count);
    return PbdWorld{
        .particles = particles,
        .constraints = constraints,
        .order = order,
        .particle_count = 0,
        .constraint_count = 0,
        .gravity = [3]f32{ 0.0, 0.0, 0.0 },
        .damping = 0.0,
        .iterations = 4,
        .rng = rand_mod.xoshiroInit(seed),
    };
}

pub fn pbdAddParticle(w: *PbdWorld, pos: [3]f32, inv_mass: f32) u32 {
    if (@intCast(usize, w.particle_count) >= w.particles.len) @panic("pbdAddParticle: over capacity");
    var zero: f32 = 0.0;
    if (inv_mass < zero) @panic("pbdAddParticle: negative inv_mass");
    var idx: u32 = w.particle_count;
    var ii: usize = @intCast(usize, idx);
    w.particles[ii].pos[0] = pos[0];
    w.particles[ii].pos[1] = pos[1];
    w.particles[ii].pos[2] = pos[2];
    w.particles[ii].prev[0] = pos[0];
    w.particles[ii].prev[1] = pos[1];
    w.particles[ii].prev[2] = pos[2];
    w.particles[ii].inv_mass = inv_mass;
    w.particle_count = idx + 1;
    return idx;
}

pub fn pbdAddDistance(w: *PbdWorld, a: u32, b: u32, stiffness: f32) u32 {
    if (@intCast(usize, w.constraint_count) >= w.constraints.len) @panic("pbdAddDistance: over capacity");
    if (a == b) @panic("pbdAddDistance: a == b");
    if (a >= w.particle_count or b >= w.particle_count) @panic("pbdAddDistance: index out of range");
    var ia: usize = @intCast(usize, a);
    var ib: usize = @intCast(usize, b);
    var dx: f32 = w.particles[ib].pos[0] - w.particles[ia].pos[0];
    var dy: f32 = w.particles[ib].pos[1] - w.particles[ia].pos[1];
    var dz: f32 = w.particles[ib].pos[2] - w.particles[ia].pos[2];
    var rest: f32 = @floatCast(f32, math_mod.sqrt(@floatCast(f64, dx * dx + dy * dy + dz * dz)));
    var idx: u32 = w.constraint_count;
    var ci: usize = @intCast(usize, idx);
    w.constraints[ci].a = a;
    w.constraints[ci].b = b;
    w.constraints[ci].rest = rest;
    w.constraints[ci].stiffness = stiffness;
    w.constraint_count = idx + 1;
    return idx;
}

pub fn pbdPin(w: *PbdWorld, i: u32) void {
    if (i >= w.particle_count) @panic("pbdPin: index out of range");
    w.particles[@intCast(usize, i)].inv_mass = 0.0;
}

pub fn pbdStep(w: *PbdWorld, dt: f32) void {
    if (w.particle_count == 0) return;

    var zero: f32 = 0.0;
    var one: f32 = 1.0;
    var dt2: f32 = dt * dt;
    var keep: f32 = one - w.damping;
    var i: u32 = 0;
    while (i < w.particle_count) : (i += 1) {
        var ii: usize = @intCast(usize, i);
        if (w.particles[ii].inv_mass == zero) continue;
        var ox: f32 = w.particles[ii].pos[0];
        var oy: f32 = w.particles[ii].pos[1];
        var oz: f32 = w.particles[ii].pos[2];
        var vx: f32 = (ox - w.particles[ii].prev[0]) * keep;
        var vy: f32 = (oy - w.particles[ii].prev[1]) * keep;
        var vz: f32 = (oz - w.particles[ii].prev[2]) * keep;
        var nx: f32 = ox + vx + w.gravity[0] * dt2;
        var ny: f32 = oy + vy + w.gravity[1] * dt2;
        var nz: f32 = oz + vz + w.gravity[2] * dt2;
        w.particles[ii].prev[0] = ox;
        w.particles[ii].prev[1] = oy;
        w.particles[ii].prev[2] = oz;
        w.particles[ii].pos[0] = nx;
        w.particles[ii].pos[1] = ny;
        w.particles[ii].pos[2] = nz;
    }

    if (w.constraint_count == 0 or w.iterations == 0) return;

    var it: u8 = 0;
    while (it < w.iterations) : (it += 1) {
        var j: u32 = 0;
        while (j < w.constraint_count) : (j += 1) {
            w.order[@intCast(usize, j)] = j;
        }
        var k: u32 = w.constraint_count - 1;
        while (k >= 1) : (k -= 1) {
            var bound: u64 = @intCast(u64, k) + 1;
            var r: u32 = @intCast(u32, rand_mod.xoshiroBounded(&w.rng, bound));
            var tmp: u32 = w.order[@intCast(usize, k)];
            w.order[@intCast(usize, k)] = w.order[@intCast(usize, r)];
            w.order[@intCast(usize, r)] = tmp;
        }
        var cidx: u32 = 0;
        while (cidx < w.constraint_count) : (cidx += 1) {
            var ci: usize = @intCast(usize, w.order[@intCast(usize, cidx)]);
            var a: u32 = w.constraints[ci].a;
            var b: u32 = w.constraints[ci].b;
            var rest: f32 = w.constraints[ci].rest;
            var stiffness: f32 = w.constraints[ci].stiffness;
            var ia: usize = @intCast(usize, a);
            var ib: usize = @intCast(usize, b);
            var dx: f32 = w.particles[ib].pos[0] - w.particles[ia].pos[0];
            var dy: f32 = w.particles[ib].pos[1] - w.particles[ia].pos[1];
            var dz: f32 = w.particles[ib].pos[2] - w.particles[ia].pos[2];
            var len: f32 = @floatCast(f32, math_mod.sqrt(@floatCast(f64, dx * dx + dy * dy + dz * dz)));
            if (len == zero) continue;
            var wa: f32 = w.particles[ia].inv_mass;
            var wb: f32 = w.particles[ib].inv_mass;
            var wsum: f32 = wa + wb;
            if (wsum == zero) continue;
            var corr: f32 = (len - rest) / len * stiffness;
            var cax: f32 = dx * corr * wa / wsum;
            var cay: f32 = dy * corr * wa / wsum;
            var caz: f32 = dz * corr * wa / wsum;
            var cbx: f32 = dx * corr * wb / wsum;
            var cby: f32 = dy * corr * wb / wsum;
            var cbz: f32 = dz * corr * wb / wsum;
            w.particles[ia].pos[0] = w.particles[ia].pos[0] + cax;
            w.particles[ia].pos[1] = w.particles[ia].pos[1] + cay;
            w.particles[ia].pos[2] = w.particles[ia].pos[2] + caz;
            w.particles[ib].pos[0] = w.particles[ib].pos[0] - cbx;
            w.particles[ib].pos[1] = w.particles[ib].pos[1] - cby;
            w.particles[ib].pos[2] = w.particles[ib].pos[2] - cbz;
        }
    }
}
