const sand_mod = @import("lib/sand.zig");
const rng_mod = @import("lib/rng.zig");
const scenario = @import("lib/scenario.zig");
const point_mod = @import("lib/point.zig");
const entity_mod = @import("lib/entity.zig");
const combat_mod = @import("lib/combat.zig");
const tile_mod = @import("lib/tile.zig");
const room_mod = @import("lib/room.zig");
const ui_mod = @import("ui.zig");
const std = @import("../mud_server/std.zig");

// External functions for input
extern "c" fn getchar() i32;
extern "c" fn __bootstrap_print(s: [*]const u8) void;
extern "c" fn __bootstrap_print_int(n: i32) void;

pub fn main() !void {
    ui_mod.initUI();
    var buffer: [1024 * 1024]u8 = undefined;
    var arena = sand_mod.sand_init(buffer[0..], true);
    var rng = rng_mod.Random_init(@intCast(u32, 12345));

    __bootstrap_print("Welcome to Rogue MUD!\n");
    __bootstrap_print("Generating dungeon...\n");

    var dungeon = try scenario.generateDungeon(&arena, &rng, @intCast(u8, 60), @intCast(u8, 30));

    // Place player in the center of the first room
    if (dungeon.room_count > 0) {
        const first_room = dungeon.rooms[0];
        const px = room_mod.Room_centerX(first_room);
        const py = room_mod.Room_centerY(first_room);
        combat_mod.addEntity(&dungeon, entity_mod.EntityType.Player, px, py, @intCast(i16, 20));
    } else {
        __bootstrap_print("Error: No rooms generated!\n");
        return;
    }

    // Add some enemies
    var i: usize = 1;
    while (i < @intCast(usize, dungeon.room_count)) : (i += 1) {
        const room = dungeon.rooms[i];
        const ex = room_mod.Room_centerX(room);
        const ey = room_mod.Room_centerY(room);
        combat_mod.addEntity(&dungeon, entity_mod.EntityType.Goblin, ex, ey, @intCast(i16, 5));
    }

    __bootstrap_print("Game started! Use WASD to move, Q to quit, L to look.\n");

    while (true) {
        drawDungeon(dungeon);
        const c = getchar();
        if (c == @intCast(i32, 'q') or c == @intCast(i32, 'Q')) break;

        var dx: i8 = @intCast(i8, 0);
        var dy: i8 = @intCast(i8, 0);

        if (c == @intCast(i32, 'w') or c == @intCast(i32, 'W')) dy = @intCast(i8, -1);
        if (c == @intCast(i32, 's') or c == @intCast(i32, 'S')) dy = @intCast(i8, 1);
        if (c == @intCast(i32, 'a') or c == @intCast(i32, 'A')) dx = @intCast(i8, -1);
        if (c == @intCast(i32, 'd') or c == @intCast(i32, 'D')) dx = @intCast(i8, 1);

        if (dx != @intCast(i8, 0) or dy != @intCast(i8, 0)) {
            combat_mod.moveEntity(&dungeon, @intCast(usize, 0), dx, dy);
            combat_mod.updateEnemies(&dungeon);
        }

        if (c == @intCast(i32, 'l') or c == @intCast(i32, 'L')) {
            ui_mod.lookSurroundings(dungeon);
        }

        // Simple turn feedback
        if (!dungeon.entities[0].active) {
            __bootstrap_print("You have died. Game Over.\n");
            break;
        }
    }
}

fn drawDungeon(dungeon: scenario.Dungeon_t) void {
    var y: u8 = 0;
    while (y < dungeon.height) : (y += 1) {
        var x: u8 = 0;
        while (x < dungeon.width) : (x += 1) {
            // Check for entities first
            var found_entity = false;
            var i: usize = 0;
            while (i < dungeon.entity_count) : (i += 1) {
                const e = dungeon.entities[i];
                if (e.active and e.x == x and e.y == y) {
                    switch (e.typ) {
                        .Player => {
                            ui_mod.printColor(ui_mod.getAnsiGreen());
                            __bootstrap_print("@");
                            ui_mod.resetColor();
                        },
                        .Goblin => {
                            ui_mod.printColor(ui_mod.getAnsiRed());
                            __bootstrap_print("g");
                            ui_mod.resetColor();
                        },
                        .Orc => {
                            ui_mod.printColor(ui_mod.getAnsiRed());
                            __bootstrap_print("o");
                            ui_mod.resetColor();
                        },
                    }
                    found_entity = true;
                    break;
                }
            }

            if (!found_entity) {
                const idx = @intCast(usize, y) * @intCast(usize, dungeon.width) + @intCast(usize, x);
                switch (dungeon.tiles[idx]) {
                    .Wall => {
                        ui_mod.printColor(ui_mod.getAnsiBlue());
                        __bootstrap_print("#");
                        ui_mod.resetColor();
                    },
                    .Floor => {
                        __bootstrap_print(".");
                    },
                    .Door => {
                        ui_mod.printColor(ui_mod.getAnsiYellow());
                        __bootstrap_print("+");
                        ui_mod.resetColor();
                    },
                }
            }
        }
        __bootstrap_print("\n");
    }
}
