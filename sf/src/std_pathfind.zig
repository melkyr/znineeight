// std_pathfind.zig — Z98 std lib L5: Jump Point Search on an 8-connected grid.
//
// Contract (spec §6.7): alloc arena scratch | errors {NoPath, OutOfMemory} |
// coroutine no. Imports L4 `std_heap` and L1 `std_arena` only.
//
//   Point  { x: u32, y: u32 }
//   Grid   { tiles: []u8, width: u32, height: u32 }  // 0 blocked, 1 walkable
//   jpsFind(arena, grid, start, goal, out) !u32
//
// Movement is 8-connected on a uniform-cell-cost grid: cardinal cost 10,
// diagonal cost 14, heuristic 10*max(dx,dy)+4*min(dx,dy). A diagonal move is
// legal only when both adjacent cardinal cells are walkable (strict no corner
// cutting), using the pruning rules of Harabor & Grastien, "The JPS
// Pathfinding System", SoCS 2012. The jump function is iterative (no
// recursion): for a cardinal direction it scans straight ahead; for a diagonal
// direction it also probes the two cardinal components at each step.
//
// The open set is the existing `std_heap` min-heap, keyed by the composite
// i64 `(f << 32) | (~g & 0xffffffff)`. Since the heap pops the smallest key,
// equal f prefers the larger g (the node closer to the goal). g, parent and
// closed are single arena allocations; the heap grows from the same arena and
// nothing is freed.
//
// `out` is a capacity in u32 slots: jpsFind writes at most out.len/2 complete
// (x,y) pairs in forward order (start and goal included), ignores an odd
// trailing slot, and never overflows. The return value is always the FULL path
// tile count, so the caller detects truncation via `2*return > out.len`.
// Blocked/out-of-bounds start or goal, a zero-sized grid, or an unreachable
// goal return error.NoPath; start==goal walkable returns 1.

const arena_mod = @import("std_arena.zig");
const heap_mod = @import("std_heap.zig");

pub const Point = struct {
    x: u32,
    y: u32,
};

pub const Grid = struct {
    tiles: []u8,
    width: u32,
    height: u32,
};

const INF: u32 = 4294967295;
const PARENT_NONE: u32 = 4294967295;

const Ctx = struct {
    grid: *const Grid,
    g: [*]u32,
    parent: [*]u32,
    closed: [*]u8,
    start: Point,
    goal: Point,
    heap: heap_mod.Heap,
};

fn absI32(v: i32) i32 {
    if (v < 0) return -v;
    return v;
}

fn signI32(v: i32) i32 {
    if (v > 0) return 1;
    if (v < 0) return -1;
    return 0;
}

fn inBounds(ctx: *Ctx, x: i32, y: i32) bool {
    if (x < 0 or y < 0) return false;
    if (x >= @intCast(i32, ctx.grid.width)) return false;
    if (y >= @intCast(i32, ctx.grid.height)) return false;
    return true;
}

fn walkable(ctx: *Ctx, x: i32, y: i32) bool {
    if (!inBounds(ctx, x, y)) return false;
    var w: usize = @intCast(usize, ctx.grid.width);
    var idx: usize = @intCast(usize, y) * w + @intCast(usize, x);
    return ctx.grid.tiles[idx] == 1;
}

fn indexOf(ctx: *Ctx, x: i32, y: i32) usize {
    var w: usize = @intCast(usize, ctx.grid.width);
    return @intCast(usize, y) * w + @intCast(usize, x);
}

fn heuristic(ctx: *Ctx, x: i32, y: i32) u32 {
    var dx: i32 = absI32(@intCast(i32, ctx.goal.x) - x);
    var dy: i32 = absI32(@intCast(i32, ctx.goal.y) - y);
    var mx: i32 = dx;
    if (dy > mx) mx = dy;
    var mn: i32 = dx;
    if (dy < mn) mn = dy;
    return @intCast(u32, 10 * mx + 4 * mn);
}

