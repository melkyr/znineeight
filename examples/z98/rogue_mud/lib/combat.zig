const scenario = @import("scenario.zig");
const entity_mod = @import("entity.zig");
const point_mod = @import("point.zig");
const pathfinding = @import("pathfinding.zig");
const sand_mod = @import("sand.zig");
const std = @import("std");

pub fn addEntity(dungeon: *scenario.Dungeon_t, typ: entity_mod.EntityType, x: u8, y: u8, hp: i16) void {
    if (dungeon.entity_count >= dungeon.entities.len) return;

    dungeon.entities[dungeon.entity_count] = entity_mod.Entity{
        .typ = typ,
        .x = x,
        .y = y,
        .hp = hp,
        .max_hp = hp,
        .active = true,
    };
    dungeon.entity_count += 1;
}

pub fn moveEntity(dungeon: *scenario.Dungeon_t, entity_idx: usize, dx: i8, dy: i8) void {
    const entity = &dungeon.entities[entity_idx];
    if (!entity.active) return;

    const nx = @intCast(u8, @intCast(i32, entity.x) + @intCast(i32, dx));
    const ny = @intCast(u8, @intCast(i32, entity.y) + @intCast(i32, dy));

    if (nx >= dungeon.width or ny >= dungeon.height) return;

    const idx = @intCast(usize, ny) * @intCast(usize, dungeon.width) + @intCast(usize, nx);

    var is_wall = false;
    switch (dungeon.tiles[idx]) {
        .Wall => is_wall = true,
        else => {},
    }
    if (is_wall) return;

    // Check for collision with other active entities
    var i: usize = 0;
    while (i < dungeon.entity_count) : (i += 1) {
        if (i == entity_idx) continue;
        const other = &dungeon.entities[i];
        if (other.active and other.x == nx and other.y == ny) {
            // Combat!
            resolveCombat(entity, other);
            return;
        }
    }

    entity.x = nx;
    entity.y = ny;
}

fn resolveCombat(attacker: *entity_mod.Entity, defender: *entity_mod.Entity) void {
    // Simple combat: 2 damage
    defender.hp -= 2;
    if (defender.hp <= 0) {
        defender.active = false;
    }
}

pub const NpcArgs = struct {
    dungeon: *scenario.Dungeon_t,
    entity_idx: usize,
    arena: *sand_mod.Sand,
};

fn npcStep(na: *NpcArgs) void {
    const dungeon = na.dungeon;
    const i = na.entity_idx;
    const player_node = dungeon.entities[0];
    const enemy = &dungeon.entities[i];
    if (!enemy.active) return;

    const player_pt = point_mod.Point{ .x = player_node.x, .y = player_node.y };
    const enemy_pt = point_mod.Point{ .x = enemy.x, .y = enemy.y };

    if (pathfinding.findPath(na.arena, dungeon.*, enemy_pt, player_pt)) |path| {
        if (path.len > 0) {
            const next_step = path[0];
            const dx = @intCast(i8, @intCast(i32, next_step.x) - @intCast(i32, enemy.x));
            const dy = @intCast(i8, @intCast(i32, next_step.y) - @intCast(i32, enemy.y));
            moveEntity(dungeon, i, dx, dy);
        }
    } else {
        var dx: i8 = 0;
        var dy: i8 = 0;
        if (enemy.x < player_node.x) dx = 1
        else if (enemy.x > player_node.x) dx = -1;
        if (enemy.y < player_node.y) dy = 1
        else if (enemy.y > player_node.y) dy = -1;
        if (dx != 0) {
            moveEntity(dungeon, i, dx, 0);
        } else if (dy != 0) {
            moveEntity(dungeon, i, 0, dy);
        }
    }
}

// B3 (option a): `@asyncInit` copies an args record POSITIONALLY into the
// coroutine's parameters, so the record's fields ARE the coroutine's params
// (fixtures: `caller(out: *i32)` + `CArgs{ out }`). `npcCoroutine` therefore
// takes the `NpcArgs` pointer directly, and the record is `{ na: *NpcArgs }`.
pub const NpcCoroutineArgs = struct { na: *NpcArgs };

pub fn npcCoroutine(na: *NpcArgs) void {
    while (true) {
        npcStep(na);
        _ = @asyncSuspend(null);
    }
}

pub fn spawnEnemies(ctx: *std.async.Context, sched: *std.async.Scheduler,
    tasks: []*std.async.Task, args: []NpcArgs, recs: []NpcCoroutineArgs,
    dungeon: *scenario.Dungeon_t,
    frame_arena: *sand_mod.Sand, path_arena: *sand_mod.Sand) usize {
    var n: usize = 0;
    var i: usize = 1;
    while (i < dungeon.entity_count and n < tasks.len) : (i += 1) {
        args[n] = NpcArgs{ .dungeon = dungeon, .entity_idx = i, .arena = path_arena };
        recs[n] = NpcCoroutineArgs{ .na = &args[n] };
        const sz = @intCast(usize, @asyncFrameSize(npcCoroutine));
        // S10: root frames come from a PERMANENT arena, never the per-turn
        // temp_arena that sand_reset reclaims.
        const frame = sand_mod.sand_alloc(frame_arena, sz, 8) catch return n;
        tasks[n].frame = @asyncInit(ctx, @ptrCast([*]u8, frame), npcCoroutine, @ptrCast(*const void, &recs[n]));
        tasks[n].ctx = ctx;
        tasks[n].arg = @ptrCast(*void, &recs[n]);
        tasks[n].result = @ptrCast(*void, &recs[n]);
        tasks[n].cancel_requested = false;
        tasks[n].waiting_on = tasks[n];
        tasks[n].has_waiting_on = false;
        _ = std.async.addTask(sched, tasks[n]);
        n += 1;
    }
    return n;
}

pub fn updateEnemies(sched: *std.async.Scheduler) std.async.FrameError!void {
    try std.async.tick(sched);
}

