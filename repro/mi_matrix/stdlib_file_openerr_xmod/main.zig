// stdlib_file_openerr_xmod — STDLIB std_file (L3) open-failure probe fixture.
//
// Contract (blueprint §3 L3): open(arena, path, mode) is FileError!File. A
// failed POSIX open(2) — here ENOENT from a nonexistent path in Read mode — is
// reported as `FileError.OpenFailed` (win32: CreateFileA returns
// INVALID_HANDLE_VALUE). Only Read mode is asserted: Write/Append/ReadWrite
// create-or-open by design (O_CREAT / OPEN_ALWAYS), so they are not failure
// paths. The error is caught and asserted in-process, so the process exits
// cleanly (rc 0) on the success path.
//
// GREEN (contract): deterministic byte-exact stdout `file openerr ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn openFailed(ar: *arena_mod.Arena, path: []const u8) bool {
    _ = f.open(ar, path, f.Mode.Read) catch |e| {
        if (e == error.OpenFailed) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    // Precondition: the path must not exist (the harness runs from a fresh
    // scratch CWD), so Read mode hits ENOENT rather than opening a file.
    ck(!f.exists("t_openerr_missing.txt"), "setup: path must not exist");

    ck(openFailed(&g_arena, "t_openerr_missing.txt"), "Read missing path -> OpenFailed");

    io.write("file openerr ok\n");
}
