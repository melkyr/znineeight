// stdlib_file_remove_xmod — STDLIB std_file (L3) remove GREEN fixture.
//
// Contract (blueprint §3 L3): remove(path) FileError!void unlinks the file
// (unlink on POSIX, DeleteFileA on win32); a subsequent exists() is false.
//
// GREEN (contract): deterministic byte-exact stdout `file remove ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_remove.txt", "x") catch @panic("setup writeAll");
    ck(f.exists("t_remove.txt"), "present before remove");

    f.remove("t_remove.txt") catch @panic("remove");
    ck(!f.exists("t_remove.txt"), "absent after remove");

    io.write("file remove ok\n");
}
