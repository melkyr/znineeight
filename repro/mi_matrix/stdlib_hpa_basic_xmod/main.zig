// stdlib_hpa_basic_xmod — std_hpa (L5) HPA* GREEN fixture.
//
// Checks:
//   - 50 random 64x64 maps (8x8 clusters): every returned path is legal
//     (walkable, 8-adjacent, strict no-corner-cut, exact endpoints) and its
//     octile cost equals jpsFind on the same grid; NoPath agrees too;
//   - entrance coverage: every legal cross-cluster adjacency has the expected
//     transition node and directed edge with cost 10/14, and every node is a
//     transition tile;
//   - a fully blocked cluster contributes no nodes;
//   - 32x32 cost parity with jpsFind;
//   - a same-cluster start/goal whose best route leaves the cluster and
//     re-enters it;
//   - a non-divisible 31x17 grid with 4x3 clipped clusters;
//   - start==goal, blocked/out-of-bounds endpoints, map/grid mismatch, and a
//     zero-sized grid;
//   - `out` truncation / odd trailing slot / full count;
//   - deterministic serialized AbstractMap fields across two builds.
//
// GREEN (contract): byte-exact stdout `expected.txt` (RUNRC=0).

const std = @import("std");
const hpa = @import("std_hpa.zig");
const pf = @import("std_pathfind.zig");

var MAP_BACK: [8388608]u8 = undefined;
var RUN_BACK: [8388608]u8 = undefined;
var TILES: [4096]u8 = undefined;
var OUT: [32768]u32 = undefined;
var JOUT: [32768]u32 = undefined;
var MAP_BACK2: [8388608]u8 = undefined;

const Result = struct {
    ok: bool,
    cost: u32,
    count: u32,
};

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn idx(w: u32, x: u32, y: u32) usize {
    return @intCast(usize, y) * @intCast(usize, w) + @intCast(usize, x);
}

fn fill(tiles: []u8, v: u8) void {
    var i: usize = 0;
    while (i < tiles.len) : (i += 1) tiles[i] = v;
}

fn absI32(v: i32) i32 {
    if (v < 0) return -v;
    return v;
}

fn lcg(state: *u32) u32 {
    state.* = state.* *% 1664525 +% 1013904223;
    return state.*;
}

fn costOf(out: []const u32, count: u32) u32 {
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

fn walkable(grid: *const pf.Grid, x: i32, y: i32) bool {
    if (x < 0 or y < 0) return false;
    if (x >= @intCast(i32, grid.width) or y >= @intCast(i32, grid.height)) return false;
    return grid.tiles[idx(grid.width, @intCast(u32, x), @intCast(u32, y))] == 1;
}

fn pathLegal(grid: *const pf.Grid, out: []const u32, count: u32, sx: u32, sy: u32, gx: u32, gy: u32) bool {
    if (count == 0) return false;
    if (out[0] != sx or out[1] != sy) return false;
    var i: u32 = 1;
    while (i < count) : (i += 1) {
        var px: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2]);
        var py: i32 = @intCast(i32, out[@intCast(usize, i - 1) * 2 + 1]);
        var cx: i32 = @intCast(i32, out[@intCast(usize, i) * 2]);
        var cy: i32 = @intCast(i32, out[@intCast(usize, i) * 2 + 1]);
        var dx: i32 = cx - px;
        var dy: i32 = cy - py;
        if (dx < -1 or dx > 1 or dy < -1 or dy > 1) return false;
        if (dx == 0 and dy == 0) return false;
        if (!walkable(grid, cx, cy)) return false;
        if (dx != 0 and dy != 0) {
            if (!walkable(grid, cx, py) or !walkable(grid, px, cy)) return false;
        }
    }
    var last: usize = @intCast(usize, count - 1) * 2;
    if (out[last] != gx or out[last + 1] != gy) return false;
    return true;
}

fn callHpa(ar: *std.arena.Arena, map: *const hpa.AbstractMap, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) Result {
    var n = hpa.hpaFind(ar, map, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, OUT[0..]) catch |e| {
        if (e == error.NoPath) return Result{ .ok = false, .cost = 0, .count = 0 };
        @panic("hpa unexpected error");
    };
    ck(@intCast(usize, n) * 2 <= OUT.len, "hpa out too small");
    return Result{ .ok = true, .cost = costOf(OUT[0..], n), .count = n };
}

