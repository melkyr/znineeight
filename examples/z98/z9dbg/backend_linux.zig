// backend_linux.zig — Linux ptrace process backend for z9dbg (P3-M3).
//
// Implements the backend.zig vtable against ptrace(2) + waitpid(2) on i386.
// It never shells out: the debuggee is forked directly, traced from exec via
// PTRACE_TRACEME, and driven with PEEK/POKETEXT, GETREGS/SETREGS, SINGLESTEP,
// CONT and DETACH. Machine-address resolution (DWARF/ELF) is the upper layer's
// job; this module only moves bytes and reports stops.
//
// Breakpoint lifecycle: the upper layer calls plant(addr) for every machine
// address of a source line. A hit restores the original byte and rewinds EIP.
// continue() performs the classic step-over (single-step the restored
// instruction with the other breakpoints planted) before re-enabling it and
// issuing PTRACE_CONT, so a breakpoint at the current PC does not self-trap.
//
// i386 ptrace ABI: four fixed args (request, pid, addr, data). The C prototype
// is variadic; a fixed-argument extern matches the i386 cdecl call.

const os = @import("std_os");
const backend = @import("backend.zig");

const TRACEME: i32 = 0;
const PEEKTEXT: i32 = 1;
const PEEKDATA: i32 = 2;
const POKEDATA: i32 = 3;
const POKETEXT: i32 = 4;
const CONT: i32 = 7;
const SINGLESTEP: i32 = 9;
const GETREGS: i32 = 12;
const SETREGS: i32 = 13;
const ATTACH: i32 = 16;
const DETACH: i32 = 17;

const SIGTRAP: i32 = 5;

const MAX_BREAKS: usize = 256;

// i386 struct user_regs_struct: 17 x u32, kernel order (spec task brief).
const UserRegs = struct {
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,
    eax: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,
    orig_eax: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    esp: u32,
    ss: u32,
};

const Break = struct {
    addr: u32,
    orig: u8,
    enabled: bool,
};

const State = struct {
    pid: i32,
    alive: bool,
    exited: bool,
    exit_code: i32,
    stepping: bool,
    has_pending: bool,
    pending: backend.StopEvent,
    breaks: [MAX_BREAKS]Break,
    break_n: usize,
};

var g_state: State = undefined;

fn wIfExited(status: i32) bool {
    return (status & 0x7f) == 0;
}

fn wExitStatus(status: i32) i32 {
    return (status & 0xff00) >> 8;
}

fn wIfStopped(status: i32) bool {
    return (status & 0xff) == 0x7f;
}

fn wStopSig(status: i32) i32 {
    return (status & 0xff00) >> 8;
}

fn nullPtr() *void {
    return os.ptraceNull();
}

fn errIsSet() bool {
    return os.errno() != 0;
}

fn peek(text: bool, pid: i32, addr: u32) backend.BackendError!u32 {
    os.clearErrno();
    var req: i32 = PEEKDATA;
    if (text) req = PEEKTEXT;
    var r = os.ptrace(req, pid, @intToPtr(*void, addr), nullPtr());
    if (r == -1 and errIsSet()) return error.ReadFailed;
    return @bitCast(u32, r);
}

fn poke(text: bool, pid: i32, addr: u32, word: u32) backend.BackendError!void {
    os.clearErrno();
    var req: i32 = POKEDATA;
    if (text) req = POKETEXT;
    var r = os.ptrace(req, pid, @intToPtr(*void, addr), @intToPtr(*void, word));
    if (r == -1 and errIsSet()) return error.WriteFailed;
}

fn readBytes(st: *State, addr: u32, dst: []u8) backend.BackendError!void {
    var off: usize = 0;
    while (off < dst.len) {
        var word = try peek(true, st.pid, addr +% @intCast(u32, off));
        var i: usize = 0;
        while (i < 4 and off + i < dst.len) : (i += 1) {
            var shift: u32 = @intCast(u32, i * 8);
            dst[off + i] = @intCast(u8, (word >> shift) & @intCast(u32, 0xff));
        }
        off += 4;
    }
}

