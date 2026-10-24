// backend_win98.zig — Win32 Debug-API process backend for z9dbg (P3-M4).
//
// CreateProcessA(DEBUG_ONLY_THIS_PROCESS) + a 50 ms WaitForDebugEvent pump,
// ContinueDebugEvent, Get/SetThreadContext, Read/WriteProcessMemory and
// FlushInstructionCache — only APIs present on Windows 95/98 (the §15.5 9x
// whitelist). The debuggee is never attached by pid and DebugActiveProcessStop
// is not used: `detach` is terminate-on-quit, as documented.
//
// Raw buffers are deliberate: DEBUG_EVENT is 96 bytes and CONTEXT_i386 is
// 716 bytes on every Win32 build; the documented offsets below avoid depending
// on a struct ABI. The loader's initial breakpoint is skipped (it has no
// planted reach at EIP-1). A planted int3 restores the original byte, rewinds
// EIP to the int3 address, and leaves the event pending for continue().
// Single-step sets EFlags.TF and clears it when the single-step exception
// arrives.

const os = @import("std_os");
const backend = @import("backend.zig");

const DBG_CONTINUE: u32 = 0x00010002;
const EXCEPTION_BREAKPOINT: u32 = 0x80000003;
const EXCEPTION_SINGLE_STEP: u32 = 0x80000004;
const EXCEPTION_ACCESS_VIOLATION: u32 = 0xC0000005;

const CREATE_THREAD_DEBUG_EVENT: u32 = 2;
const CREATE_PROCESS_DEBUG_EVENT: u32 = 3;
const EXIT_THREAD_DEBUG_EVENT: u32 = 4;
const EXIT_PROCESS_DEBUG_EVENT: u32 = 5;
const LOAD_DLL_DEBUG_EVENT: u32 = 6;
const UNLOAD_DLL_DEBUG_EVENT: u32 = 7;
const OUTPUT_DEBUG_STRING_EVENT: u32 = 8;
const RIP_EVENT: u32 = 9;

const CONTEXT_FULL: u32 = 0x00010007;
const TF_BIT: u32 = 0x00000100;

// CONTEXT_i386 offsets.
const CTX_EFLAGS: usize = 192;
const CTX_ESP: usize = 196;
const CTX_EDI: usize = 156;
const CTX_ESI: usize = 160;
const CTX_EBX: usize = 164;
const CTX_EDX: usize = 168;
const CTX_ECX: usize = 172;
const CTX_EAX: usize = 176;
const CTX_EBP: usize = 180;
const CTX_EIP: usize = 184;

const MAX_BREAKS: usize = 65536;

const Break = struct {
    addr: u32,
    orig: u8,
    enabled: bool,
};

const State = struct {
    process: *void,
    thread: *void,
    pid: u32,
    tid: u32,
    image_base: u32,
    alive: bool,
    exited: bool,
    stepping: bool,
    skip_initial: bool,
    breaks: [MAX_BREAKS]Break,
    break_n: usize,
};

var g_state: State = undefined;

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

