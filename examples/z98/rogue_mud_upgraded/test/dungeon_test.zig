// test/dungeon_test.zig
const sand_mod = @import("../lib/sand.zig");
const rng_mod = @import("../lib/rng.zig");
const scenario = @import("../lib/scenario.zig");
const std = @import("std");

pub fn main() !void {
    var buffer: [65536]u8 = undefined;
    var arena = sand_mod.sand_init(buffer[0..], true);
    var rng = rng_mod.Random_init(@intCast(u32, 12345));

    std.io.print("Generating dungeon...\n", .{});
    const dungeon = try scenario.generateDungeon(&arena, &rng, @intCast(u8, 40), @intCast(u8, 20));

    std.io.print("Dungeon generated: {}x{}, rooms: {}\n", .{
        dungeon.width,
        dungeon.height,
        dungeon.room_count,
    });

    if (dungeon.width != @intCast(u8, 40)) {
        std.io.print("Error: expected width 40, got {}\n", .{dungeon.width});
        return;
    }

    std.io.print("Dungeon test passed!\n", .{});
}