fn callJps(ar: *std.arena.Arena, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) Result {
    var n = pf.jpsFind(ar, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, JOUT[0..]) catch |e| {
        if (e == error.NoPath) return Result{ .ok = false, .cost = 0, .count = 0 };
        @panic("jps unexpected error");
    };
    ck(@intCast(usize, n) * 2 <= JOUT.len, "jps out too small");
    return Result{ .ok = true, .cost = costOf(JOUT[0..], n), .count = n };
}

fn noPathHpa(ar: *std.arena.Arena, map: *const hpa.AbstractMap, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) bool {
    var n = hpa.hpaFind(ar, map, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, OUT[0..]) catch |e| {
        if (e == error.NoPath) return true;
        return false;
    };
    _ = n;
    return false;
}

fn checkPair(mapar: *std.arena.Arena, runar: *std.arena.Arena, map: *const hpa.AbstractMap, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32, what: []const u8) void {
    std.arena.reset(runar);
    var hr = callHpa(runar, map, grid, sx, sy, gx, gy);
    std.arena.reset(runar);
    var jr = callJps(runar, grid, sx, sy, gx, gy);
    ck(hr.ok == jr.ok, what);
    if (!hr.ok) return;
    ck(hr.cost == jr.cost, what);
    ck(pathLegal(grid, OUT[0..], hr.count, sx, sy, gx, gy), what);
    _ = mapar;
}

fn transitionAt(grid: *const pf.Grid, cw: u32, ch: u32, cols: u32, x: u32, y: u32) bool {
    if (grid.tiles[idx(grid.width, x, y)] != 1) return false;
    var cid: u32 = (y / ch) * cols + x / cw;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            var nx: i32 = @intCast(i32, x) + dx;
            var ny: i32 = @intCast(i32, y) + dy;
            if (!walkable(grid, nx, ny)) continue;
            if (dx != 0 and dy != 0) {
                if (!walkable(grid, nx, @intCast(i32, y)) or !walkable(grid, @intCast(i32, x), ny)) continue;
            }
            var ncid: u32 = (@intCast(u32, ny) / ch) * cols + @intCast(u32, nx) / cw;
            if (ncid != cid) return true;
        }
    }
    return false;
}

fn nodeOf(map: *const hpa.AbstractMap, cid: u32, x: u32, y: u32) u32 {
    var n = map.node_start[@intCast(usize, cid)];
    var e = map.node_start[@intCast(usize, cid) + 1];
    while (n < e) : (n += 1) {
        var nd = map.nodes[@intCast(usize, n)];
        if (nd.x == x and nd.y == y) return n;
    }
    return 4294967295;
}

fn edgeCost(map: *const hpa.AbstractMap, n: u32, to: u32) u32 {
    var e = map.edge_start[@intCast(usize, n)];
    var ee = map.edge_start[@intCast(usize, n) + 1];
    while (e < ee) : (e += 1) {
        if (map.edges[@intCast(usize, e)].to == to) return map.edges[@intCast(usize, e)].cost;
    }
    return 4294967295;
}