fn makeKey(f: u32, g: u32) i64 {
    var low: u32 = ~g;
    return (@intCast(i64, f) << 32) | @intCast(i64, low);
}

fn indexPtr(idx: usize) *void {
    return @intToPtr(*void, idx);
}

fn pushNode(ctx: *Ctx, idx: usize, f: u32, g: u32) !void {
    var item = heap_mod.HeapItem{ .key = makeKey(f, g), .value = indexPtr(idx) };
    try heap_mod.heapPush(&ctx.heap, item);
}

// True when the node (x,y), reached from x-d, has a forced neighbor. With
// strict no corner cutting a diagonal move has no forced neighbors at all: the
// two side-diagonal candidates are always dominated by a straight step through
// the predecessor's side cell, and the perpendicular cardinal is reachable
// from the predecessor's side cell. For a cardinal move, a perpendicular cell
// is forced when the cell diagonally behind it (relative to the direction of
// travel) is blocked: the predecessor cannot reach it with an equal-cost
// diagonal step.
fn hasForced(ctx: *Ctx, x: i32, y: i32, dx: i32, dy: i32) bool {
    if (dx != 0 and dy != 0) return false;
    if (dx != 0) {
        var py: i32 = 1;
        while (py >= -1) : (py -= 2) {
            if (walkable(ctx, x, y + py) and !walkable(ctx, x - dx, y + py)) return true;
        }
        return false;
    }
    var px: i32 = 1;
    while (px >= -1) : (px -= 2) {
        if (walkable(ctx, x + px, y) and !walkable(ctx, x + px, y - dy)) return true;
    }
    return false;
}

// Iterative cardinal scan: walk in (dx,dy) until a wall, the goal, or a forced
// neighbor. (dx,dy) is unit and cardinal.
fn jumpCardinal(ctx: *Ctx, x: i32, y: i32, dx: i32, dy: i32) ?Point {
    var cx: i32 = x;
    var cy: i32 = y;
    while (true) {
        cx += dx;
        cy += dy;
        if (!walkable(ctx, cx, cy)) return null;
        if (cx == @intCast(i32, ctx.goal.x) and cy == @intCast(i32, ctx.goal.y)) {
            return Point{ .x = @intCast(u32, cx), .y = @intCast(u32, cy) };
        }
        if (hasForced(ctx, cx, cy, dx, dy)) {
            return Point{ .x = @intCast(u32, cx), .y = @intCast(u32, cy) };
        }
    }
    return null;
}

fn jump(ctx: *Ctx, x: i32, y: i32, dx: i32, dy: i32) ?Point {
    if (dx == 0 or dy == 0) return jumpCardinal(ctx, x, y, dx, dy);
    var cx: i32 = x;
    var cy: i32 = y;
    while (true) {
        var nx: i32 = cx + dx;
        var ny: i32 = cy + dy;
        if (!walkable(ctx, nx, ny)) return null;
        if (!walkable(ctx, nx, cy) or !walkable(ctx, cx, ny)) return null;
        cx = nx;
        cy = ny;
        if (cx == @intCast(i32, ctx.goal.x) and cy == @intCast(i32, ctx.goal.y)) {
            return Point{ .x = @intCast(u32, cx), .y = @intCast(u32, cy) };
        }
        if (jumpCardinal(ctx, cx, cy, dx, 0) != null) {
            return Point{ .x = @intCast(u32, cx), .y = @intCast(u32, cy) };
        }
        if (jumpCardinal(ctx, cx, cy, 0, dy) != null) {
            return Point{ .x = @intCast(u32, cx), .y = @intCast(u32, cy) };
        }
    }
    return null;
}

