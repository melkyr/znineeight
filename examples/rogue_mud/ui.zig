const scenario = @import("lib/scenario.zig");
const sand_mod = @import("lib/sand.zig");
const point_mod = @import("lib/point.zig");
const entity_mod = @import("lib/entity.zig");
const tile_mod = @import("lib/tile.zig");
const std = @import("../mud_server/std.zig");

extern "c" fn plat_is_windows() bool;

const ansi_reset_val = "\x1b[0m";
const ansi_red_val = "\x1b[31m";
const ansi_green_val = "\x1b[32m";
const ansi_yellow_val = "\x1b[33m";
const ansi_blue_val = "\x1b[34m";
const ansi_cyan_val = "\x1b[36m";

pub fn getAnsiReset() []const u8 { return ansi_reset_val; }
pub fn getAnsiRed() []const u8 { return ansi_red_val; }
pub fn getAnsiGreen() []const u8 { return ansi_green_val; }
pub fn getAnsiYellow() []const u8 { return ansi_yellow_val; }
pub fn getAnsiBlue() []const u8 { return ansi_blue_val; }
pub fn getAnsiCyan() []const u8 { return ansi_cyan_val; }

pub fn initUI() void { }

pub fn printHP(hp: i16, max_hp: i16) void {
    __bootstrap_print("HP: ");
    if (hp < max_hp / 3) {
        printColor(getAnsiRed());
    } else if (hp < max_hp / 2) {
        printColor(getAnsiYellow());
    } else {
        printColor(getAnsiGreen());
    }
    __bootstrap_print_int(@intCast(i32, hp));
    __bootstrap_print("/");
    __bootstrap_print_int(@intCast(i32, max_hp));
    resetColor();
    __bootstrap_print("\n");
}

pub fn useAnsi() bool {
    // On Windows, assume no ANSI support unless we are on a modern terminal (not likely for this stress test target)
    // On Linux/Unix, assume ANSI support.
    return !plat_is_windows();
}

pub fn printColor(color: []const u8) void {
    // Z98 Constraint: string literals and []const u8 might trigger signedness warnings in C89
    // if passed to functions expecting char* (like __bootstrap_write).
    if (useAnsi()) {
        __bootstrap_print_bytes(color.ptr, color.len);
    }
}

pub fn resetColor() void {
    if (useAnsi()) {
        const s = getAnsiReset();
        __bootstrap_print_bytes(s.ptr, s.len);
    }
}

extern "c" fn __bootstrap_write(s: *const u8, len: usize) void;
fn __bootstrap_print_bytes(s: [*]const u8, len: usize) void {
    __bootstrap_write(@ptrCast(*const u8, s), len);
}

extern "c" fn __bootstrap_print_int(n: i32) void;
extern "c" fn __bootstrap_print(s: *const c_char) void;

pub fn lookSurroundings(dungeon: scenario.Dungeon_t) void {
    const player = dungeon.entities[0];
    const px = player.x;
    const py = player.y;

    __bootstrap_print("You are at (");
    __bootstrap_print_int(@intCast(i32, px));
    __bootstrap_print(", ");
    __bootstrap_print_int(@intCast(i32, py));
    __bootstrap_print("). Surroundings:\n");

    var dy: i16 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i16 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx = @intCast(i32, px) + @intCast(i32, dx);
            const ny = @intCast(i32, py) + @intCast(i32, dy);

            if (nx < 0 or nx >= @intCast(i32, dungeon.width) or ny < 0 or ny >= @intCast(i32, dungeon.height)) {
                continue;
            }

            const unx = @intCast(u8, nx);
            const uny = @intCast(u8, ny);

            describeTile(dungeon, unx, uny, dx, dy);
        }
    }
}

fn describeTile(dungeon: scenario.Dungeon_t, x: u8, y: u8, dx: i16, dy: i16) void {
    const dir_str = getDirectionString(dx, dy);

    // Check for entities
    var i: usize = 0;
    while (i < dungeon.entity_count) : (i += 1) {
        const e = dungeon.entities[i];
        if (e.active and e.x == x and e.y == y) {
            // Z98 Constraint: Tagged union comparison (e.typ == .Player) is unstable in zig0.
            // Using switch is the recommended idiomatic workaround for Milestone 11.
            switch (e.typ) {
                .Player => {},
                .Goblin => {
                    __bootstrap_print("To the ");
                    __bootstrap_print_bytes(dir_str.ptr, dir_str.len);
                    __bootstrap_print(", you see a Goblin!\n");
                },
                .Orc => {
                    __bootstrap_print("To the ");
                    __bootstrap_print_bytes(dir_str.ptr, dir_str.len);
                    __bootstrap_print(", you see an Orc!\n");
                },
            }
            return;
        }
    }

    const idx = @intCast(usize, y) * @intCast(usize, dungeon.width) + @intCast(usize, x);
    switch (dungeon.tiles[idx]) {
        .Wall => {
            __bootstrap_print("To the ");
            __bootstrap_print_bytes(dir_str.ptr, dir_str.len);
            __bootstrap_print(", there is a solid stone wall.\n");
        },
        .Floor => {}, // Floors are boring
        .Door => {
            __bootstrap_print("To the ");
            __bootstrap_print_bytes(dir_str.ptr, dir_str.len);
            __bootstrap_print(", you see a heavy wooden door.\n");
        },
    }
}

fn getDirectionString(dx: i16, dy: i16) []const u8 {
    // Z98 switch doesn't support complex tuples well yet, but we can use nested switches or packed values
    // For now, let's keep it simple or use a better structure if possible.
    // Actually, Milestone 11 supports switch expressions.
    const packed_dir = dx + (dy * 3);
    return switch (packed_dir) {
        -3 => "North",
        3 => "South",
        1 => "East",
        -1 => "West",
        -2 => "North-East",
        -4 => "North-West",
        4 => "South-East",
        2 => "South-West",
        else => "Unknown",
    };
}
