// stdlib_test/hpa_usage — std_hpa (L5) usage program (R7b pattern).
//
// Builds a small deterministic 24x16 map with 8x8 clusters, runs one
// hpaFind, checks the path endpoints and octile cost, runs the identical query
// again on reset scratch, and checks both results are byte-identical.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0), ending
// `hpa ok`. A mismatch calls @panic.
const std = @import("std");
const hpa = @import("std_hpa.zig");
const pf = @import("std_pathfind.zig");

var MAP_BACK: [1048576]u8 = undefined;
var RUN_BACK: [1048576]u8 = undefined;
var TILES: [384]u8 = undefined;
var OUT: [1024]u32 = undefined;
var JOUT: [1024]u32 = undefined;
var SAVED: [1024]u32 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn idx(w: u32, x: u32, y: u32) usize {
    return @intCast(usize, y) * @intCast(usize, w) + @intCast(usize, x);
}

fn absI32(v: i32) i32 {
    if (v < 0) return -v;
    return v;
}

fn pathCost(out: []const u32, count: u32) u32 {
    var total: u32 = 0;
    var i: u32 = 1;
    while (i < count) : (i += 1) {
        var px: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2]);
        var py: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2 + 1]);
        var cx: i32 = @intCast(i32, out[@intCast(usize, i) * 2]);
        var cy: i32 = @intCast(i32, out[@intCast(usize, i) * 2 + 1]);
        if (absI32(cx - px) + absI32(cy - py) == 2) {
            total += 14;
        } else {
            total += 10;
        }
    }
    return total;
}

pub fn main() void {
    var i: usize = 0;
    while (i < TILES.len) : (i += 1) TILES[i] = 1;
    var y: u32 = 0;
    while (y < 8) : (y += 1) TILES[idx(24, 12, y)] = 0;

    var grid = pf.Grid{ .tiles = TILES[0..], .width = 24, .height = 16 };
    var mar = std.arena.init(MAP_BACK[0..]);
    var map = hpa.hpaBuild(&mar, &grid, 8, 8) catch @panic("hpaBuild");
    ck(map.clusters.len == 6, "cluster count");
    ck(map.node_start[map.node_start.len - 1] == @intCast(u32, map.nodes.len), "node range");
    ck(map.edge_start[map.edge_start.len - 1] == @intCast(u32, map.edges.len), "edge range");

    var run = std.arena.init(RUN_BACK[0..]);
    std.arena.reset(&run);
    var n1 = hpa.hpaFind(&run, &map, &grid, pf.Point{ .x = 9, .y = 3 }, pf.Point{ .x = 14, .y = 3 }, OUT[0..]) catch @panic("hpaFind");
    ck(n1 > 1, "path length");
    ck(OUT[0] == 9 and OUT[1] == 3, "start endpoint");
    ck(OUT[@intCast(usize, n1 - 1) * 2] == 14 and OUT[@intCast(usize, n1 - 1) * 2 + 1] == 3, "goal endpoint");
    var c1 = pathCost(OUT[0..], n1);
    var j: usize = 0;
    while (j < @intCast(usize, n1) * 2) : (j += 1) SAVED[j] = OUT[j];

    std.arena.reset(&run);
    var jn = pf.jpsFind(&run, &grid, pf.Point{ .x = 9, .y = 3 }, pf.Point{ .x = 14, .y = 3 }, JOUT[0..]) catch @panic("jpsFind");
    var jc = pathCost(JOUT[0..], jn);
    ck(c1 == jc, "path cost");

    std.arena.reset(&run);
    var n2 = hpa.hpaFind(&run, &map, &grid, pf.Point{ .x = 9, .y = 3 }, pf.Point{ .x = 14, .y = 3 }, OUT[0..]) catch @panic("hpaFind repeat");
    ck(n2 == n1, "repeat count");
    j = 0;
    while (j < @intCast(usize, n1) * 2) : (j += 1) ck(OUT[j] == SAVED[j], "repeat path");

    std.io.write("hpa_usage\n");
    std.io.write("clusters: ");
    std.io.printInt(@intCast(i32, @intCast(u32, map.clusters.len)));
    std.io.write("\n");
    std.io.write("nodes: ");
    std.io.printInt(@intCast(i32, @intCast(u32, map.nodes.len)));
    std.io.write("\n");
    std.io.write("edges: ");
    std.io.printInt(@intCast(i32, @intCast(u32, map.edges.len)));
    std.io.write("\n");
    std.io.write("cost: ");
    std.io.printInt(@intCast(i32, c1));
    std.io.write("\n");
    std.io.write("repeat: 1\n");
    std.io.write("hpa ok\n");
}
