// stdlib_pathfind_basic_xmod — std_pathfind (L5) Jump Point Search GREEN
// fixture.
//
// Checks (32x32 unless noted):
//   - open straight line (0,0)->(31,0) is 32 tiles, all on row 0;
//   - a full-height wall with one gap forces the path through the gap;
//   - a goal enclosed by a blocked ring returns error.NoPath;
//   - a blocked corner (8x8) forbids the diagonal squeeze: the path is the
//     no-corner-cut 3-tile route, while opening the corner allows the 2-tile
//     diagonal (strict Harabor & Grastien SoCS 2012 rule);
//   - start==goal returns one tile;
//   - out-of-bounds or blocked start/goal and zero-sized grids return
//     error.NoPath;
//   - an 11-slot `out` (5 pairs + one odd slot) writes exactly 5 complete
//     forward pairs, leaves the odd slot untouched, and still returns the FULL
//     tile count (32) so the caller sees 2*return > out.len.
//
// Every returned path is also checked tile-by-tile: in bounds, walkable,
// 8-connected, and every diagonal step has both adjacent cardinal cells
// walkable.
//
// GREEN (contract): byte-exact stdout `expected.txt` (RUNRC=0).

const std = @import("std");
const pf = @import("std_pathfind.zig");

var BACKING: [262144]u8 = undefined;
var OUT: [2048]u32 = undefined;

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

fn walk(grid: *const pf.Grid, x: i32, y: i32) bool {
    if (x < 0 or y < 0) return false;
    if (x >= @intCast(i32, grid.width) or y >= @intCast(i32, grid.height)) return false;
    return grid.tiles[idx(grid.width, @intCast(u32, x), @intCast(u32, y))] == 1;
}

fn find(ar: *std.arena.Arena, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32, out: []u32) u32 {
    return pf.jpsFind(ar, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, out) catch |e| {
        _ = e;
        @panic("unexpected NoPath");
    };
}

fn noPath(ar: *std.arena.Arena, grid: *const pf.Grid, sx: u32, sy: u32, gx: u32, gy: u32, out: []u32) bool {
    var n = pf.jpsFind(ar, grid, pf.Point{ .x = sx, .y = sy }, pf.Point{ .x = gx, .y = gy }, out) catch |e| {
        if (e == error.NoPath) return true;
        return false;
    };
    _ = n;
    return false;
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
        if (!walk(grid, cx, cy)) return false;
        if (dx != 0 and dy != 0) {
            if (!walk(grid, cx, py) or !walk(grid, px, cy)) return false;
        }
    }
    var last: usize = @intCast(usize, count - 1) * 2;
    if (out[last] != gx or out[last + 1] != gy) return false;
    return true;
}

fn containsTile(out: []const u32, count: u32, x: u32, y: u32) bool {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (out[@intCast(usize, i) * 2] == x and out[@intCast(usize, i) * 2 + 1] == y) return true;
    }
    return false;
}

fn checkStraight(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    var n = find(ar, &grid, 0, 0, 31, 0, OUT[0..]);
    ck(n == 32, "straight count");
    ck(pathLegal(&grid, OUT[0..], n, 0, 0, 31, 0), "straight legal");
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        ck(OUT[@intCast(usize, i) * 2] == i, "straight x");
        ck(OUT[@intCast(usize, i) * 2 + 1] == 0, "straight y");
    }
    std.io.write("straight ok\n");
}

fn checkGap(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var y: u32 = 0;
    while (y < 32) : (y += 1) {
        if (y != 16) tiles[idx(32, 16, y)] = 0;
    }
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    var n = find(ar, &grid, 0, 0, 31, 31, OUT[0..]);
    ck(n >= 32, "gap count");
    ck(pathLegal(&grid, OUT[0..], n, 0, 0, 31, 31), "gap legal");
    ck(containsTile(OUT[0..], n, 16, 16), "gap through gap");
    std.io.write("gap ok\n");
}

fn checkEnclosed(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var y: u32 = 19;
    while (y <= 21) : (y += 1) {
        var x: u32 = 19;
        while (x <= 21) : (x += 1) {
            if (x != 20 or y != 20) tiles[idx(32, x, y)] = 0;
        }
    }
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    ck(noPath(ar, &grid, 0, 0, 20, 20, OUT[0..]), "enclosed NoPath");
    std.io.write("enclosed ok\n");
}