fn checkEntrances(map: *const hpa.AbstractMap, grid: *const pf.Grid) void {
    ck(map.cluster_w == 8 and map.cluster_h == 8, "entrance cluster size");
    var y: u32 = 0;
    while (y < grid.height) : (y += 1) {
        var x: u32 = 0;
        while (x < grid.width) : (x += 1) {
            if (!transitionAt(grid, 8, 8, map.cluster_cols, x, y)) continue;
            var cid: u32 = (y / 8) * map.cluster_cols + x / 8;
            var node: u32 = nodeOf(map, cid, x, y);
            ck(node != 4294967295, "missing transition node");
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    if (dx == 0 and dy == 0) continue;
                    var nx: i32 = @intCast(i32, x) + dx;
                    var ny: i32 = @intCast(i32, y) + dy;
                    if (!walkable(grid, nx, ny)) continue;
                    if (dx != 0 and dy != 0) {
                        if (!walkable(grid, nx, @intCast(i32, y)) or !walkable(grid, @intCast(i32, x), ny)) continue;
                    }
                    var ncid: u32 = (@intCast(u32, ny) / 8) * map.cluster_cols + @intCast(u32, nx) / 8;
                    if (ncid == cid) continue;
                    var other: u32 = nodeOf(map, ncid, @intCast(u32, nx), @intCast(u32, ny));
                    ck(other != 4294967295, "missing neighbour node");
                    var want: u32 = 10;
                    if (dx != 0 and dy != 0) want = 14;
                    ck(edgeCost(map, node, other) == want, "cross edge cost");
                    ck(edgeCost(map, other, node) == want, "reverse cross edge cost");
                }
            }
        }
    }
    var total: u32 = 0;
    var yy: u32 = 0;
    while (yy < grid.height) : (yy += 1) {
        var xx: u32 = 0;
        while (xx < grid.width) : (xx += 1) {
            if (transitionAt(grid, 8, 8, map.cluster_cols, xx, yy)) total += 1;
        }
    }
    ck(total == @intCast(u32, map.nodes.len), "node count");
    var cid2: u32 = 0;
    while (cid2 < map.cluster_cols * map.cluster_rows) : (cid2 += 1) {
        var n2 = map.node_start[@intCast(usize, cid2)];
        var e2 = map.node_start[@intCast(usize, cid2) + 1];
        while (n2 < e2) : (n2 += 1) {
            var nd = map.nodes[@intCast(usize, n2)];
            ck(nd.cluster == cid2, "node cluster");
            ck(transitionAt(grid, 8, 8, map.cluster_cols, nd.x, nd.y), "node not transition");
        }
    }
}

fn checkRandom() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    var seed: u32 = 12345;
    var mi: u32 = 0;
    while (mi < 50) : (mi += 1) {
        var y: u32 = 0;
        while (y < 64) : (y += 1) {
            var x: u32 = 0;
            while (x < 64) : (x += 1) {
                if ((lcg(&seed) % 100) < 72) {
                    TILES[idx(64, x, y)] = 1;
                } else {
                    TILES[idx(64, x, y)] = 0;
                }
            }
        }
        var grid = pf.Grid{ .tiles = TILES[0..], .width = 64, .height = 64 };
        std.arena.reset(&mapar);
        var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("random build");
        ck(map.node_start[map.node_start.len - 1] == @intCast(u32, map.nodes.len), "random node_start");
        ck(map.edge_start[map.edge_start.len - 1] == @intCast(u32, map.edges.len), "random edge_start");
        var k: u32 = 0;
        while (k < 3) : (k += 1) {
            var sp: u32 = lcg(&seed) % 4096;
            while (grid.tiles[@intCast(usize, sp)] != 1) sp = (sp + 1) % 4096;
            var gp: u32 = lcg(&seed) % 4096;
            while (grid.tiles[@intCast(usize, gp)] != 1) gp = (gp + 1) % 4096;
            checkPair(&mapar, &runar, &map, &grid, sp % 64, sp / 64, gp % 64, gp / 64, "random pair");
        }
    }
    std.io.write("random ok\n");
}

fn checkEntrance() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var seed: u32 = 777;
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            if ((lcg(&seed) % 100) < 75) {
                TILES[idx(64, x, y)] = 1;
            } else {
                TILES[idx(64, x, y)] = 0;
            }
        }
    }
    var grid = pf.Grid{ .tiles = TILES[0..], .width = 64, .height = 64 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("entrance build");
    checkEntrances(&map, &grid);
    std.io.write("entrance ok\n");
}

fn checkBlockedCluster() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    fill(TILES[0..128], 1);
    var x: u32 = 8;
    while (x < 16) : (x += 1) {
        var y: u32 = 0;
        while (y < 8) : (y += 1) TILES[idx(16, x, y)] = 0;
    }
    var grid = pf.Grid{ .tiles = TILES[0..128], .width = 16, .height = 8 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("blocked build");
    ck(map.cluster_cols == 2 and map.cluster_rows == 1, "blocked dims");
    ck(map.node_start[1] == map.node_start[2], "blocked cluster nodes");
    ck(map.nodes.len == 0, "blocked all nodes");
    std.io.write("blocked-cluster ok\n");
}

