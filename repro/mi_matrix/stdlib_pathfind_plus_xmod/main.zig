const std = @import("std");
const pf = @import("std_pathfind.zig");
const vec = @import("vectors_data.zig");

var MAP_BACK: [262144]u8 = undefined;
var RUN_BACK: [1048576]u8 = undefined;
var OUT: [16384]u32 = undefined;

const MASKS = [_]u8{ 1, 2, 4, 8, 16, 32, 64, 128 };

const Result = struct {
    ok: bool,
    cost: u32,
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

fn cost(out: []const u32, count: u32) u32 {
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

fn tileAt(gi: u32, p: u32) u8 {
    var bit: u32 = vec.offsets[@intCast(usize, gi)] + p;
    var byte: u8 = vec.data[@intCast(usize, bit / 8)];
    if ((byte & MASKS[@intCast(usize, bit % 8)]) != 0) return 1;
    return 0;
}

fn decodeGrid(gi: u32, tiles: []u8) pf.Grid {
    var w: u32 = vec.widths[@intCast(usize, gi)];
    var h: u32 = vec.heights[@intCast(usize, gi)];
    var n: u32 = w * h;
    var p: u32 = 0;
    while (p < n) : (p += 1) tiles[@intCast(usize, p)] = tileAt(gi, p);
    return pf.Grid{ .tiles = tiles, .width = w, .height = h };
}

fn callJps(ar: *std.arena.Arena, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) Result {
    var n = pf.jpsFind(ar, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, OUT[0..]) catch |e| {
        if (e == error.NoPath) return Result{ .ok = false, .cost = 0 };
        @panic("jps unexpected error");
    };
    ck(@intCast(usize, n) * 2 <= OUT.len, "jps out too small");
    return Result{ .ok = true, .cost = cost(OUT[0..], n) };
}

fn callPlus(ar: *std.arena.Arena, map: *const pf.JpsPlus, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) Result {
    var n = pf.jpsPlusFind(ar, map, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, OUT[0..]) catch |e| {
        if (e == error.NoPath) return Result{ .ok = false, .cost = 0 };
        @panic("plus unexpected error");
    };
    ck(@intCast(usize, n) * 2 <= OUT.len, "plus out too small");
    return Result{ .ok = true, .cost = cost(OUT[0..], n) };
}

fn checkPair(run: *std.arena.Arena, map: *const pf.JpsPlus, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32, what: []const u8) void {
    std.arena.reset(run);
    var jr = callJps(run, grid, sx, sy, gx, gy);
    std.arena.reset(run);
    var pr = callPlus(run, map, grid, sx, sy, gx, gy);
    ck(jr.ok == pr.ok, what);
    if (jr.ok) ck(jr.cost == pr.cost, what);
}

fn lcg(state: *u32) u32 {
    state.* = state.* *% 1664525 +% 1013904223;
    return state.*;
}

fn walkIndex(grid: *const pf.Grid, v: u32) u32 {
    var n: u32 = grid.width * grid.height;
    if (n == 0) return 0;
    var p: u32 = v % n;
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        if (grid.tiles[@intCast(usize, p)] == 1) return p;
        p += 1;
        if (p == n) p = 0;
    }
    return 0;
}

fn plusNoPath(ar: *std.arena.Arena, map: *const pf.JpsPlus, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32) bool {
    var n = pf.jpsPlusFind(ar, map, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, OUT[0..]) catch |e| {
        if (e == error.NoPath) return true;
        return false;
    };
    _ = n;
    return false;
}

fn checkTiny() void {
    var tiles: [25]u8 = undefined;
    fill(tiles[0..], 1);
    tiles[idx(5, 4, 0)] = 0;
    tiles[idx(5, 3, 2)] = 0;
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 5, .height = 5 };
    var mar = std.arena.init(MAP_BACK[0..]);
    var map = pf.jpsPlusBuild(&mar, &grid) catch @panic("tiny build");
    ck(map.dist.len == 25 * 8, "tiny dist len");
    var neg: usize = idx(5, 2, 0) * 8 + 2;
    ck(map.dist[neg] == -1, "tiny negative wall");
    var pos: usize = idx(5, 3, 1) * 8 + 6;
    ck(map.dist[pos] == 1, "tiny positive jump");
    var wall: usize = idx(5, 3, 2) * 8;
    var d: usize = 0;
    while (d < 8) : (d += 1) ck(map.dist[wall + d] == 0, "tiny blocked cell");
    std.io.write("tiny ok\n");
}

