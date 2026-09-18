// stdlib_file_open_xmod — STDLIB std_file (L3) open GREEN fixture.
//
// Contract (blueprint §3 L3): open(arena, path, mode) FileError!File owns the
// OS handle (CreateFileA on win32, open(2) on POSIX). Read mode opens an
// existing file; ReadWrite creates/opens without truncating.
//
// GREEN (contract): deterministic byte-exact stdout `file open ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

pub fn main() void {
    f.writeAll("t_open.txt", "abc") catch @panic("setup writeAll");
    var file = f.open(&g_arena, "t_open.txt", f.Mode.Read) catch @panic("open read");
    f.close(&file);
    f.remove("t_open.txt") catch {};

    var rw = f.open(&g_arena, "t_open_rw.txt", f.Mode.ReadWrite) catch @panic("open readwrite");
    f.close(&rw);
    f.remove("t_open_rw.txt") catch {};

    io.write("file open ok\n");
}
