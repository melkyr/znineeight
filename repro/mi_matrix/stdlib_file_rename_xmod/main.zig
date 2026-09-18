// stdlib_file_rename_xmod — STDLIB std_file (L3) rename GREEN fixture.
//
// Contract (blueprint §3 L3): rename(old, new) FileError!void moves the path
// (rename on POSIX, MoveFileA on win32); content is preserved.
//
// GREEN (contract): deterministic byte-exact stdout `file rename ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.remove("t_rename_b.txt") catch {};
    f.writeAll("t_rename_a.txt", "data") catch @panic("setup writeAll");

    f.rename("t_rename_a.txt", "t_rename_b.txt") catch @panic("rename");
    ck(!f.exists("t_rename_a.txt"), "old gone");
    ck(f.exists("t_rename_b.txt"), "new present");

    var back = f.readAll(&g_arena, "t_rename_b.txt") catch @panic("readAll");
    ck(back.len == 4, "readback length");
    ck(back[0] == 'd', "readback first");

    f.remove("t_rename_b.txt") catch {};
    io.write("file rename ok\n");
}