fn readU32(p: [*]const u8) u32 {
    var b0: u32 = @intCast(u32, p[0]);
    var b1: u32 = @intCast(u32, p[1]);
    var b2: u32 = @intCast(u32, p[2]);
    var b3: u32 = @intCast(u32, p[3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn writeU32(p: [*]u8, v: u32) void {
    p[0] = @intCast(u8, v & @intCast(u32, 0xff));
    p[1] = @intCast(u8, (v >> @intCast(u32, 8)) & @intCast(u32, 0xff));
    p[2] = @intCast(u8, (v >> @intCast(u32, 16)) & @intCast(u32, 0xff));
    p[3] = @intCast(u8, v >> @intCast(u32, 24));
}

fn continueEvent(st: *State) backend.BackendError!void {
    if (os.continueDebugEvent(st.pid, st.tid, DBG_CONTINUE) == 0) return error.ContinueFailed;
}

fn getRegsRaw(st: *State, regs: *backend.Registers) backend.BackendError!void {
    var ctx: [716]u8 = undefined;
    var i: usize = 0;
    while (i < 716) : (i += 1) ctx[i] = 0;
    writeU32(@ptrCast([*]u8, &ctx[0]), CONTEXT_FULL);
    if (os.getThreadContext(st.thread, @ptrCast(*void, &ctx[0])) == 0) return error.RegFailed;
    regs.eax = readU32(@ptrCast([*]const u8, &ctx[CTX_EAX]));
    regs.ecx = readU32(@ptrCast([*]const u8, &ctx[CTX_ECX]));
    regs.edx = readU32(@ptrCast([*]const u8, &ctx[CTX_EDX]));
    regs.ebx = readU32(@ptrCast([*]const u8, &ctx[CTX_EBX]));
    regs.esp = readU32(@ptrCast([*]const u8, &ctx[CTX_ESP]));
    regs.ebp = readU32(@ptrCast([*]const u8, &ctx[CTX_EBP]));
    regs.esi = readU32(@ptrCast([*]const u8, &ctx[CTX_ESI]));
    regs.edi = readU32(@ptrCast([*]const u8, &ctx[CTX_EDI]));
    regs.eip = readU32(@ptrCast([*]const u8, &ctx[CTX_EIP]));
    regs.eflags = readU32(@ptrCast([*]const u8, &ctx[CTX_EFLAGS]));
}

fn setRegsRaw(st: *State, regs: *const backend.Registers) backend.BackendError!void {
    var ctx: [716]u8 = undefined;
    var i: usize = 0;
    while (i < 716) : (i += 1) ctx[i] = 0;
    writeU32(@ptrCast([*]u8, &ctx[0]), CONTEXT_FULL);
    if (os.getThreadContext(st.thread, @ptrCast(*void, &ctx[0])) == 0) return error.RegFailed;
    writeU32(@ptrCast([*]u8, &ctx[CTX_EAX]), regs.eax);
    writeU32(@ptrCast([*]u8, &ctx[CTX_ECX]), regs.ecx);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EDX]), regs.edx);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EBX]), regs.ebx);
    writeU32(@ptrCast([*]u8, &ctx[CTX_ESP]), regs.esp);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EBP]), regs.ebp);
    writeU32(@ptrCast([*]u8, &ctx[CTX_ESI]), regs.esi);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EDI]), regs.edi);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EIP]), regs.eip);
    writeU32(@ptrCast([*]u8, &ctx[CTX_EFLAGS]), regs.eflags);
    if (os.setThreadContext(st.thread, @ptrCast(*const void, &ctx[0])) == 0) return error.RegFailed;
}

fn readBytes(st: *State, addr: u32, dst: []u8) backend.BackendError!void {
    if (dst.len == 0) return;
    if (os.readProcessMemory(st.process, @intToPtr(*const void, addr), @ptrCast(*void, dst.ptr), dst.len) == 0) {
        return error.ReadFailed;
    }
}

