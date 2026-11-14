// stdlib_hpa_cross_xmod — std_hpa (L5) crosscheck driver.
//
// Default mode (fixture gate): deterministic `hpa cross ok\n`.
//
// `--crosscheck` reads one grid per input:
//   width height cluster_w cluster_h start_x start_y goal_x goal_y
//   <height rows of width bytes, '0' blocked / '1' walkable>
// and prints exactly one line per grid: `ok <octile_cost>` or `nopath`.
// The process always exits 0. Cost is compared with the C89 full-grid A*
// reference and the committed .expected; tile count is not invariant across
// equal-cost paths, so it is not printed.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const pf = @import("std_pathfind.zig");
const hpa = @import("std_hpa.zig");

var BACKING: [8388608]u8 = undefined;
var MAPBACK: [8388608]u8 = undefined;
var HEADER: [256]u8 = undefined;
var ROW: [4096]u8 = undefined;

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

fn u32Token(line: []const u8, pos: *usize) ?u32 {
    const s = nextToken(line, pos) orelse return null;
    return parse.parseUint(s);
}

fn absI32(v: i32) i32 {
    if (v < 0) return -v;
    return v;
}

fn pathCost(out: []const u32, count: u32) u32 {
    var cost: u32 = 0;
    var i: u32 = 1;
    while (i < count) : (i += 1) {
        var px: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2]);
        var py: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2 + 1]);
        var cx: i32 = @intCast(i32, out[@intCast(usize, i) * 2]);
        var cy: i32 = @intCast(i32, out[@intCast(usize, i) * 2 + 1]);
        if (absI32(cx - px) + absI32(cy - py) == 2) {
            cost += 14;
        } else {
            cost += 10;
        }
    }
    return cost;
}

fn runOne(ar: *std.arena.Arena, hdr: []const u8) void {
    var pos: usize = 0;
    const w = u32Token(hdr, &pos) orelse return;
    const h = u32Token(hdr, &pos) orelse return;
    const cw = u32Token(hdr, &pos) orelse return;
    const ch = u32Token(hdr, &pos) orelse return;
    const sx = u32Token(hdr, &pos) orelse return;
    const sy = u32Token(hdr, &pos) orelse return;
    const gx = u32Token(hdr, &pos) orelse return;
    const gy = u32Token(hdr, &pos) orelse return;
    var wu: usize = @intCast(usize, w);
    var n: usize = wu * @intCast(usize, h);
    if (n > 65536) return;

    std.arena.reset(ar);
    var tiles_raw = std.arena.alloc(ar, n) catch return;
    var tiles: []u8 = tiles_raw[0..n];
    var out_raw = std.arena.alloc(ar, n * 16) catch return;
    var out_ptr: [*]u32 = @ptrCast([*]u32, out_raw);
    var out: []u32 = out_ptr[0..(n * 4)];

    var y: usize = 0;
    while (y < @intCast(usize, h)) : (y += 1) {
        const line_opt = stdin.readLine(ROW[0..]) catch return;
        if (line_opt) |line| {
            var x: usize = 0;
            while (x < wu) : (x += 1) {
                if (x < line.len and line[x] == '1') {
                    tiles[y * wu + x] = 1;
                } else {
                    tiles[y * wu + x] = 0;
                }
            }
        } else {
            return;
        }
    }

    var grid = pf.Grid{ .tiles = tiles, .width = w, .height = h };
    var build_ar = std.arena.init(MAPBACK[0..]);
    var map = hpa.hpaBuild(&build_ar, &grid, cw, ch) catch return;
    var count = hpa.hpaFind(ar, &map, &grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, out) catch |e| {
        if (e == error.NoPath) {
            std.io.write("nopath\n");
            return;
        }
        return;
    };
    if (@intCast(usize, count) * 2 > out.len) {
        std.io.write("nopath\n");
        return;
    }
    std.io.write("ok ");
    std.io.printInt(@intCast(i32, pathCost(out, count)));
    std.io.write("\n");
}

fn crossMain() void {
    var ar = std.arena.init(BACKING[0..]);
    while (true) {
        const line_opt = stdin.readLine(HEADER[0..]) catch {
            return;
        };
        if (line_opt) |line| {
            if (line.len > 0) runOne(&ar, line);
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
        std.io.write("hpa cross ok\n");
    }
}
