// stdlib_num_cross_xmod — std_num (L5) crosscheck driver.
//
// Default mode (fixture gate): deterministic `num cross ok\n`.
// `--crosscheck` reads one ODE/step line per input and prints one result line,
// each f64 printed as its exact 16-hex-digit IEEE-754 bit pattern:
//   exp <t0> <y0> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
//   osc <t0> <x0> <v0> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
//   vdp <t0> <x0> <v0> <mu> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
// Result: `<t> <y...> <dt>` (final state and the step size returned by the
// last call) or `small` when rk45Step returns error.StepTooSmall. The C89
// reference at scripts/stdlib/ref/std_num/ref.c implements the same protocol.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const num = @import("std_num.zig");

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
    return c == ' ' or c == '\t';
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

fn bitsOf(v: f64) u64 {
    var p: *u64 = @ptrCast(*u64, &v);
    return p.*;
}

fn hexChar(v: u64) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHex16(v: u64) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        var sh: u64 = @intCast(u64, (15 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..16]);
}

fn expRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = -y[0];
}

fn oscRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = y[1];
    out[1] = -y[0];
}

fn vdpRhs(t: f64, y: []const f64, out: []f64) void {
    _ = t;
    out[0] = y[1];
    var one: f64 = 1.0;
    var x2: f64 = y[0] * y[0];
    out[1] = VDP_MU * (one - x2) * y[1] - y[0];
}

var VDP_MU: f64 = 2.0;

fn f64Token(line: []const u8, pos: *usize) ?f64 {
    const s = nextToken(line, pos) orelse return null;
    return parse.parseFloat(s);
}

fn u32Token(line: []const u8, pos: *usize) ?u32 {
    const s = nextToken(line, pos) orelse return null;
    return parse.parseUint(s);
}

fn runOne(kind: []const u8, line: []const u8, pos: *usize) void {
    const t0 = f64Token(line, pos) orelse return;
    const a0 = f64Token(line, pos) orelse return;
    var n: usize = 1;
    var y: [2]f64 = .{0.0, 0.0};
    var dy: [2]f64 = .{0.0, 0.0};
    var f: fn (f64, []const f64, []f64) void = expRhs;
    y[0] = a0;
    if (sliceEq(kind, "osc")) {
        const v0 = f64Token(line, pos) orelse return;
        y[1] = v0;
        n = 2;
        f = oscRhs;
    } else if (sliceEq(kind, "vdp")) {
        const v0 = f64Token(line, pos) orelse return;
        const mu = f64Token(line, pos) orelse return;
        y[1] = v0;
        n = 2;
        VDP_MU = mu;
        f = vdpRhs;
    }
    const dt0 = f64Token(line, pos) orelse return;
    const atol = f64Token(line, pos) orelse return;
    const rtol = f64Token(line, pos) orelse return;
    const mn = f64Token(line, pos) orelse return;
    const mx = f64Token(line, pos) orelse return;
    const max_steps = u32Token(line, pos) orelse return;
    const nsteps = u32Token(line, pos) orelse return;

    f(t0, y[0..n], dy[0..n]);
    var st = num.Rk45State{
        .t = t0,
        .y = y[0..n],
        .dy = dy[0..n],
        .cfg = num.Rk45Config{
            .abs_tol = atol,
            .rel_tol = rtol,
            .min_step = mn,
            .max_step = mx,
            .max_steps = max_steps,
        },
    };
    var dt: f64 = dt0;
    var i: u32 = 0;
    var small: bool = false;
    while (i < nsteps) : (i += 1) {
        num.rk45Step(&st, f, &dt) catch |err| {
            if (err == error.StepTooSmall) small = true;
            break;
        };
    }
    if (small) {
        std.io.write("small\n");
        return;
    }
    writeHex16(bitsOf(st.t));
    var j: usize = 0;
    while (j < n) : (j += 1) {
        std.io.write(" ");
        writeHex16(bitsOf(st.y[j]));
    }
    std.io.write(" ");
    writeHex16(bitsOf(dt));
    std.io.write("\n");
}

fn crossMain() void {
    var buf: [1024]u8 = undefined;
    while (true) {
        const line_opt = stdin.readLine(buf[0..]) catch {
            return;
        };
        if (line_opt) |line| {
            var pos: usize = 0;
            const kind = nextToken(line[0..], &pos) orelse {
                continue;
            };
            if (sliceEq(kind, "exp") or sliceEq(kind, "osc") or sliceEq(kind, "vdp")) {
                runOne(kind, line[0..], &pos);
            }
        } else {
            break;
        }
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("num cross ok\n");
    }
}
