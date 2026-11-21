// stdlib_file_close_xmod — STDLIB std_file (L3) close GREEN fixture.
//
// Contract (blueprint §3 L3): close(f) releases the owned OS handle. After a
// successful close the file is no longer held open, so it can be renamed.
//
// GREEN (contract): deterministic byte-exact stdout `file close ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_close.txt", "abc") catch @panic("setup writeAll");
    var file = f.open(&g_arena, "t_close.txt", f.Mode.Read) catch @panic("open");
    f.close(&file);

    f.remove("t_close2.txt") catch {};
    f.rename("t_close.txt", "t_close2.txt") catch @panic("rename after close");
    ck(f.exists("t_close2.txt"), "renamed exists");
    ck(!f.exists("t_close.txt"), "original gone");
    f.remove("t_close2.txt") catch {};

    io.write("file close ok\n");
}