fn checkSpecial() void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    var mar = std.arena.init(MAP_BACK[0..]);
    var run = std.arena.init(RUN_BACK[0..]);
    std.arena.reset(&mar);
    var map = pf.jpsPlusBuild(&mar, &grid) catch @panic("special build");

    std.arena.reset(&run);
    var same = pf.jpsPlusFind(&run, &map, &grid, pf.Point{ .x = 5, .y = 5 }, pf.Point{ .x = 5, .y = 5 }, OUT[0..]) catch @panic("same");
    ck(same == 1, "same count");
    ck(OUT[0] == 5 and OUT[1] == 5, "same tile");

    std.arena.reset(&run);
    ck(plusNoPath(&run, &map, &grid, 32, 0, 1, 1), "oob start");
    std.arena.reset(&run);
    ck(plusNoPath(&run, &map, &grid, 0, 0, 32, 1), "oob goal");
    tiles[idx(32, 0, 0)] = 0;
    std.arena.reset(&run);
    ck(plusNoPath(&run, &map, &grid, 0, 0, 1, 1), "blocked start");
    tiles[idx(32, 0, 0)] = 1;
    tiles[idx(32, 31, 31)] = 0;
    std.arena.reset(&run);
    ck(plusNoPath(&run, &map, &grid, 0, 0, 31, 31), "blocked goal");
    tiles[idx(32, 31, 31)] = 1;

    var bad_w = map;
    bad_w.width = 33;
    std.arena.reset(&run);
    ck(plusNoPath(&run, &bad_w, &grid, 0, 0, 1, 1), "width mismatch");
    var bad_h = map;
    bad_h.height = 33;
    std.arena.reset(&run);
    ck(plusNoPath(&run, &bad_h, &grid, 0, 0, 1, 1), "height mismatch");
    var bad_d = map;
    bad_d.dist = map.dist[0 .. map.dist.len - 1];
    std.arena.reset(&run);
    ck(plusNoPath(&run, &bad_d, &grid, 0, 0, 1, 1), "dist len mismatch");

    var ztiles: [1]u8 = undefined;
    ztiles[0] = 1;
    var zgrid = pf.Grid{ .tiles = ztiles[0..0], .width = 0, .height = 0 };
    std.arena.reset(&mar);
    var zmap = pf.jpsPlusBuild(&mar, &zgrid) catch @panic("zero build");
    std.arena.reset(&run);
    ck(plusNoPath(&run, &zmap, &zgrid, 0, 0, 0, 0), "zero grid");

    var i: usize = 0;
    while (i < 11) : (i += 1) OUT[i] = 999;
    std.arena.reset(&run);
    var trunc = pf.jpsPlusFind(&run, &map, &grid, pf.Point{ .x = 0, .y = 0 }, pf.Point{ .x = 31, .y = 0 }, OUT[0..11]) catch @panic("trunc");
    ck(trunc == 32, "trunc full count");
    ck(2 * trunc > 11, "trunc detected");
    ck(OUT[0] == 0 and OUT[1] == 0, "trunc pair 0");
    ck(OUT[2] == 1 and OUT[3] == 0, "trunc pair 1");
    ck(OUT[4] == 2 and OUT[5] == 0, "trunc pair 2");
    ck(OUT[6] == 3 and OUT[7] == 0, "trunc pair 3");
    ck(OUT[8] == 4 and OUT[9] == 0, "trunc pair 4");
    ck(OUT[10] == 999, "trunc odd slot untouched");
    std.io.write("special ok\n");
}

pub fn main() void {
    checkTiny();
    checkSpecial();

    var mar = std.arena.init(MAP_BACK[0..]);
    var run = std.arena.init(RUN_BACK[0..]);
    var tiles: [4096]u8 = undefined;
    var gi: u32 = 0;
    while (gi < vec.count) : (gi += 1) {
        var grid = decodeGrid(gi, tiles[0..]);
        std.arena.reset(&mar);
        var map = pf.jpsPlusBuild(&mar, &grid) catch @panic("plus build");
        var n: u32 = grid.width * grid.height;
        ck(map.dist.len == @intCast(usize, n) * 8, "map dist len");
        ck(map.width == grid.width and map.height == grid.height, "map dims");

        var sx: u32 = vec.start_x[@intCast(usize, gi)];
        var sy: u32 = vec.start_y[@intCast(usize, gi)];
        var gx: u32 = vec.goal_x[@intCast(usize, gi)];
        var gy: u32 = vec.goal_y[@intCast(usize, gi)];
        checkPair(&run, &map, &grid, sx, sy, gx, gy, "vector case");

        var state: u32 = 1000 + gi;
        var k: u32 = 0;
        while (k < 50) : (k += 1) {
            var a: u32 = lcg(&state);
            var b: u32 = lcg(&state);
            var c: u32 = lcg(&state);
            var d: u32 = lcg(&state);
            var sp: u32 = walkIndex(&grid, a);
            var gp: u32 = walkIndex(&grid, b ^ c ^ d);
            checkPair(&run, &map, &grid, sp % grid.width, sp / grid.width, gp % grid.width, gp / grid.width, "pair case");
        }

        gx = walkIndex(&grid, lcg(&state));
        gy = gx;
        checkPair(&run, &map, &grid, gx % grid.width, gx / grid.width, gy % grid.width, gy / grid.width, "same case");
    }
    std.io.write("pathfind plus ok\n");
}
