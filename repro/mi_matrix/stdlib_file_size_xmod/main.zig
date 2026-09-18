// stdlib_file_size_xmod — STDLIB std_file (L3) size GREEN fixture.
//
// Contract (blueprint §3 L3): size(f) FileError!i64 returns the file length and
// must not disturb the read position.
//
// GREEN (contract): deterministic byte-exact stdout `file size ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_size.txt", "1234567890") catch @panic("setup writeAll");
    var file = f.open(&g_arena, "t_size.txt", f.Mode.Read) catch @panic("open");

    var s = f.size(&file) catch @panic("size1");
    ck(s == 10, "size 10");

    var b: [1]u8 = undefined;
    var n = f.read(&file, b[0..]) catch @panic("read");
    ck(n == 1, "read one");

    s = f.size(&file) catch @panic("size2");
    ck(s == 10, "size stable across read");

    f.close(&file);
    f.remove("t_size.txt") catch {};
    io.write("file size ok\n");
}