fn checkCorner(ar: *std.arena.Arena) void {
    var tiles: [64]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 8, .height = 8 };
    tiles[idx(8, 0, 0)] = 0;
    std.arena.reset(ar);
    var n = find(ar, &grid, 0, 1, 1, 0, OUT[0..]);
    ck(n == 3, "corner no-cut count");
    ck(pathLegal(&grid, OUT[0..], n, 0, 1, 1, 0), "corner legal");
    tiles[idx(8, 0, 0)] = 1;
    std.arena.reset(ar);
    var m = find(ar, &grid, 0, 1, 1, 0, OUT[0..]);
    ck(m == 2, "open corner diagonal count");
    ck(pathLegal(&grid, OUT[0..], m, 0, 1, 1, 0), "open corner legal");
    std.io.write("corner ok\n");
}

fn checkSame(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    var n = find(ar, &grid, 5, 5, 5, 5, OUT[0..]);
    ck(n == 1, "same count");
    ck(OUT[0] == 5 and OUT[1] == 5, "same tile");
    std.io.write("same ok\n");
}

fn checkInvalid(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    ck(noPath(ar, &grid, 32, 0, 1, 1, OUT[0..]), "oob start");
    ck(noPath(ar, &grid, 0, 0, 32, 1, OUT[0..]), "oob goal");
    tiles[idx(32, 0, 0)] = 0;
    std.arena.reset(ar);
    ck(noPath(ar, &grid, 0, 0, 1, 1, OUT[0..]), "blocked start");
    tiles[idx(32, 0, 0)] = 1;
    tiles[idx(32, 31, 31)] = 0;
    std.arena.reset(ar);
    ck(noPath(ar, &grid, 0, 0, 31, 31, OUT[0..]), "blocked goal");
    var zero_w = pf.Grid{ .tiles = tiles[0..0], .width = 0, .height = 32 };
    std.arena.reset(ar);
    ck(noPath(ar, &zero_w, 0, 0, 1, 1, OUT[0..]), "zero width");
    var zero_h = pf.Grid{ .tiles = tiles[0..0], .width = 32, .height = 0 };
    std.arena.reset(ar);
    ck(noPath(ar, &zero_h, 0, 0, 1, 1, OUT[0..]), "zero height");
    std.io.write("invalid ok\n");
}

fn checkTrunc(ar: *std.arena.Arena) void {
    var tiles: [1024]u8 = undefined;
    fill(tiles[0..], 1);
    var grid = pf.Grid{ .tiles = tiles[0..], .width = 32, .height = 32 };
    std.arena.reset(ar);
    var i: usize = 0;
    while (i < 11) : (i += 1) OUT[i] = 999;
    var n = find(ar, &grid, 0, 0, 31, 0, OUT[0..11]);
    ck(n == 32, "trunc full count");
    ck(2 * n > 11, "trunc detected");
    ck(OUT[0] == 0 and OUT[1] == 0, "trunc pair 0");
    ck(OUT[2] == 1 and OUT[3] == 0, "trunc pair 1");
    ck(OUT[4] == 2 and OUT[5] == 0, "trunc pair 2");
    ck(OUT[6] == 3 and OUT[7] == 0, "trunc pair 3");
    ck(OUT[8] == 4 and OUT[9] == 0, "trunc pair 4");
    ck(OUT[10] == 999, "trunc odd slot untouched");
    std.arena.reset(ar);
    var m = find(ar, &grid, 0, 0, 31, 0, OUT[0..64]);
    ck(m == 32, "full count");
    ck(2 * m == 64, "full fits");
    ck(pathLegal(&grid, OUT[0..], m, 0, 0, 31, 0), "full legal");
    std.io.write("trunc ok\n");
}

pub fn main() void {
    var ar = std.arena.init(BACKING[0..]);
    checkStraight(&ar);
    checkGap(&ar);
    checkEnclosed(&ar);
    checkCorner(&ar);
    checkSame(&ar);
    checkInvalid(&ar);
    checkTrunc(&ar);
    std.io.write("pathfind basic ok\n");
}