// Jump from (fx,fy) in (dx,dy); relax the endpoint if it is new or cheaper.
fn relax(ctx: *Ctx, fx: i32, fy: i32, dx: i32, dy: i32) !void {
    var jopt = jump(ctx, fx, fy, dx, dy);
    if (jopt) |jp| {
        var jx: i32 = @intCast(i32, jp.x);
        var jy: i32 = @intCast(i32, jp.y);
        var sx: i32 = absI32(jx - fx);
        var sy: i32 = absI32(jy - fy);
        var steps: i32 = sx;
        if (sy > steps) steps = sy;
        var step_cost: u32 = 10;
        if (dx != 0 and dy != 0) step_cost = 14;
        var fidx: usize = indexOf(ctx, fx, fy);
        var jidx: usize = indexOf(ctx, jx, jy);
        var ng: u32 = ctx.g[fidx] + @intCast(u32, steps) * step_cost;
        if (ctx.closed[jidx] != 0) return;
        if (ng < ctx.g[jidx]) {
            ctx.g[jidx] = ng;
            ctx.parent[jidx] = @intCast(u32, fidx);
            var f: u32 = ng + heuristic(ctx, jx, jy);
            try pushNode(ctx, jidx, f, ng);
        }
    }
}

fn expand(ctx: *Ctx, idx: usize) !void {
    var w: usize = @intCast(usize, ctx.grid.width);
    var x: i32 = @intCast(i32, idx % w);
    var y: i32 = @intCast(i32, idx / w);
    var pidx: u32 = ctx.parent[idx];
    if (pidx == PARENT_NONE) {
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dx != 0 or dy != 0) try relax(ctx, x, y, dx, dy);
            }
        }
        return;
    }
    var px: i32 = @intCast(i32, @intCast(usize, pidx) % w);
    var py: i32 = @intCast(i32, @intCast(usize, pidx) / w);
    var dx: i32 = signI32(x - px);
    var dy: i32 = signI32(y - py);
    if (dx != 0 and dy != 0) {
        try relax(ctx, x, y, dx, dy);
        try relax(ctx, x, y, dx, 0);
        try relax(ctx, x, y, 0, dy);
        return;
    }
    try relax(ctx, x, y, dx, dy);
    if (dx != 0) {
        var py2: i32 = 1;
        while (py2 >= -1) : (py2 -= 2) {
            if (walkable(ctx, x, y + py2) and !walkable(ctx, x - dx, y + py2)) {
                try relax(ctx, x, y, 0, py2);
                if (walkable(ctx, x + dx, y) and walkable(ctx, x + dx, y + py2)) {
                    try relax(ctx, x, y, dx, py2);
                }
            }
        }
    } else {
        var px2: i32 = 1;
        while (px2 >= -1) : (px2 -= 2) {
            if (walkable(ctx, x + px2, y) and !walkable(ctx, x + px2, y - dy)) {
                try relax(ctx, x, y, px2, 0);
                if (walkable(ctx, x, y + dy) and walkable(ctx, x + px2, y + dy)) {
                    try relax(ctx, x, y, px2, dy);
                }
            }
        }
    }
}

