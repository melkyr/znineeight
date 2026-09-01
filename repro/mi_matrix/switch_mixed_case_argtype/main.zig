const persist = @import("persist.zig");

var buffer: [512 * 1024]u8 = undefined;

pub fn main() !void {
    var arena = persist.Sand{ .pos = @intCast(usize, 0), .end = @intCast(usize, 0) };
    var dungeon = persist.Dungeon_t{ .width = @intCast(u8, 60), .height = @intCast(u8, 30) };
    var c: i32 = -1;
    var dx: i8 = 0;
    var dy: i8 = 0;
    game_loop: while (true) {
        if (c != -1) switch (c) {
            'k', 'K' => dx = 0,
            'e', 'E' => {},
            'v', 'V' => {
                persist.saveDungeon(&arena, dungeon, "save.dat") catch {};
            },
            else => {},
        }
        break :game_loop;
    }
}
