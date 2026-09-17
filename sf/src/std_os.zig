// std_os.zig — Z98 std lib L1: process-level information.
//
// Contract (blueprint §3 L1): alloc once (cwd) | errors own set | coroutine no.
// OS specifics live in the std-side PAL std_os_pal.zig (R8); the compiler PAL
// (pal.zig / zig_pal.c) is never touched. Per-OS C prototypes come from the
// authorized std_os_prelude.h (the net_prelude.h analog).
//
// argc/argv (operator ruling 2026-09-17): the user calls initArgs(argc, argv)
// from their main; argc()/argv(i) read the saved values. The compiler is
// untouched — no capture hook in the emitted main wrapper. argv(i) slices
// alias the pointers passed to initArgs; the caller does not free them.

const pal = @import("std_os_pal.zig");
const arena_mod = @import("std_arena.zig");

@cInclude("<std_os_prelude.h>");

// One error set per module (R2). CwdFailed is a failed/oversized OS directory
// query; OutOfMemory is the arena's.
pub const OsError = error{ OutOfMemory, CwdFailed };

// cwd's fixed work buffer, allocated once per call from the caller's arena.
// POSIX PATH_MAX is 4096 on linux; win32 reports an over-long path as the
// required size, surfaced here as CwdFailed.
const CWD_BUF: usize = 4096;

// env's fixed NUL-termination buffer (env takes no arena, so the copy is
// stack-local). Names >= ENV_NAME_MAX are rejected as unset, not truncated.
const ENV_NAME_MAX: usize = 256;

var saved_argc: i32 = 0;
var saved_argv: [*]*const u8 = undefined;

// NOTE: the initArgs parameter names are arg_count/arg_values, not
// argc/argv. A parameter named `argc`/`argv` in this module resolves to the
// module's argc()/argv() functions instead of the parameter (the emitter
// proves it: `zT_2 = zF_..._argc;`), so the public API names cannot be reused
// as parameter names here. The ABI is unchanged.
pub fn initArgs(arg_count: i32, arg_values: [*]*const u8) void {
    saved_argc = arg_count;
    saved_argv = arg_values;
}

pub fn argc() usize {
    return @intCast(usize, saved_argc);
}

pub fn argv(i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, saved_argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

pub fn exit(code: i32) noreturn {
    @exit(code);
    while (true) {}
}

pub fn env(name: []const u8) ?[]const u8 {
    if (name.len >= ENV_NAME_MAX) return null;
    var nbuf: [ENV_NAME_MAX]u8 = undefined;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        nbuf[i] = name[i];
    }
    nbuf[name.len] = 0;
    var raw: ?[*]const u8 = pal.getenv(@ptrCast([*]const u8, &nbuf[0]));
    if (raw) |p| {
        var n: usize = 0;
        while (p[n] != 0) : (n += 1) {}
        return p[0..n];
    }
    return null;
}

pub fn cwd(arena: *arena_mod.Arena) OsError![]u8 {
    const buf: [*]u8 = @ptrCast([*]u8, try arena_mod.alloc(arena, CWD_BUF));
    if (@isWindows()) {
        const n = pal.GetCurrentDirectoryA(@intCast(u32, CWD_BUF), buf);
        if (n == 0) return error.CwdFailed;
        if (@intCast(usize, n) >= CWD_BUF) return error.CwdFailed;
        return buf[0..@intCast(usize, n)];
    } else {
        const r: ?[*]u8 = pal.getcwd(buf, CWD_BUF);
        if (r == null) return error.CwdFailed;
        var n: usize = 0;
        while (buf[n] != 0) : (n += 1) {}
        return buf[0..n];
    }
}
