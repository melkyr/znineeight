// stdlib_physics_cross_xmod — std_physics (L5) crosscheck driver.
//
// Default mode (fixture gate): deterministic `physics cross ok\n`.
//
// `--crosscheck` reads scenarios until EOF. Each scenario is line-oriented:
//   <seed decimal>
//   <gravity_x> <gravity_y> <gravity_z>       (8-hex f32 bit patterns)
//   <damping>                                 (8-hex f32 bit pattern)
//   <iterations decimal>
//   <steps decimal>
//   <dt>                                      (8-hex f32 bit pattern)
//   <particle_count decimal> <constraint_count decimal>
//   <x> <y> <z> <inv_mass>                    (particle_count lines, f32 hex)
//   <a> <b> <stiffness>                       (constraint_count lines; a,b
//                                              decimal, stiffness f32 hex)
// After `steps` pbdStep calls it prints exactly one line per particle:
// `<x> <y> <z>` as 8-hex f32 bit patterns. Malformed input is skipped and the
// process always exits 0. The C89 reference at
// scripts/stdlib/ref/std_physics/ref.c implements the same protocol.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const phys = @import("std_physics.zig");

var BACKING: [1048576]u8 = undefined;
var LINE: [1024]u8 = undefined;

fn sliceEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isCrosscheck() bool {
    var i: usize = 1;
    while (i < os.argc()) : (i += 1) {
        if (sliceEq(os.argv(i), "--crosscheck")) return true;
    }
    return false;
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

fn nextToken(line: []const u8, pos: *usize) ?[]const u8 {
    var i: usize = pos.*;
    while (i < line.len and isWs(line[i])) : (i += 1) {}
    if (i >= line.len) {
        pos.* = i;
        return null;
    }
    var j: usize = i;
    while (j < line.len and !isWs(line[j])) : (j += 1) {}
    pos.* = j;
    return line[i..j];
}

fn hexDigit(c: u8) ?u32 {
    if (c >= '0' and c <= '9') return @intCast(u32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(u32, c - 'a') + 10;
    if (c >= 'A' and c <= 'F') return @intCast(u32, c - 'A') + 10;
    return null;
}

fn parseHex32(s: []const u8) ?u32 {
    if (s.len == 0 or s.len > 8) return null;
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var d = hexDigit(s[i]) orelse return null;
        v = (v << 4) | d;
    }
    return v;
}

fn f32OfBits(bits: u32) f32 {
    var b: u32 = bits;
    var p: *f32 = @ptrCast(*f32, &b);
    return p.*;
}

fn bitsOfF32(v: f32) u32 {
    var p: *u32 = @ptrCast(*u32, &v);
    return p.*;
}

fn hexTokenF32(line: []const u8, pos: *usize) ?f32 {
    var s = nextToken(line, pos) orelse return null;
    var b = parseHex32(s) orelse return null;
    return f32OfBits(b);
}

fn u32Token(line: []const u8, pos: *usize) ?u32 {
    var s = nextToken(line, pos) orelse return null;
    return parse.parseUint(s);
}

fn u64Token(line: []const u8, pos: *usize) ?u64 {
    var s = nextToken(line, pos) orelse return null;
    return parse.parseUint64(s);
}

fn readLine() ?[]const u8 {
    var opt = stdin.readLine(LINE[0..]) catch return null;
    if (opt) |line| return line;
    return null;
}

fn hexChar(v: u32) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + v);
    return @intCast(u8, @intCast(u32, 'a') + (v - 10));
}

fn writeHex8(v: u32) void {
    var buf: [8]u8 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        var sh: u32 = @intCast(u32, (7 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..8]);
}

fn runScenario(ar: *std.arena.Arena) bool {
    var line = readLine() orelse return false;
    while (line.len == 0) {
        line = readLine() orelse return false;
    }
    var pos: usize = 0;
    var seed = u64Token(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var gx = hexTokenF32(line[0..], &pos) orelse return false;
    var gy = hexTokenF32(line[0..], &pos) orelse return false;
    var gz = hexTokenF32(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var damping = hexTokenF32(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var iterations = u32Token(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var steps = u32Token(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var dt = hexTokenF32(line[0..], &pos) orelse return false;

    line = readLine() orelse return false;
    pos = 0;
    var np = u32Token(line[0..], &pos) orelse return false;
    var nc = u32Token(line[0..], &pos) orelse return false;

    std.arena.reset(ar);
    var w = phys.pbdInit(ar, np, nc, seed) catch return false;
    w.gravity[0] = gx;
    w.gravity[1] = gy;
    w.gravity[2] = gz;
    w.damping = damping;
    w.iterations = @intCast(u8, iterations);

    var i: u32 = 0;
    while (i < np) : (i += 1) {
        line = readLine() orelse return false;
        pos = 0;
        var x = hexTokenF32(line[0..], &pos) orelse return false;
        var y = hexTokenF32(line[0..], &pos) orelse return false;
        var z = hexTokenF32(line[0..], &pos) orelse return false;
        var m = hexTokenF32(line[0..], &pos) orelse return false;
        _ = phys.pbdAddParticle(&w, [3]f32{ x, y, z }, m);
    }
    var j: u32 = 0;
    while (j < nc) : (j += 1) {
        line = readLine() orelse return false;
        pos = 0;
        var a = u32Token(line[0..], &pos) orelse return false;
        var b = u32Token(line[0..], &pos) orelse return false;
        var k = hexTokenF32(line[0..], &pos) orelse return false;
        _ = phys.pbdAddDistance(&w, a, b, k);
    }

    var s: u32 = 0;
    while (s < steps) : (s += 1) phys.pbdStep(&w, dt);

    i = 0;
    while (i < w.particle_count) : (i += 1) {
        var p = w.particles[@intCast(usize, i)];
        writeHex8(bitsOfF32(p.pos[0]));
        std.io.write(" ");
        writeHex8(bitsOfF32(p.pos[1]));
        std.io.write(" ");
        writeHex8(bitsOfF32(p.pos[2]));
        std.io.write("\n");
    }
    return true;
}

fn crossMain() void {
    var ar = std.arena.init(BACKING[0..]);
    while (true) {
        if (!runScenario(&ar)) return;
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("physics cross ok\n");
    }
}