fn checkParity32() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    var seed: u32 = 4242;
    var mi: u32 = 0;
    while (mi < 6) : (mi += 1) {
        var y: u32 = 0;
        while (y < 32) : (y += 1) {
            var x: u32 = 0;
            while (x < 32) : (x += 1) {
                if ((lcg(&seed) % 100) < 70) {
                    TILES[idx(32, x, y)] = 1;
                } else {
                    TILES[idx(32, x, y)] = 0;
                }
            }
        }
        var grid = pf.Grid{ .tiles = TILES[0..1024], .width = 32, .height = 32 };
        std.arena.reset(&mapar);
        var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("parity build");
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            var sp: u32 = lcg(&seed) % 1024;
            while (grid.tiles[@intCast(usize, sp)] != 1) sp = (sp + 1) % 1024;
            var gp: u32 = lcg(&seed) % 1024;
            while (grid.tiles[@intCast(usize, gp)] != 1) gp = (gp + 1) % 1024;
            checkPair(&mapar, &runar, &map, &grid, sp % 32, sp / 32, gp % 32, gp / 32, "parity32 pair");
        }
    }
    std.io.write("parity32 ok\n");
}

fn checkLeaveReenter() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    fill(TILES[0..384], 1);
    var y: u32 = 0;
    while (y < 8) : (y += 1) TILES[idx(24, 12, y)] = 0;
    var grid = pf.Grid{ .tiles = TILES[0..384], .width = 24, .height = 16 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("reenter build");
    var sx: u32 = 9;
    var sy: u32 = 3;
    var gx: u32 = 14;
    var gy: u32 = 3;
    std.arena.reset(&runar);
    var hr = callHpa(&runar, &map, &grid, sx, sy, gx, gy);
    std.arena.reset(&runar);
    var jr = callJps(&runar, &grid, sx, sy, gx, gy);
    ck(hr.ok and jr.ok, "reenter reachable");
    ck(hr.cost == jr.cost, "reenter cost");
    ck(pathLegal(&grid, OUT[0..], hr.count, sx, sy, gx, gy), "reenter legal");
    var left: bool = false;
    var i: u32 = 0;
    while (i < hr.count) : (i += 1) {
        if (OUT[@intCast(usize, i) * 2 + 1] >= 8) left = true;
    }
    ck(left, "reenter route leaves cluster");
    std.io.write("leave-reenter ok\n");
}

fn checkNonDivisible() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    var seed: u32 = 909;
    var y: u32 = 0;
    while (y < 17) : (y += 1) {
        var x: u32 = 0;
        while (x < 31) : (x += 1) {
            if ((lcg(&seed) % 100) < 70) {
                TILES[idx(31, x, y)] = 1;
            } else {
                TILES[idx(31, x, y)] = 0;
            }
        }
    }
    var grid = pf.Grid{ .tiles = TILES[0..527], .width = 31, .height = 17 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 4, 3) catch @panic("nondiv build");
    ck(map.cluster_cols == 8 and map.cluster_rows == 6, "nondiv dims");
    ck(map.clusters[map.clusters.len - 1].w == 3, "nondiv clipped w");
    ck(map.clusters[map.clusters.len - 1].h == 2, "nondiv clipped h");
    var k: u32 = 0;
    while (k < 10) : (k += 1) {
        var sp: u32 = lcg(&seed) % 527;
        while (grid.tiles[@intCast(usize, sp)] != 1) sp = (sp + 1) % 527;
        var gp: u32 = lcg(&seed) % 527;
        while (grid.tiles[@intCast(usize, gp)] != 1) gp = (gp + 1) % 527;
        checkPair(&mapar, &runar, &map, &grid, sp % 31, sp / 31, gp % 31, gp / 31, "nondiv pair");
    }
    std.io.write("nondiv ok\n");
}

