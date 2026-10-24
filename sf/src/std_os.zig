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

// Both saved values are `undefined`-initialized on purpose: a module-scope
// mutable global with a concrete initializer is a runtime-init root
// (main.zig reachability seeding), which would force std_os + std_os_pal +
// std_os_prelude.h into EVERY std program. `undefined` restores use-gating:
// std_os is emitted only when a program actually calls it. initArgs must run
// before argc()/argv(i) (the user calls it from main).
var saved_argc: i32 = undefined;
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
    var raw: ?[*]const u8 = undefined;
    if (@isWindows()) {
        raw = pal.pal_getenv(@ptrCast([*]const u8, &nbuf[0]));
    } else {
        raw = pal.getenv(@ptrCast([*]const u8, &nbuf[0]));
    }
    if (raw) |p| {
        var n: usize = 0;
        while (p[n] != 0) : (n += 1) {}
        return p[0..n];
    }
    return null;
}

// --- POSIX process/debug surface (P3-M3) -----------------------------------
//
// Thin wrappers over the std-side PAL. Win32 returns failure/no-op values; the
// @isWindows() guards keep the POSIX extern calls out of win32 emission (the
// Win32 Debug API bindings are M4). These are deliberately low-level: policy
// (argv construction, ptrace request sequencing, wait-status decoding) lives
// in the debugger backend, not here.

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

pub fn fork() i32 {
    if (@isWindows()) return -1;
    return pal.fork();
}

pub fn execv(path: [*]const u8, arg_values: [*]const [*]const u8) i32 {
    if (@isWindows()) return -1;
    return pal.execv(path, arg_values);
}

pub fn waitpid(pid: i32, status: *i32, options: i32) i32 {
    if (@isWindows()) return -1;
    return pal.waitpid(pid, status, options);
}

pub fn ptrace(request: i32, pid: i32, addr: *void, data: *void) i32 {
    if (@isWindows()) return -1;
    return pal.ptrace(request, pid, addr, data);
}

pub fn getpid() i32 {
    if (@isWindows()) return -1;
    return pal.getpid();
}

pub fn kill(pid: i32, sig: i32) i32 {
    if (@isWindows()) return -1;
    return pal.kill(pid, sig);
}

pub fn errno() i32 {
    if (@isWindows()) return 0;
    return pal.__errno_location().*;
}

pub fn clearErrno() void {
    if (@isWindows()) return;
    pal.__errno_location().* = 0;
}

// Debuggee standard streams: stdin always becomes /dev/null (the debugger
// owns fd 0 for commands). Z9DBG_CHILD_OUT optionally redirects the debuggee's
// stdout+stderr to a path (e.g. /dev/null or a log file); the scripted tier
// uses this to keep debugger output free of program output while still
// exercising continue/dump on programs that print.
pub fn debuggeeStdio() void {
    if (@isWindows()) return;
    const fd = pal.open("/dev/null", @intCast(i32, 0), @intCast(i32, 0));
    if (fd >= 0) {
        _ = pal.dup2(fd, @intCast(i32, 0));
        if (fd != 0) _ = pal.close(fd);
    }
    var out_opt = env("Z9DBG_CHILD_OUT");
    if (out_opt) |path| {
        if (path.len >= 4096) return;
        var nbuf: [4096]u8 = undefined;
        var i: usize = 0;
        while (i < path.len) : (i += 1) nbuf[i] = path[i];
        nbuf[path.len] = 0;
        // O_WRONLY|O_CREAT|O_TRUNC, 0644 (i386 Linux values).
        const ofd = pal.open(@ptrCast([*]const u8, &nbuf[0]), @intCast(i32, 0x241), @intCast(i32, 0x1a4));
        if (ofd >= 0) {
            _ = pal.dup2(ofd, @intCast(i32, 1));
            _ = pal.dup2(ofd, @intCast(i32, 2));
            if (ofd > 2) _ = pal.close(ofd);
        }
    }
}

pub fn ptraceNull() *void {
    return nullVoid();
}

fn nullConst() *const void {
    return @ptrCast(*const void, @intToPtr(*void, 0));
}

// --- Win32 Debug API wrappers (P3-M4) --------------------------------------
//
// Same policy as the POSIX surface: the backend owns argv/event sequencing,
// std_os only guards the extern calls by target. On Linux they return failure
// without referencing the stdcall symbols.
pub fn createProcessA(app: *const void, cmd: [*]u8, startup: *void, info: *void) i32 {
    if (@isWindows()) {
        return pal.CreateProcessA(app, cmd, nullVoid(), nullVoid(), @intCast(i32, 0), @intCast(u32, 0x00000002), nullVoid(), nullConst(), startup, info);
    }
    return 0;
}

pub fn waitForDebugEvent(event: *void, ms: u32) i32 {
    if (@isWindows()) return pal.WaitForDebugEvent(event, ms);
    return 0;
}

pub fn continueDebugEvent(pid: u32, tid: u32, status: u32) i32 {
    if (@isWindows()) return pal.ContinueDebugEvent(pid, tid, status);
    return 0;
}

pub fn getThreadContext(thread: *void, ctx: *void) i32 {
    if (@isWindows()) return pal.GetThreadContext(thread, ctx);
    return 0;
}

pub fn setThreadContext(thread: *void, ctx: *const void) i32 {
    if (@isWindows()) return pal.SetThreadContext(thread, ctx);
    return 0;
}

pub fn readProcessMemory(process: *void, addr: *const void, dst: *void, len: usize) i32 {
    if (@isWindows()) {
        var got: usize = 0;
        return pal.ReadProcessMemory(process, addr, dst, len, &got);
    }
    return 0;
}

pub fn writeProcessMemory(process: *void, addr: *const void, src: *const void, len: usize) i32 {
    if (@isWindows()) {
        var wrote: usize = 0;
        return pal.WriteProcessMemory(process, addr, src, len, &wrote);
    }
    return 0;
}

pub fn flushInstructionCache(process: *void, addr: *const void, len: usize) i32 {
    if (@isWindows()) return pal.FlushInstructionCache(process, addr, len);
    return 0;
}

pub fn terminateProcess(process: *void, code: u32) i32 {
    if (@isWindows()) return pal.TerminateProcess(process, code);
    return 0;
}

pub fn closeHandle(handle: *void) i32 {
    if (@isWindows()) return pal.CloseHandle(handle);
    return 0;
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
