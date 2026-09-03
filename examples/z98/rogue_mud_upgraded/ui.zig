const scenario = @import("lib/scenario.zig");
const sand_mod = @import("lib/sand.zig");
const point_mod = @import("lib/point.zig");
const entity_mod = @import("lib/entity.zig");
const tile_mod = @import("lib/tile.zig");
const std = @import("std");
const std_net = @import("std_net");

@cInclude("zig_runtime.h");

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
                @consoleGotoxy(@intCast(i32, x), @intCast(i32, y));
                @consoleSetColor(@intCast(i32, cur.fg), @intCast(i32, cur.bg));
                @putChar(cur.ch);
                prev_buffer[idx] = cur;
            }
        }
    }
    // Reset color to default after drawing
    @consoleSetColor(@intCast(i32, COLOR_WHITE), @intCast(i32, COLOR_BLACK));
    // Move cursor out of the way
    @consoleGotoxy(0, @intCast(i32, rows));
}

pub fn drawToSocket(sock: i32, rows: usize, cols: usize, cells: []const Cell) void {
    // Clear screen and Move cursor home for telnet
    const clear_home: []const u8 = "\x1b[2J\x1b[H";
    _ = std_net.send(sock, clear_home.ptr, @intCast(i32, clear_home.len));

    var last_fg: u8 = 255;

    var y: usize = 0;
    while (y < rows) : (y += 1) {
        var x: usize = 0;
        while (x < cols) : (x += 1) {
            const cell = cells[y * cols + x];

            if (cell.fg != last_fg) {
                sendColorANSI(sock, cell.fg);
                last_fg = cell.fg;
            }
            const char_buf: [1]u8 = [1]u8{ cell.ch };
            _ = std_net.send(sock, &char_buf[0], 1);
        }
        const nl: []const u8 = "\r\n";
        _ = std_net.send(sock, nl.ptr, 2);
    }
    // Reset color at end
    const reset: []const u8 = "\x1b[0m";
    _ = std_net.send(sock, reset.ptr, @intCast(i32, reset.len));
}

fn sendColorANSI(sock: i32, fg: u8) void {
    const esc: []const u8 = "\x1b[";
    _ = std_net.send(sock, esc.ptr, 2);

    // Z98: switch expression for ANSI codes
    const code: []const u8 = switch (fg & 7) {
        0 => "30", // COLOR_BLACK
        1 => "34", // COLOR_BLUE
        2 => "32", // COLOR_GREEN
        3 => "36", // COLOR_CYAN
        4 => "31", // COLOR_RED
        5 => "35", // COLOR_MAGENTA
        6 => "33", // COLOR_YELLOW
        7 => "37", // COLOR_WHITE
        else => "37",
    };
    _ = std_net.send(sock, code.ptr, 2);

    if ((fg & COLOR_BRIGHT) != 0) {
        const bright: []const u8 = ";1";
        _ = std_net.send(sock, bright.ptr, 2);
    }

    const end: []const u8 = "m";
    _ = std_net.send(sock, end.ptr, 1);
}

pub fn initUI() void { }

pub fn clearScreen() void {
    @consoleClear();
}

pub fn drawStatusBar(dungeon: scenario.Dungeon_t) void {
    const player = dungeon.entities[0];
    std.io.print("Pos: (");
    std.io.printInt(@intCast(i32, player.x));
    std.io.print(", ");
    std.io.printInt(@intCast(i32, player.y));
    std.io.print(") | ");
    printHP(player.hp, player.max_hp);
}

pub fn printHP(hp: i16, max_hp: i16) void {
    std.io.print("HP: ");
    if (hp < max_hp / 3) {
        @consoleSetColor(@intCast(i32, COLOR_RED), @intCast(i32, COLOR_BLACK));
    } else if (hp < max_hp / 2) {
        @consoleSetColor(@intCast(i32, COLOR_YELLOW), @intCast(i32, COLOR_BLACK));
    } else {
        @consoleSetColor(@intCast(i32, COLOR_GREEN), @intCast(i32, COLOR_BLACK));
    }
    std.io.printInt(@intCast(i32, hp));
    std.io.print("/");
    std.io.printInt(@intCast(i32, max_hp));
    @consoleSetColor(@intCast(i32, COLOR_WHITE), @intCast(i32, COLOR_BLACK));
    std.io.print("\n");
}

pub fn lookSurroundings(dungeon: scenario.Dungeon_t) void {
    const player = dungeon.entities[0];
    const px = player.x;
    const py = player.y;

    std.io.print("You are at (");
    std.io.printInt(@intCast(i32, px));
    std.io.print(", ");
    std.io.printInt(@intCast(i32, py));
    std.io.print("). Surroundings:\n");

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
            if (e.typ == .Goblin) {
                std.io.print("To the ");
                std.io.write(dir_str);
                std.io.print(", you see a Goblin!\n");
            } else if (e.typ == .Orc) {
                std.io.print("To the ");
                std.io.write(dir_str);
                std.io.print(", you see an Orc!\n");
            }
            return;
        }
    }

    const idx = @intCast(usize, y) * @intCast(usize, dungeon.width) + @intCast(usize, x);
    switch (dungeon.tiles[idx]) {
        .Wall => {
            std.io.print("To the ");
            std.io.write(dir_str);
            std.io.print(", there is a solid stone wall.\n");
        },
        .Floor => {}, // Floors are boring
        .Door => {
            std.io.print("To the ");
            std.io.write(dir_str);
            std.io.print(", you see a heavy wooden door.\n");
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