fn writeBytes(st: *State, addr: u32, src: []const u8) backend.BackendError!void {
    if (src.len == 0) return;
    if (os.writeProcessMemory(st.process, @intToPtr(*const void, addr), @ptrCast(*const void, src.ptr), src.len) == 0) {
        return error.WriteFailed;
    }
    _ = os.flushInstructionCache(st.process, @intToPtr(*const void, addr), src.len);
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

pub fn pidOf(state: *void) i32 {
    var st = @ptrCast(*State, state);
    return @intCast(i32, st.pid);
}

pub fn imageBaseOf(state: *void) u32 {
    var st = @ptrCast(*State, state);
    return st.image_base;
}

fn storeCreateProcess(st: *State, ev: [*]const u8) void {
    st.process = @intToPtr(*void, readU32(ev + 16));
    st.thread = @intToPtr(*void, readU32(ev + 20));
    st.image_base = readU32(ev + 24);
    st.pid = readU32(ev + 4);
    st.tid = readU32(ev + 8);
}

fn waitRaw(st: *State) backend.BackendError!backend.StopEvent {
    while (true) {
        var ev: [96]u8 = undefined;
        var i: usize = 0;
        while (i < 96) : (i += 1) ev[i] = 0;
        if (os.waitForDebugEvent(@ptrCast(*void, &ev[0]), @intCast(u32, 50)) == 0) {
            if (!st.alive or st.exited) return error.WaitFailed;
            continue;
        }
        var ep = @ptrCast([*]const u8, &ev[0]);
        var code = readU32(ep);
        st.pid = readU32(ep + 4);
        st.tid = readU32(ep + 8);
        if (code == CREATE_PROCESS_DEBUG_EVENT) {
            storeCreateProcess(st, ep);
            try continueEvent(st);
            continue;
        }
        if (code == CREATE_THREAD_DEBUG_EVENT or code == LOAD_DLL_DEBUG_EVENT or
            code == UNLOAD_DLL_DEBUG_EVENT or code == OUTPUT_DEBUG_STRING_EVENT or
            code == EXIT_THREAD_DEBUG_EVENT or code == RIP_EVENT) {
            try continueEvent(st);
            continue;
        }
        if (code == EXIT_PROCESS_DEBUG_EVENT) {
            st.exited = true;
            st.alive = false;
            continueEvent(st) catch {};
            return backend.StopEvent{ .reason = backend.STOP_EXITED, .signo = 0, .eip = 0 };
        }
        if (code == 1) { // EXCEPTION_DEBUG_EVENT
            var exc = readU32(ep + 12);
            var addr = readU32(ep + 24);
            var regs: backend.Registers = undefined;
            var regs_ok = true;
            getRegsRaw(st, &regs) catch {
                regs_ok = false;
            };
            if (exc == EXCEPTION_SINGLE_STEP) {
                st.stepping = false;
                if (regs_ok) {
                    regs.eflags = regs.eflags & ~TF_BIT;
                    setRegsRaw(st, &regs) catch {};
                }
                var eip: u32 = addr;
                if (regs_ok) eip = regs.eip;
                return backend.StopEvent{ .reason = backend.STOP_SINGLE_STEP, .signo = 5, .eip = eip };
            }
            if (exc == EXCEPTION_BREAKPOINT) {
                if (regs_ok and regs.eip > 0) {
                    var bp_addr = regs.eip - 1;
                    if (findBreak(st, bp_addr)) |idx| {
                        if (st.breaks[idx].enabled) {
                            var orig: [1]u8 = undefined;
                            orig[0] = st.breaks[idx].orig;
                            writeBytes(st, bp_addr, orig[0..1]) catch {};
                            st.breaks[idx].enabled = false;
                            regs.eip = bp_addr;
                            setRegsRaw(st, &regs) catch {};
                            st.stepping = false;
                            return backend.StopEvent{ .reason = backend.STOP_BREAKPOINT, .signo = 5, .eip = bp_addr };
                        }
                    }
                }
                if (st.skip_initial) {
                    st.skip_initial = false;
                    try continueEvent(st);
                    continue;
                }
                return backend.StopEvent{ .reason = backend.STOP_SIGNAL, .signo = 5, .eip = addr };
            }
            var signo: i32 = 5;
            if (exc == EXCEPTION_ACCESS_VIOLATION) signo = 11;
            if (regs_ok) return backend.StopEvent{ .reason = backend.STOP_SIGNAL, .signo = signo, .eip = regs.eip };
            return backend.StopEvent{ .reason = backend.STOP_SIGNAL, .signo = signo, .eip = addr };
        }
        try continueEvent(st);
    }
    return error.WaitFailed;
}

fn launch(state: *void, exe: []const u8, args: [][]const u8) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    st.process = @intToPtr(*void, 0);
    st.thread = @intToPtr(*void, 0);
    st.pid = 0;
    st.tid = 0;
    st.image_base = 0;
    st.alive = false;
    st.exited = false;
    st.stepping = false;
    st.skip_initial = true;
    st.break_n = 0;

    var cmd: [8192]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < exe.len and n + 1 < cmd.len) : (i += 1) {
        cmd[n] = exe[i];
        n += 1;
    }
    var ai: usize = 0;
    while (ai < args.len) : (ai += 1) {
        if (n + 1 >= cmd.len) break;
        cmd[n] = ' ';
        n += 1;
        var s = args[ai];
        var j: usize = 0;
        while (j < s.len and n + 1 < cmd.len) : (j += 1) {
            cmd[n] = s[j];
            n += 1;
        }
    }
    cmd[n] = 0;

    var startup: [68]u8 = undefined;
    var k: usize = 0;
    while (k < 68) : (k += 1) startup[k] = 0;
    writeU32(@ptrCast([*]u8, &startup[0]), 68);
    var info: [16]u8 = undefined;
    k = 0;
    while (k < 16) : (k += 1) info[k] = 0;

    if (os.createProcessA(@ptrCast(*const void, @intToPtr(*void, 0)), @ptrCast([*]u8, &cmd[0]), @ptrCast(*void, &startup[0]), @ptrCast(*void, &info[0])) == 0) {
        return error.LaunchFailed;
    }
    st.process = @intToPtr(*void, readU32(@ptrCast([*]const u8, &info[0])));
    st.thread = @intToPtr(*void, readU32(@ptrCast([*]const u8, &info[4])));
    st.pid = readU32(@ptrCast([*]const u8, &info[8]));
    st.tid = readU32(@ptrCast([*]const u8, &info[12]));
    st.alive = true;

    // Consume CREATE_PROCESS without continuing it: the session plants entry
    // breakpoints, then continue() releases the process. This also makes
    // imageBase_fn usable before the first wait.
    while (true) {
        var ev: [96]u8 = undefined;
        var z: usize = 0;
        while (z < 96) : (z += 1) ev[z] = 0;
        if (os.waitForDebugEvent(@ptrCast(*void, &ev[0]), @intCast(u32, 50)) == 0) continue;
        var ep = @ptrCast([*]const u8, &ev[0]);
        var code = readU32(ep);
        if (code == CREATE_PROCESS_DEBUG_EVENT) {
            storeCreateProcess(st, ep);
            return;
        }
        st.pid = readU32(ep + 4);
        st.tid = readU32(ep + 8);
        if (code == EXIT_PROCESS_DEBUG_EVENT) {
            st.alive = false;
            st.exited = true;
            continueEvent(st) catch {};
            return error.LaunchFailed;
        }
        try continueEvent(st);
    }
    return;
}

