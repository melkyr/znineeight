const std = @import("std.zig");

extern "c" fn system(s: *const c_char) i32;
extern "c" fn __bootstrap_sleep_ms(ms: u32) void;

const Cell = union(enum) {
    Dead,
    Alive,
};

const WIDTH: usize = 40;
const HEIGHT: usize = 20;

pub fn main() !void {
    var grid: [800]Cell = undefined;
    var next: [800]Cell = undefined;

    const s_grid = grid[0..];
    const s_next = next[0..];

    // Initialize grid
    var i: usize = 0;
    while (i < 800) {
        grid[i] = Cell.Dead;
        i += 1;
    }

    // Set glider pattern
    // (1, 0), (2, 1), (0, 2), (1, 2), (2, 2)
    set(s_grid, 1, 0, Cell{ .Alive = {} });
    set(s_grid, 2, 1, Cell{ .Alive = {} });
    set(s_grid, 0, 2, Cell{ .Alive = {} });
    set(s_grid, 1, 2, Cell{ .Alive = {} });
    set(s_grid, 2, 2, Cell{ .Alive = {} });

    var gen: u32 = 0;
    while (gen < 100) {
        // Clear screen
        _ = system("clear");

        // Print grid
        var y: usize = 0;
        while (y < HEIGHT) {
            var x: usize = 0;
            while (x < WIDTH) {
                const cell = get(s_grid, x, y);
                const ch = switch (cell) {
                    .Dead => ' ',
                    .Alive => '#',
                    else => unreachable,
                };
                std.debug.print("{c}", .{ch});
                x += 1;
            }
            std.debug.print("\n", .{});
            y += 1;
        }
        std.debug.print("Generation: {}\n", .{gen});

        // Compute next generation
        y = 0;
        while (y < HEIGHT) {
            var x: usize = 0;
            while (x < WIDTH) {
                const neighbors = countNeighbors(s_grid, x, y);
                const current = get(s_grid, x, y);

                const next_state: Cell = switch (current) {
                    .Alive => if (neighbors < 2 or neighbors > 3) Cell{ .Dead = {} } else Cell{ .Alive = {} },
                    .Dead => if (neighbors == 3) Cell{ .Alive = {} } else Cell{ .Dead = {} },
                    else => unreachable,
                };
                set(s_next, x, y, next_state);
                x += 1;
            }
            y += 1;
        }

        // Copy next to grid
        i = 0;
        while (i < 800) {
            grid[i] = next[i];
            i += 1;
        }

        gen += 1;
        __bootstrap_sleep_ms(100);
    }
}

fn get(grid: []Cell, x: usize, y: usize) Cell {
    if (x >= WIDTH or y >= HEIGHT) return Cell{ .Dead = {} };
    return grid[y * WIDTH + x];
}

fn set(grid: []Cell, x: usize, y: usize, cell: Cell) void {
    if (x >= WIDTH or y >= HEIGHT) return;
    grid[y * WIDTH + x] = cell;
}

fn countNeighbors(grid: []Cell, x: usize, y: usize) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx = @intCast(i32, x) + dx;
            const ny = @intCast(i32, y) + dy;

            if (nx >= 0 and nx < @intCast(i32, WIDTH) and ny >= 0 and ny < @intCast(i32, HEIGHT)) {
                const cell = get(grid, @intCast(usize, nx), @intCast(usize, ny));
                switch (cell) {
                    .Alive => count += 1,
                    .Dead => {},
                    else => unreachable,
                }
            }
        }
    }
    return count;
}
