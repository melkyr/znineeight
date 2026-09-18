// stdlib_stdin_readerr_xmod — STDLIB std_stdin (L3) read-error mapping fixture.
//
// Contract (blueprint §3 L3): a read failure is reported as `error.Io`.
// `std_file`'s `ReadFailed` is translated at the std_stdin boundary, so it is
// NOT part of `StdinError`; both `readLine` and `readAll` can only yield
// `OutOfMemory` or `Io`. Closing fd 0 makes every subsequent read fail with
// EBADF, which exercises the translation.
//
// GREEN (contract): deterministic byte-exact stdout `stdin readerr ok\n`.
const stdin = @import("std_stdin.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

@cInclude("<unistd.h>");
extern "c" fn close(fd: i32) i32;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn readLineIo(buf: []u8) bool {
    _ = stdin.readLine(buf) catch |e| {
        if (e == error.Io) return true;
        return false;
    };
    return false;
}

fn readAllIo(ar: *arena_mod.Arena) bool {
    _ = stdin.readAll(ar) catch |e| {
        if (e == error.Io) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    // Closed stdin: read(2) returns EBADF -> std_file.ReadFailed -> error.Io.
    _ = close(0);

    var buf: [16]u8 = undefined;
    ck(readLineIo(buf[0..]), "readLine maps a read failure to error.Io");
    ck(readAllIo(&g_arena), "readAll maps a read failure to error.Io");

    io.write("stdin readerr ok\n");
}