fn checkSpecial() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    fill(TILES[0..1024], 1);
    var grid = pf.Grid{ .tiles = TILES[0..1024], .width = 32, .height = 32 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("special build");

    std.arena.reset(&runar);
    var same = hpa.hpaFind(&runar, &map, &grid, pf.Point{ .x = 5, .y = 5 }, pf.Point{ .x = 5, .y = 5 }, OUT[0..]) catch @panic("same");
    ck(same == 1, "same count");
    ck(OUT[0] == 5 and OUT[1] == 5, "same tile");

    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &map, &grid, 32, 0, 1, 1), "oob start path");
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &map, &grid, 0, 0, 32, 1), "oob goal path");

    TILES[idx(32, 0, 0)] = 0;
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &map, &grid, 0, 0, 1, 1), "blocked start path");
    TILES[idx(32, 0, 0)] = 1;
    TILES[idx(32, 31, 31)] = 0;
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &map, &grid, 0, 0, 31, 31), "blocked goal path");
    TILES[idx(32, 31, 31)] = 1;

    var bad_w = map;
    bad_w.width = 33;
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &bad_w, &grid, 0, 0, 1, 1), "width mismatch path");
    var bad_c = map;
    bad_c.cluster_cols = 5;
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &bad_c, &grid, 0, 0, 1, 1), "cluster mismatch path");

    var ztiles: [1]u8 = undefined;
    ztiles[0] = 1;
    var zgrid = pf.Grid{ .tiles = ztiles[0..0], .width = 0, .height = 0 };
    std.arena.reset(&mapar);
    var zmap = hpa.hpaBuild(&mapar, &zgrid, 8, 8) catch @panic("zero build");
    ck(zmap.clusters.len == 0, "zero clusters");
    ck(zmap.node_start.len == 1 and zmap.node_start[0] == 0, "zero node_start");
    ck(zmap.nodes.len == 0 and zmap.edge_start.len == 1 and zmap.edges.len == 0, "zero nodes/edges");
    std.arena.reset(&runar);
    ck(noPathHpa(&runar, &zmap, &zgrid, 0, 0, 0, 0), "zero grid path");


    std.io.write("special ok\n");
}

fn checkTruncation() void {
    var mapar = std.arena.init(MAP_BACK[0..]);
    var runar = std.arena.init(RUN_BACK[0..]);
    fill(TILES[0..1024], 1);
    var grid = pf.Grid{ .tiles = TILES[0..1024], .width = 32, .height = 32 };
    std.arena.reset(&mapar);
    var map = hpa.hpaBuild(&mapar, &grid, 8, 8) catch @panic("trunc build");
    std.arena.reset(&runar);
    var full = hpa.hpaFind(&runar, &map, &grid, pf.Point{ .x = 0, .y = 0 }, pf.Point{ .x = 31, .y = 0 }, OUT[0..]) catch @panic("trunc full");
    ck(full == 32, "trunc full count");
    ck(pathLegal(&grid, OUT[0..], full, 0, 0, 31, 0), "trunc full legal");

    var i: usize = 0;
    while (i < 11) : (i += 1) OUT[i] = 999;
    std.arena.reset(&runar);
    var n = hpa.hpaFind(&runar, &map, &grid, pf.Point{ .x = 0, .y = 0 }, pf.Point{ .x = 31, .y = 0 }, OUT[0..11]) catch @panic("trunc find");
    ck(n == full, "trunc full return");
    ck(2 * n > 11, "trunc detected");
    ck(OUT[0] == 0 and OUT[1] == 0, "trunc pair 0");
    ck(OUT[2] == 1 and OUT[3] == 0, "trunc pair 1");
    ck(OUT[4] == 2 and OUT[5] == 0, "trunc pair 2");
    ck(OUT[6] == 3 and OUT[7] == 0, "trunc pair 3");
    ck(OUT[8] == 4 and OUT[9] == 0, "trunc pair 4");
    ck(OUT[10] == 999, "trunc odd slot untouched");

    std.arena.reset(&runar);
    var even = hpa.hpaFind(&runar, &map, &grid, pf.Point{ .x = 0, .y = 0 }, pf.Point{ .x = 31, .y = 0 }, OUT[0..10]) catch @panic("trunc even");
    ck(even == full, "trunc even return");
    ck(2 * even > 10, "trunc even detected");
    std.io.write("trunc ok\n");
}

