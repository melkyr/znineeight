// stdlib_file_mtime_xmod — STDLIB std_file (L3) mtime GREEN fixture.
//
// Contract (spec 2026-10-08 §7, M2 amendment lift): mtime(path) FileError!i64
// returns the file's modification time in seconds since the Unix epoch
// (POSIX stat(2) reading st_mtime at the probed ABI offset; win32
// GetFileAttributesExA + FILETIME conversion). A missing/un-statable path is
// OpenFailed, matching open()'s error granularity.
//
// GREEN (contract): deterministic byte-exact stdout `file mtime ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn mtimeFailed(path: []const u8) bool {
    _ = f.mtime(path) catch |e| {
        if (e == error.OpenFailed) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    f.writeAll("t_mtime.txt", "1234567890") catch @panic("setup writeAll");

    var m = f.mtime("t_mtime.txt") catch @panic("mtime");
    ck(m > 0, "mtime positive");

    ck(!f.exists("t_mtime_missing.txt"), "setup: missing path must not exist");
    ck(mtimeFailed("t_mtime_missing.txt"), "missing path -> OpenFailed");

    f.remove("t_mtime.txt") catch {};
    io.write("file mtime ok\n");
}
