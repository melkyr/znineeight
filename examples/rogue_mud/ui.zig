const scenario = @import("lib/scenario.zig");
const sand_mod = @import("lib/sand.zig");
const point_mod = @import("lib/point.zig");
const entity_mod = @import("lib/entity.zig");
const tile_mod = @import("lib/tile.zig");
const std = @import("../mud_server/std.zig");

extern "c" fn plat_is_windows() bool;
extern "c" fn plat_console_gotoxy(x: i32, y: i32) void;
extern "c" fn plat_console_setcolor(fg: i32, bg: i32) void;
extern "c" fn plat_console_putchar(c: i32) void;

pub const Cell = struct {
    ch: u8,
    fg: u8,
    bg: u8,
};

pub const COLOR_BLACK: u8 = 0;
pub const COLOR_BLUE: u8 = 1;
pub const COLOR_GREEN: u8 = 2;
pub const COLOR_CYAN: u8 = 3;
pub const COLOR_RED: u8 = 4;
pub const COLOR_MAGENTA: u8 = 5;
pub const COLOR_YELLOW: u8 = 6;
pub const COLOR_WHITE: u8 = 7;
pub const COLOR_BRIGHT: u8 = 8;

var prev_buffer: [80 * 50]Cell = undefined;
var dirty: bool = true;

pub fn draw(rows: usize, cols: usize, cells: []const Cell) void {
    if (dirty) {
        var i: usize = 0;
        while (i < @intCast(usize, 80 * 50)) : (i += 1) {
            prev_buffer[i] = Cell{ .ch = @intCast(u8, 0), .fg = @intCast(u8, 0), .bg = @intCast(u8, 0) };
        }
        dirty = false;
    }

    var y: usize = 0;
    while (y < rows) : (y += 1) {
        var x: usize = 0;
        while (x < cols) : (x += 1) {
            const idx = y * cols + x;
            const cur = cells[idx];
            const prev = prev_buffer[idx];

            if (cur.ch != prev.ch or cur.fg != prev.fg or cur.bg != prev.bg) {
                plat_console_gotoxy(@intCast(i32, x), @intCast(i32, y));
                plat_console_setcolor(@intCast(i32, cur.fg), @intCast(i32, cur.bg));
                plat_console_putchar(@intCast(i32, cur.ch));
                prev_buffer[idx] = cur;
            }
        }
    }
    // Reset color to default after drawing
    plat_console_setcolor(@intCast(i32, COLOR_WHITE), @intCast(i32, COLOR_BLACK));
    // Move cursor out of the way
    plat_console_gotoxy(0, @intCast(i32, rows));
}

pub var ansi_reset_val: [4]u8 = [4]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '0'), @intCast(u8, 'm') };
pub var ansi_red_val: [5]u8 = [5]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '3'), @intCast(u8, '1'), @intCast(u8, 'm') };
pub var ansi_green_val: [5]u8 = [5]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '3'), @intCast(u8, '2'), @intCast(u8, 'm') };
pub var ansi_yellow_val: [5]u8 = [5]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '3'), @intCast(u8, '3'), @intCast(u8, 'm') };
pub var ansi_blue_val: [5]u8 = [5]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '3'), @intCast(u8, '4'), @intCast(u8, 'm') };
pub var ansi_cyan_val: [5]u8 = [5]u8{ @intCast(u8, 0x1B), @intCast(u8, '['), @intCast(u8, '3'), @intCast(u8, '6'), @intCast(u8, 'm') };

pub fn getAnsiReset() []u8 { return ansi_reset_val[0..]; }
pub fn getAnsiRed() []u8 { return ansi_red_val[0..]; }
pub fn getAnsiGreen() []u8 { return ansi_green_val[0..]; }
pub fn getAnsiYellow() []u8 { return ansi_yellow_val[0..]; }
pub fn getAnsiBlue() []u8 { return ansi_blue_val[0..]; }
pub fn getAnsiCyan() []u8 { return ansi_cyan_val[0..]; }

pub fn initUI() void { }

pub fn clearScreen() void {
    if (useAnsi()) {
        const clear: []const u8 = "\x1b[2J\x1b[H";
        __bootstrap_print_bytes(@ptrCast([*]u8, clear.ptr), clear.len);
    } else {
        // Fallback for non-ANSI: just print some newlines to push old content up
        __bootstrap_print("\n\n\n\n\n\n\n\n\n\n");
    }
}

pub fn drawStatusBar(dungeon: scenario.Dungeon_t) void {
    const player = dungeon.entities[0];
    __bootstrap_print("Pos: (");
    __bootstrap_print_int(@intCast(i32, player.x));
    __bootstrap_print(", ");
    __bootstrap_print_int(@intCast(i32, player.y));
    __bootstrap_print(") | ");
    printHP(player.hp, player.max_hp);
}

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

pub fn printColor(color: []u8) void {
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
fn __bootstrap_print_bytes(s: [*]u8, len: usize) void {
    __bootstrap_write(@ptrCast(*const u8, s), len);
}

extern "c" fn __bootstrap_print_int(n: i32) void;
extern "c" fn __bootstrap_print_char(c: i32) void;
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
                    __bootstrap_print_bytes(@ptrCast([*]u8, dir_str.ptr), dir_str.len);
                    __bootstrap_print(", you see a Goblin!\n");
                },
                .Orc => {
                    __bootstrap_print("To the ");
                    __bootstrap_print_bytes(@ptrCast([*]u8, dir_str.ptr), dir_str.len);
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
            __bootstrap_print_bytes(@ptrCast([*]u8, dir_str.ptr), dir_str.len);
            __bootstrap_print(", there is a solid stone wall.\n");
        },
        .Floor => {}, // Floors are boring
        .Door => {
            __bootstrap_print("To the ");
            __bootstrap_print_bytes(@ptrCast([*]u8, dir_str.ptr), dir_str.len);
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
