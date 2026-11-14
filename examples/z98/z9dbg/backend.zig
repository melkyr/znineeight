// backend.zig — the debugger's process-control vtable (P3-M2).
//
// The upper layer (main/dbg_core) never names ptrace or the Win32 Debug API;
// it drives a backend through this record. M2 ships only the contract and a
// stub: launch/wait/memory/registers/single-step/continue/detach/terminate all
// return error.Unsupported until the Linux ptrace (M3) and Win98 (M4) backends
// land. No machine address is invented here.

pub const BackendError = error{
    Unsupported,
    LaunchFailed,
    WaitFailed,
    ReadFailed,
    WriteFailed,
    RegFailed,
    StepFailed,
    ContinueFailed,
    DetachFailed,
    TerminateFailed,
};

// i386 general-purpose register context (spec §14: debuggee arch = i386).
pub const Registers = struct {
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    eip: u32,
    eflags: u32,
};

// A stop reported by the backend. reason is backend-neutral: 0 = entry,
// 1 = breakpoint, 2 = single-step, 3 = signal, 4 = exited. Source resolution
// (map + C debug info) is the upper layer's job, not the backend's.
pub const StopEvent = struct {
    reason: u8,
    signo: i32,
    eip: u32,
};

pub const STOP_ENTRY: u8 = 0;
pub const STOP_BREAKPOINT: u8 = 1;
pub const STOP_SINGLE_STEP: u8 = 2;
pub const STOP_SIGNAL: u8 = 3;
pub const STOP_EXITED: u8 = 4;
// The process terminated because of a signal (WIFSIGNALED), as opposed to a
// signal-delivery stop (STOP_SIGNAL) from which it can still continue.
pub const STOP_SIGNALED_EXIT: u8 = 5;

pub const Backend = struct {
    // true for a real process backend (backend_linux): the command loop then
    // waits for and displays stops after continue/dump. Stub/mock backends in
    // the M2 headless tests keep live = false, preserving their scripted UX.
    live: bool,
    state: *void,
    launch_fn: fn (*void, []const u8, [][]const u8) BackendError!void,
    wait_fn: fn (*void) BackendError!StopEvent,
    readMemory_fn: fn (*void, u32, []u8) BackendError!void,
    writeMemory_fn: fn (*void, u32, []const u8) BackendError!void,
    getRegs_fn: fn (*void, *Registers) BackendError!void,
    setRegs_fn: fn (*void, *const Registers) BackendError!void,
    singleStep_fn: fn (*void) BackendError!void,
    continue_fn: fn (*void) BackendError!void,
    detach_fn: fn (*void) BackendError!void,
    terminate_fn: fn (*void) BackendError!void,
    // Machine-breakpoint ops (M3 fix round 1): the upper layer owns the
    // source mapping, but it must not name a concrete backend for int3
    // planting/restoration or the child pid (PIE bias lookup).
    plant_fn: fn (*void, u32) BackendError!void,
    removeBreak_fn: fn (*void, u32) void,
    restoreAll_fn: fn (*void) void,
    installAllExcept_fn: fn (*void, u32) void,
    pid_fn: fn (*void) i32,
    // Runtime load address of the debuggee image. Linux/Win32-ELF return 0
    // (the ELF path uses /proc/<pid>/maps); the Win32 backend returns
    // CREATE_PROCESS_DEBUG_INFO.lpBaseOfImage so PE rows can be biased.
    imageBase_fn: fn (*void) u32,
};

fn stubLaunch(state: *void, exe: []const u8, args: [][]const u8) BackendError!void {
    _ = state;
    _ = exe;
    _ = args;
    return error.Unsupported;
}

fn stubWait(state: *void) BackendError!StopEvent {
    _ = state;
    return error.Unsupported;
}

fn stubReadMemory(state: *void, addr: u32, dst: []u8) BackendError!void {
    _ = state;
    _ = addr;
    _ = dst;
    return error.Unsupported;
}

fn stubWriteMemory(state: *void, addr: u32, src: []const u8) BackendError!void {
    _ = state;
    _ = addr;
    _ = src;
    return error.Unsupported;
}

fn stubGetRegs(state: *void, regs: *Registers) BackendError!void {
    _ = state;
    _ = regs;
    return error.Unsupported;
}

fn stubSetRegs(state: *void, regs: *const Registers) BackendError!void {
    _ = state;
    _ = regs;
    return error.Unsupported;
}

fn stubSingleStep(state: *void) BackendError!void {
    _ = state;
    return error.Unsupported;
}

fn stubContinue(state: *void) BackendError!void {
    _ = state;
    return error.Unsupported;
}

fn stubDetach(state: *void) BackendError!void {
    _ = state;
    return error.Unsupported;
}

fn stubTerminate(state: *void) BackendError!void {
    _ = state;
    return error.Unsupported;
}

fn stubPlant(state: *void, addr: u32) BackendError!void {
    _ = state;
    _ = addr;
    return error.Unsupported;
}

fn stubRemoveBreak(state: *void, addr: u32) void {
    _ = state;
    _ = addr;
}

fn stubRestoreAll(state: *void) void {
    _ = state;
}

fn stubInstallAllExcept(state: *void, skip: u32) void {
    _ = state;
    _ = skip;
}

fn stubPid(state: *void) i32 {
    _ = state;
    return -1;
}

fn stubImageBase(state: *void) u32 {
    _ = state;
    return 0;
}

// The M2 backend: a well-formed vtable whose every operation is unsupported.
// M3 installs backend_linux's functions here; the upper layer is unchanged.
pub fn stubBackend() Backend {
    return Backend{
        .live = false,
        .state = @ptrCast(*void, @intToPtr(*void, 0)),
        .launch_fn = stubLaunch,
        .wait_fn = stubWait,
        .readMemory_fn = stubReadMemory,
        .writeMemory_fn = stubWriteMemory,
        .getRegs_fn = stubGetRegs,
        .setRegs_fn = stubSetRegs,
        .singleStep_fn = stubSingleStep,
        .continue_fn = stubContinue,
        .detach_fn = stubDetach,
        .terminate_fn = stubTerminate,
        .plant_fn = stubPlant,
        .removeBreak_fn = stubRemoveBreak,
        .restoreAll_fn = stubRestoreAll,
        .installAllExcept_fn = stubInstallAllExcept,
        .pid_fn = stubPid,
        .imageBase_fn = stubImageBase,
    };
}