fn writeBytes(st: *State, addr: u32, src: []const u8) backend.BackendError!void {
    var off: usize = 0;
    while (off < src.len) {
        var a = addr +% @intCast(u32, off);
        var word = try peek(true, st.pid, a);
        var i: usize = 0;
        while (i < 4 and off + i < src.len) : (i += 1) {
            var shift: u32 = @intCast(u32, i * 8);
            var mask: u32 = @intCast(u32, 0xff) << shift;
            var val: u32 = @intCast(u32, src[off + i]) << shift;
            word = (word & ~mask) | val;
        }
        try poke(true, st.pid, a, word);
        off += 4;
    }
}

fn getRegsRaw(st: *State) backend.BackendError!UserRegs {
    var r: UserRegs = undefined;
    os.clearErrno();
    var rc = os.ptrace(GETREGS, st.pid, nullPtr(), @ptrCast(*void, &r));
    if (rc == -1) return error.RegFailed;
    return r;
}

fn setRegsRaw(st: *State, r: *const UserRegs) backend.BackendError!void {
    os.clearErrno();
    var rc = os.ptrace(SETREGS, st.pid, nullPtr(), @ptrCast(*void, @ptrCast(*const void, r)));
    if (rc == -1) return error.RegFailed;
}

fn findBreak(st: *State, addr: u32) ?usize {
    var i: usize = 0;
    while (i < st.break_n) : (i += 1) {
        if (st.breaks[i].addr == addr) return i;
    }
    return null;
}

fn enableAt(st: *State, addr: u32) backend.BackendError!void {
    var idx = findBreak(st, addr) orelse return;
    if (st.breaks[idx].enabled) return;
    var cc: [1]u8 = undefined;
    cc[0] = @intCast(u8, 0xcc);
    try writeBytes(st, addr, cc[0..1]);
    st.breaks[idx].enabled = true;
}

fn disableAt(st: *State, addr: u32) backend.BackendError!void {
    var idx = findBreak(st, addr) orelse return;
    if (!st.breaks[idx].enabled) return;
    var orig: [1]u8 = undefined;
    orig[0] = st.breaks[idx].orig;
    try writeBytes(st, addr, orig[0..1]);
    st.breaks[idx].enabled = false;
}

fn installAllExcept(st: *State, skip: u32) void {
    var i: usize = 0;
    while (i < st.break_n) : (i += 1) {
        if (st.breaks[i].addr == skip) continue;
        enableAt(st, st.breaks[i].addr) catch {};
    }
}

pub fn plant(state: *void, addr: u32) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    if (findBreak(st, addr) != null) {
        try enableAt(st, addr);
        return;
    }
    if (st.break_n >= MAX_BREAKS) return error.WriteFailed;
    var one: [1]u8 = undefined;
    try readBytes(st, addr, one[0..1]);
    st.breaks[st.break_n] = Break{ .addr = addr, .orig = one[0], .enabled = false };
    st.break_n += 1;
    try enableAt(st, addr);
}

pub fn removeBreak(state: *void, addr: u32) void {
    var st = @ptrCast(*State, state);
    var idx = findBreak(st, addr) orelse return;
    if (st.breaks[idx].enabled) {
        disableAt(st, addr) catch {};
    }
    st.break_n -= 1;
    st.breaks[idx] = st.breaks[st.break_n];
}

pub fn restoreAll(state: *void) void {
    var st = @ptrCast(*State, state);
    var i: usize = 0;
    while (i < st.break_n) : (i += 1) {
        if (st.breaks[i].enabled) {
            disableAt(st, st.breaks[i].addr) catch {};
        }
    }
}

pub fn installAllExceptAddr(state: *void, skip: u32) void {
    var st = @ptrCast(*State, state);
    installAllExcept(st, skip);
}

