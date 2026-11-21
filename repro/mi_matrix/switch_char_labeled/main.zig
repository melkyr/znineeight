const std = @import("std");
fn run() i32 {
    var count: i32 = 0;
    var c: u8 = 'a';
    var guard: i32 = 0;
    game_loop: while (true) {
        guard = guard + @intCast(i32, 1);
        if (guard > @intCast(i32, 100)) {
            break :game_loop;
        }
        switch (c) {
            'q' => break :game_loop,
            'a' => count = count + @intCast(i32, 1),
            else => {},
        }
        c = c + @intCast(u8, 1);
    }
    return count;
}
pub fn main() void {
    std.io.printInt(run());
}