fn compareMaps(a: *const hpa.AbstractMap, b: *const hpa.AbstractMap) void {
    ck(a.width == b.width and a.height == b.height, "det dims");
    ck(a.cluster_w == b.cluster_w and a.cluster_h == b.cluster_h, "det cluster dims");
    ck(a.cluster_cols == b.cluster_cols and a.cluster_rows == b.cluster_rows, "det cluster grid");
    ck(a.clusters.len == b.clusters.len, "det clusters len");
    var i: usize = 0;
    while (i < a.clusters.len) : (i += 1) {
        ck(a.clusters[i].x0 == b.clusters[i].x0 and a.clusters[i].y0 == b.clusters[i].y0, "det cluster pos");
        ck(a.clusters[i].w == b.clusters[i].w and a.clusters[i].h == b.clusters[i].h, "det cluster size");
    }
    ck(a.node_start.len == b.node_start.len and a.nodes.len == b.nodes.len, "det node lens");
    i = 0;
    while (i < a.node_start.len) : (i += 1) ck(a.node_start[i] == b.node_start[i], "det node_start");
    i = 0;
    while (i < a.nodes.len) : (i += 1) {
        ck(a.nodes[i].x == b.nodes[i].x and a.nodes[i].y == b.nodes[i].y, "det node pos");
        ck(a.nodes[i].cluster == b.nodes[i].cluster, "det node cluster");
    }
    ck(a.edge_start.len == b.edge_start.len and a.edges.len == b.edges.len, "det edge lens");
    i = 0;
    while (i < a.edge_start.len) : (i += 1) ck(a.edge_start[i] == b.edge_start[i], "det edge_start");
    i = 0;
    while (i < a.edges.len) : (i += 1) {
        ck(a.edges[i].to == b.edges[i].to and a.edges[i].cost == b.edges[i].cost, "det edge");
    }
}

fn checkDeterminism() void {
    var mar1 = std.arena.init(MAP_BACK[0..]);
    var mar2 = std.arena.init(MAP_BACK2[0..]);
    var seed: u32 = 31337;
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            if ((lcg(&seed) % 100) < 70) {
                TILES[idx(64, x, y)] = 1;
            } else {
                TILES[idx(64, x, y)] = 0;
            }
        }
    }
    var grid = pf.Grid{ .tiles = TILES[0..], .width = 64, .height = 64 };
    std.arena.reset(&mar1);
    var a = hpa.hpaBuild(&mar1, &grid, 8, 8) catch @panic("det build a");
    std.arena.reset(&mar2);
    var b = hpa.hpaBuild(&mar2, &grid, 8, 8) catch @panic("det build b");
    compareMaps(&a, &b);

    var run1 = std.arena.init(RUN_BACK[0..]);
    std.arena.reset(&run1);
    var hr1 = callHpa(&run1, &a, &grid, 1, 1, 62, 62);
    var i: usize = 0;
    if (hr1.ok) {
        while (i < @intCast(usize, hr1.count) * 2) : (i += 1) JOUT[i] = OUT[i];
    }
    std.arena.reset(&run1);
    var hr2 = callHpa(&run1, &b, &grid, 1, 1, 62, 62);
    ck(hr1.ok == hr2.ok, "det query ok");
    if (hr1.ok) {
        ck(hr1.count == hr2.count and hr1.cost == hr2.cost, "det query count");
        i = 0;
        while (i < @intCast(usize, hr1.count) * 2) : (i += 1) ck(OUT[i] == JOUT[i], "det query path");
    }


    std.io.write("determinism ok\n");
}

pub fn main() void {
    checkRandom();
    checkEntrance();
    checkBlockedCluster();
    checkParity32();
    checkLeaveReenter();
    checkNonDivisible();
    checkSpecial();
    checkTruncation();
    checkDeterminism();
    std.io.write("hpa basic ok\n");
}