pub fn jpsFind(arena: *arena_mod.Arena, grid: *const Grid, start: Point, goal: Point, out: []u32) !u32 {
    if (grid.width == 0 or grid.height == 0) return error.NoPath;
    if (start.x >= grid.width or start.y >= grid.height) return error.NoPath;
    if (goal.x >= grid.width or goal.y >= grid.height) return error.NoPath;
    var w: usize = @intCast(usize, grid.width);
    var n: usize = w * @intCast(usize, grid.height);
    var sidx: usize = @intCast(usize, start.y) * w + @intCast(usize, start.x);
    var gidx: usize = @intCast(usize, goal.y) * w + @intCast(usize, goal.x);
    if (grid.tiles[sidx] != 1 or grid.tiles[gidx] != 1) return error.NoPath;
    if (sidx == gidx) {
        if (out.len >= 2) {
            out[0] = start.x;
            out[1] = start.y;
        }
        return 1;
    }

    var graw = try arena_mod.alloc(arena, n * 4);
    var praw = try arena_mod.alloc(arena, n * 4);
    var craw = try arena_mod.alloc(arena, n);
    var garr: [*]u32 = @ptrCast([*]u32, graw);
    var parr: [*]u32 = @ptrCast([*]u32, praw);
    var carr: [*]u8 = @ptrCast([*]u8, craw);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        garr[i] = INF;
        parr[i] = PARENT_NONE;
        carr[i] = 0;
    }

    var ctx = Ctx{
        .grid = grid,
        .g = garr,
        .parent = parr,
        .closed = carr,
        .start = start,
        .goal = goal,
        .heap = try heap_mod.heapInit(arena, 16),
    };
    garr[sidx] = 0;
    var h0: u32 = heuristic(&ctx, @intCast(i32, start.x), @intCast(i32, start.y));
    try pushNode(&ctx, sidx, h0, 0);

    var found: bool = false;
    while (true) {
        var item_opt = heap_mod.heapPop(&ctx.heap);
        if (item_opt) |item| {
            var idx: usize = @intCast(usize, @ptrToInt(item.value));
            if (carr[idx] == 0) {
                carr[idx] = 1;
                if (idx == gidx) {
                    found = true;
                    break;
                }
                try expand(&ctx, idx);
            }
        } else {
            break;
        }
    }
    if (!found) return error.NoPath;

    var count: u32 = 1;
    var cur: usize = gidx;
    while (cur != sidx) {
        var p: u32 = parr[cur];
        if (p == PARENT_NONE) return error.NoPath;
        var pc: usize = @intCast(usize, p);
        var seg: i32 = absI32(@intCast(i32, cur % w) - @intCast(i32, pc % w));
        var segy: i32 = absI32(@intCast(i32, cur / w) - @intCast(i32, pc / w));
        if (segy > seg) seg = segy;
        count += @intCast(u32, seg);
        cur = pc;
    }

    // Parent links join jump points; expand each straight segment into its
    // individual tiles so `out` is the full tile-by-tile path and `count`
    // matches the number of pairs written when the capacity suffices.
    var traw = try arena_mod.alloc(arena, @intCast(usize, count) * 8);
    var tmp: [*]u32 = @ptrCast([*]u32, traw);
    var wr: u32 = count;
    cur = gidx;
    while (true) {
        wr -= 1;
        tmp[@intCast(usize, wr) * 2] = @intCast(u32, cur % w);
        tmp[@intCast(usize, wr) * 2 + 1] = @intCast(u32, cur / w);
        if (cur == sidx) break;
        var p: u32 = parr[cur];
        var pc: usize = @intCast(usize, p);
        var sx: i32 = signI32(@intCast(i32, cur % w) - @intCast(i32, pc % w));
        var sy: i32 = signI32(@intCast(i32, cur / w) - @intCast(i32, pc / w));
        var seg: i32 = absI32(@intCast(i32, cur % w) - @intCast(i32, pc % w));
        var segy: i32 = absI32(@intCast(i32, cur / w) - @intCast(i32, pc / w));
        if (segy > seg) seg = segy;
        var t: i32 = seg - 1;
        while (t > 0) : (t -= 1) {
            wr -= 1;
            tmp[@intCast(usize, wr) * 2] = @intCast(u32, @intCast(i32, pc % w) + sx * t);
            tmp[@intCast(usize, wr) * 2 + 1] = @intCast(u32, @intCast(i32, pc / w) + sy * t);
        }
        cur = pc;
    }

    var cap: usize = out.len / 2;
    var limit: usize = @intCast(usize, count);
    if (limit > cap) limit = cap;
    var i2: usize = 0;
    while (i2 < limit) : (i2 += 1) {
        out[i2 * 2] = tmp[i2 * 2];
        out[i2 * 2 + 1] = tmp[i2 * 2 + 1];
    }
    return count;
}