pub fn isLive(state: *void) bool {
    var st = @ptrCast(*State, state);
    return st.alive and !st.exited;
}

pub fn pidOf(state: *void) i32 {
    var st = @ptrCast(*State, state);
    return st.pid;
}

fn waitRaw(st: *State) backend.BackendError!backend.StopEvent {
    var status: i32 = 0;
    var r = os.waitpid(st.pid, &status, 0);
    if (r < 0) return error.WaitFailed;
    if (wIfExited(status)) {
        st.exited = true;
        st.exit_code = wExitStatus(status);
        st.alive = false;
        return backend.StopEvent{ .reason = backend.STOP_EXITED, .signo = 0, .eip = 0 };
    }
    if (wIfStopped(status)) {
        var signo = wStopSig(status);
        var regs = try getRegsRaw(st);
        if (signo == SIGTRAP) {
            if (regs.eip > 0) {
                var bp_addr = regs.eip - 1;
                if (findBreak(st, bp_addr)) |idx| {
                    if (st.breaks[idx].enabled) {
                        var orig: [1]u8 = undefined;
                        orig[0] = st.breaks[idx].orig;
                        try writeBytes(st, bp_addr, orig[0..1]);
                        st.breaks[idx].enabled = false;
                        regs.eip = bp_addr;
                        try setRegsRaw(st, &regs);
                        st.stepping = false;
                        return backend.StopEvent{ .reason = backend.STOP_BREAKPOINT, .signo = signo, .eip = bp_addr };
                    }
                }
            }
            if (st.stepping) {
                st.stepping = false;
                return backend.StopEvent{ .reason = backend.STOP_SINGLE_STEP, .signo = signo, .eip = regs.eip };
            }
        }
        st.stepping = false;
        return backend.StopEvent{ .reason = backend.STOP_SIGNAL, .signo = signo, .eip = regs.eip };
    }
    return backend.StopEvent{ .reason = backend.STOP_SIGNAL, .signo = 0, .eip = 0 };
}

fn launch(state: *void, exe: []const u8, args: [][]const u8) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    st.pid = 0;
    st.alive = false;
    st.exited = false;
    st.exit_code = 0;
    st.stepping = false;
    st.has_pending = false;
    st.break_n = 0;

    var path_buf: [4096]u8 = undefined;
    if (exe.len == 0 or exe.len >= path_buf.len) return error.LaunchFailed;
    var pi: usize = 0;
    while (pi < exe.len) : (pi += 1) path_buf[pi] = exe[pi];
    path_buf[exe.len] = 0;

    var arg_buf: [16384]u8 = undefined;
    var arg_ptrs: [65][*]const u8 = undefined;
    var used: usize = 0;
    var ai: usize = 0;
    var ac: usize = 0;
    arg_ptrs[0] = @ptrCast([*]const u8, &path_buf[0]);
    ac = 1;
    while (ai < args.len and ac < 64) : (ai += 1) {
        var s = args[ai];
        if (used + s.len + 1 > arg_buf.len) return error.LaunchFailed;
        var sj: usize = 0;
        while (sj < s.len) : (sj += 1) arg_buf[used + sj] = s[sj];
        used += s.len;
        arg_buf[used] = 0;
        used += 1;
        arg_ptrs[ac] = @ptrCast([*]const u8, &arg_buf[used - s.len - 1]);
        ac += 1;
    }
    arg_ptrs[ac] = @ptrCast([*]const u8, @intToPtr(*void, 0));

    var pid = os.fork();
    if (pid < 0) return error.LaunchFailed;
    if (pid == 0) {
        _ = os.ptrace(TRACEME, 0, nullPtr(), nullPtr());
        os.debuggeeStdinNull();
        _ = os.execv(@ptrCast([*]const u8, &path_buf[0]), @ptrCast([*]const [*]const u8, &arg_ptrs[0]));
        os.exit(127);
    }
    st.pid = pid;
    st.alive = true;
    var status: i32 = 0;
    var w = os.waitpid(pid, &status, 0);
    if (w != pid or !wIfStopped(status)) {
        st.alive = false;
        return error.LaunchFailed;
    }
    return;
}

