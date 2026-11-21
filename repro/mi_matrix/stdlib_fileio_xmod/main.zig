// stdlib_fileio_xmod — STDLIB std_io file-I/O round-trip GREEN fixture.
//
// std_io.zig's file API (fileOpen/fileWrite/fileRead/fileClose) wraps the
// extended PAL file surface (AMENDMENT 1: zig_pal.c gains a read-mode open +
// pal_file_read). This fixture imports it via a BARE `@import("std")` (lib
// search path binds the canonical <exe>/lib std module), writes a temp file in
// the CURRENT directory, closes it, reopens READ, reads it back, and asserts
// the read-back bytes are byte-identical to what was written.
//
// POSIX run: gcc link set = zig_runtime.c + zig_pal.c + c_exit.c. No cstdio is
// used (the wrappers call pal_file_* externs only). The temp file is left on
// disk after the run — PAL has no delete primitive (documented; runners use a
// scratch CWD so the repo tree is not polluted).
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - optional return `?usize` from fileOpen + `orelse` fallback
//   - optional return `?usize` from std.str.findChar + `orelse` fallback
//   - `for` loop over a []const u8 slice with element payload capture
//   - u32 width (buffer length printed via u32-cast arithmetic)
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   1           write-mode fileOpen returned a valid handle
//   1           read-mode fileOpen returned a valid handle
//   11          bytes read back == len("round trip\n")
//   1           read-back buffer byte-equal to the written content
//   5           findChar(readback, ' ') first index (optional + orelse)
//   1           for-over-slice count of 't' in "round trip\n"
const std = @import("std");

const BAD_FD: usize = @intCast(usize, 0xFFFFFFFF);

fn pb(v: bool) void {
    if (v) {
        std.io.printInt(1);
    } else {
        std.io.printInt(0);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    var fname: []const u8 = "stdlib_io_test.txt";
    var content: []const u8 = "round trip\n";

    var wfd = std.io.fileOpen(fname, true) orelse BAD_FD;
    pb(wfd != BAD_FD);
    std.io.fileWrite(wfd, content);
    std.io.fileClose(wfd);

    var rfd = std.io.fileOpen(fname, false) orelse BAD_FD;
    pb(rfd != BAD_FD);

    var buf: [64]u8 = undefined;
    var got = std.io.fileRead(rfd, buf[0..]);
    std.io.fileClose(rfd);

    std.io.printInt(@intCast(i32, got));
    std.io.writeByte('\n');
    pb(std.str.eql(buf[0..got], content));

    var sp = std.str.findChar(buf[0..got], ' ') orelse 99;
    std.io.printInt(@intCast(i32, sp));
    std.io.writeByte('\n');

    var nt: u32 = 0;
    for (buf[0..got]) |ch| {
        if (ch == 't') nt += 1;
    }
    std.io.printInt(@intCast(i32, nt));
    std.io.writeByte('\n');
}
