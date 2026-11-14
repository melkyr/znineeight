// stdlib_file_write_xmod — STDLIB std_file (L3) write GREEN fixture.
//
// Contract (blueprint §3 L3): write(f, buf) FileError!usize returns the bytes
// written; it may return fewer than buf.len (callers loop). A small buffer is
// written in full by one call on both targets.
//
// GREEN (contract): deterministic byte-exact stdout `file write ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var file = f.open(&g_arena, "t_write.txt", f.Mode.Write) catch @panic("open");
    var n = f.write(&file, "hello ") catch @panic("write1");
    ck(n == 6, "write1 count");
    n = f.write(&file, "world") catch @panic("write2");
    ck(n == 5, "write2 count");
    f.close(&file);

    var back = f.readAll(&g_arena, "t_write.txt") catch @panic("readAll");
    ck(back.len == 11, "readback length");
    ck(back[0] == 'h', "readback first");
    ck(back[10] == 'd', "readback last");
    f.remove("t_write.txt") catch {};
    io.write("file write ok\n");
}