fn waitFn(state: *void) backend.BackendError!backend.StopEvent {
    var st = @ptrCast(*State, state);
    if (st.has_pending) {
        st.has_pending = false;
        return st.pending;
    }
    return waitRaw(st);
}

fn readMemoryFn(state: *void, addr: u32, dst: []u8) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    try readBytes(st, addr, dst);
}

fn writeMemoryFn(state: *void, addr: u32, src: []const u8) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    try writeBytes(st, addr, src);
}

fn getRegsFn(state: *void, regs: *backend.Registers) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    var r = try getRegsRaw(st);
    regs.eax = r.eax;
    regs.ecx = r.ecx;
    regs.edx = r.edx;
    regs.ebx = r.ebx;
    regs.esp = r.esp;
    regs.ebp = r.ebp;
    regs.esi = r.esi;
    regs.edi = r.edi;
    regs.eip = r.eip;
    regs.eflags = r.eflags;
}

fn setRegsFn(state: *void, regs: *const backend.Registers) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    var r = try getRegsRaw(st);
    r.eax = regs.eax;
    r.ecx = regs.ecx;
    r.edx = regs.edx;
    r.ebx = regs.ebx;
    r.esp = regs.esp;
    r.ebp = regs.ebp;
    r.esi = regs.esi;
    r.edi = regs.edi;
    r.eip = regs.eip;
    r.eflags = regs.eflags;
    try setRegsRaw(st, &r);
}

fn singleStepFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    if (!st.alive or st.exited) return error.StepFailed;
    st.stepping = true;
    os.clearErrno();
    var rc = os.ptrace(SINGLESTEP, st.pid, nullPtr(), nullPtr());
    if (rc == -1 and errIsSet()) {
        st.stepping = false;
        return error.StepFailed;
    }
}

fn continueFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    if (!st.alive or st.exited) return error.ContinueFailed;
    // Do not reinsert a breakpoint sitting exactly at the current PC: the
    // upper layer either stepped over it first, or deliberately left it
    // disabled so the original instruction executes on this CONT.
    var regs = try getRegsRaw(st);
    var i: usize = 0;
    while (i < st.break_n) : (i += 1) {
        if (st.breaks[i].addr == regs.eip) continue;
        enableAt(st, st.breaks[i].addr) catch return error.ContinueFailed;
    }
    os.clearErrno();
    var rcont = os.ptrace(CONT, st.pid, nullPtr(), nullPtr());
    if (rcont == -1 and errIsSet()) return error.ContinueFailed;
}

fn detachFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    restoreAll(state);
    if (!st.alive or st.exited) return;
    os.clearErrno();
    var rc = os.ptrace(DETACH, st.pid, nullPtr(), nullPtr());
    st.alive = false;
    if (rc == -1 and errIsSet()) return error.DetachFailed;
}

fn terminateFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    restoreAll(state);
    if (!st.alive or st.exited) return;
    _ = os.kill(st.pid, 9);
    var status: i32 = 0;
    _ = os.waitpid(st.pid, &status, 0);
    st.alive = false;
    st.exited = true;
}

pub fn linuxBackend() backend.Backend {
    return backend.Backend{
        .live = true,
        .state = @ptrCast(*void, &g_state),
        .launch_fn = launch,
        .wait_fn = waitFn,
        .readMemory_fn = readMemoryFn,
        .writeMemory_fn = writeMemoryFn,
        .getRegs_fn = getRegsFn,
        .setRegs_fn = setRegsFn,
        .singleStep_fn = singleStepFn,
        .continue_fn = continueFn,
        .detach_fn = detachFn,
        .terminate_fn = terminateFn,
    };
}
