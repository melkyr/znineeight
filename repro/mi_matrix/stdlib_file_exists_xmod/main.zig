// stdlib_file_exists_xmod — STDLIB std_file (L3) exists GREEN fixture.
//
// Contract (blueprint §3 L3): exists(path) bool is a pure probe (no error
// channel): false for an absent path, true for a present regular file, false
// again after removal.
//
// GREEN (contract): deterministic byte-exact stdout `file exists ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.remove("t_exists.txt") catch {};
    ck(!f.exists("t_exists.txt"), "absent before create");

    f.writeAll("t_exists.txt", "x") catch @panic("setup writeAll");
    ck(f.exists("t_exists.txt"), "present after create");

    f.remove("t_exists.txt") catch {};
    ck(!f.exists("t_exists.txt"), "absent after remove");

    io.write("file exists ok\n");
}