fn waitFn(state: *void) backend.BackendError!backend.StopEvent {
    var st = @ptrCast(*State, state);
    if (!st.alive or st.exited) return error.WaitFailed;
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
    try getRegsRaw(st, regs);
}

fn setRegsFn(state: *void, regs: *const backend.Registers) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    try setRegsRaw(st, regs);
}

fn singleStepFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    if (!st.alive or st.exited) return error.StepFailed;
    var regs: backend.Registers = undefined;
    try getRegsRaw(st, &regs);
    regs.eflags = regs.eflags | TF_BIT;
    try setRegsRaw(st, &regs);
    st.stepping = true;
    try continueEvent(st);
}

fn continueFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    if (!st.alive or st.exited) return error.ContinueFailed;
    var regs: backend.Registers = undefined;
    var have = true;
    getRegsRaw(st, &regs) catch {
        have = false;
    };
    var i: usize = 0;
    while (i < st.break_n) : (i += 1) {
        if (have and st.breaks[i].addr == regs.eip) continue;
        enableAt(st, st.breaks[i].addr) catch return error.ContinueFailed;
    }
    try continueEvent(st);
}

fn detachFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    restoreAll(state);
    if (st.alive and !st.exited) {
        _ = os.terminateProcess(st.process, 0);
        st.alive = false;
        st.exited = true;
    }
    if (!isNull(st.process)) {
        _ = os.closeHandle(st.process);
        st.process = @intToPtr(*void, 0);
    }
    if (!isNull(st.thread)) {
        _ = os.closeHandle(st.thread);
        st.thread = @intToPtr(*void, 0);
    }
}

fn terminateFn(state: *void) backend.BackendError!void {
    var st = @ptrCast(*State, state);
    restoreAll(state);
    if (st.alive and !st.exited) {
        _ = os.terminateProcess(st.process, 1);
        st.alive = false;
        st.exited = true;
    }
}

pub fn win98Backend() backend.Backend {
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
        .plant_fn = plant,
        .removeBreak_fn = removeBreak,
        .restoreAll_fn = restoreAll,
        .installAllExcept_fn = installAllExceptAddr,
        .pid_fn = pidOf,
        .imageBase_fn = imageBaseOf,
    };
}
