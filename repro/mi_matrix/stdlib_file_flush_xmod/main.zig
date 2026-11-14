// stdlib_file_flush_xmod — STDLIB std_file (L3) flush GREEN fixture.
//
// Contract (blueprint §3 L3): flush(f) FileError!void forces buffered OS state
// to disk (fsync on POSIX, FlushFileBuffers on win32).
//
// GREEN (contract): deterministic byte-exact stdout `file flush ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var file = f.open(&g_arena, "t_flush.txt", f.Mode.Write) catch @panic("open");
    var n = f.write(&file, "flush me") catch @panic("write");
    ck(n == 8, "write count");
    f.flush(&file) catch @panic("flush");
    f.close(&file);

    var back = f.readAll(&g_arena, "t_flush.txt") catch @panic("readAll");
    ck(back.len == 8, "readback length");
    ck(back[0] == 'f', "readback first");
    f.remove("t_flush.txt") catch {};
    io.write("file flush ok\n");
}
