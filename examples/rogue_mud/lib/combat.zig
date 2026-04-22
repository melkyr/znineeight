const scenario = @import("scenario.zig");
const entity_mod = @import("entity.zig");
const point_mod = @import("point.zig");
const pathfinding = @import("pathfinding.zig");
const sand_mod = @import("sand.zig");

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

pub fn updateEnemies(arena: *sand_mod.Sand, dungeon: *scenario.Dungeon_t) void {
    if (dungeon.entity_count == 0) return;

    // Assume entity 0 is the player
    const player_node = dungeon.entities[0];
    const player_pt = point_mod.Point{ .x = player_node.x, .y = player_node.y };

    var i: usize = 1;
    while (i < dungeon.entity_count) : (i += 1) {
        const enemy = &dungeon.entities[i];
        if (!enemy.active) continue;

        const enemy_pt = point_mod.Point{ .x = enemy.x, .y = enemy.y };

        // Use A* pathfinding
        const path_opt = pathfinding.findPath(arena, dungeon.*, enemy_pt, player_pt);

        if (path_opt) |path| {
            if (path.len > 1) {
                // path[0] is current position, path[1] is next step
                const next_step = path[1];
                const nx_val = @intCast(i32, next_step.x);
                const ex_val = @intCast(i32, enemy.x);
                const ny_val = @intCast(i32, next_step.y);
                const ey_val = @intCast(i32, enemy.y);
                const dx = @intCast(i8, nx_val - ex_val);
                const dy = @intCast(i8, ny_val - ey_val);
                moveEntity(dungeon, i, dx, dy);
            }
        } else {
            // Fallback to simple movement if no path found
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
}
