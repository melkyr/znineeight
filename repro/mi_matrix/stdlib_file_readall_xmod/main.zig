// stdlib_file_readall_xmod — STDLIB std_file (L3) readAll GREEN fixture.
//
// Contract (blueprint §3 L3): readAll(arena, path) FileError![]u8 allocates the
// whole file once from the arena and returns the exact bytes.
//
// GREEN (contract): deterministic byte-exact stdout `file readall ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_readall.txt", "read all bytes") catch @panic("setup writeAll");
    var back = f.readAll(&g_arena, "t_readall.txt") catch @panic("readAll");
    ck(back.len == 14, "readAll length");
    ck(back[0] == 'r', "readAll first");
    ck(back[13] == 's', "readAll last");
    f.remove("t_readall.txt") catch {};
    io.write("file readall ok\n");
}
