// std_os_pal.zig — Z98 std_os std-side PAL: target-selected extern "c" OS
// bindings (the std_net.zig pattern, R8). The compiler PAL (pal.zig /
// zig_pal.c) is NOT touched: the compiler's cost is what it imports, the
// library's cost is what emits.
//
// std_os_prelude.h (the net_prelude.h analog, found on the compiler include
// path and emitted next to the program) supplies the per-OS C prototypes,
// because the C89 emitter emits no prototype for non-variadic externs. The
// externs are declared here; the @isWindows() guards live in std_os.zig, which
// also @cIncludes the prelude so the prototypes are visible at its call sites.

@cInclude("<std_os_prelude.h>");

// win32 (kernel32, always present on win9x): fill lpBuffer with the current
// directory; returns the number of characters written (excluding the NUL), or
// the required buffer size if lpBuffer is too small.
pub extern "stdcall" fn GetCurrentDirectoryA(nBufferLength: u32, lpBuffer: [*]u8) u32;

// POSIX: fill buf (size bytes) with the current directory; returns buf on
// success, null on failure.
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8;

// Portable CRT: environment lookup; null when unset.
pub extern "c" fn getenv(name: [*]const u8) ?[*]const u8;

// win32: GetEnvironmentVariableA into one static PAL buffer (single-threaded;
// valid until the next call); null when unset/oversized.
pub extern "c" fn pal_getenv(name: [*]const u8) ?[*]const u8;

// POSIX process/debug bindings (P3-M3). The @isWindows() guards in std_os.zig
// prune every call site on Win32, so the emitted win32 C never references
// these symbols (the Win32 Debug API bindings are M4). No custom prototypes
// are required: <unistd.h> in the prelude declares fork/execv/getpid/close,
// and C89 implicit declarations cover waitpid/ptrace/open/dup2
// (-Wno-implicit-function-declaration is in the binding build flags).
//
// ptrace's i386 ABI is four fixed args (request, pid, addr, data); the real
// libc prototype is variadic, which accepts this fixed-argument call.
pub extern "c" fn fork() i32;
pub extern "c" fn execv(path: [*]const u8, arg_values: [*]const [*]const u8) i32;
pub extern "c" fn waitpid(pid: i32, status: *i32, options: i32) i32;
pub extern "c" fn ptrace(request: i32, pid: i32, addr: *void, data: *void) i32;
pub extern "c" fn getpid() i32;
pub extern "c" fn kill(pid: i32, sig: i32) i32;
pub extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
pub extern "c" fn dup2(old_fd: i32, new_fd: i32) i32;
pub extern "c" fn close(fd: i32) i32;
pub extern "c" fn __errno_location() *i32;

// --- Win32 Debug API (P3-M4, spec §15.5) -----------------------------------
//
// Declared in the std-side PAL and called only through the @isWindows()
// wrappers in std_os.zig, so a Linux emission references none of these. The
// debugger passes raw DEBUG_EVENT (96 B), CONTEXT_i386 (716 B) and
// STARTUPINFOA/PROCESS_INFORMATION buffers rather than struct definitions, to
// avoid Win9x/Wine ABI drift; <windows.h> in std_os_prelude.h supplies the
// real prototypes and constants for the emitted C.
pub extern "stdcall" fn CreateProcessA(lpApplicationName: *const void, lpCommandLine: [*]u8, lpProcessAttributes: *void, lpThreadAttributes: *void, bInheritHandles: i32, dwCreationFlags: u32, lpEnvironment: *void, lpCurrentDirectory: *const void, lpStartupInfo: *void, lpProcessInformation: *void) i32;
pub extern "stdcall" fn WaitForDebugEvent(lpDebugEvent: *void, dwMilliseconds: u32) i32;
pub extern "stdcall" fn ContinueDebugEvent(dwProcessId: u32, dwThreadId: u32, dwContinueStatus: u32) i32;
pub extern "stdcall" fn GetThreadContext(hThread: *void, lpContext: *void) i32;
pub extern "stdcall" fn SetThreadContext(hThread: *void, lpContext: *const void) i32;
pub extern "stdcall" fn ReadProcessMemory(hProcess: *void, lpBaseAddress: *const void, lpBuffer: *void, nSize: usize, lpNumberOfBytesRead: *usize) i32;
pub extern "stdcall" fn WriteProcessMemory(hProcess: *void, lpBaseAddress: *const void, lpBuffer: *const void, nSize: usize, lpNumberOfBytesWritten: *usize) i32;
pub extern "stdcall" fn FlushInstructionCache(hProcess: *void, lpBaseAddress: *const void, dwSize: usize) i32;
pub extern "stdcall" fn TerminateProcess(hProcess: *void, uExitCode: u32) i32;
pub extern "stdcall" fn CloseHandle(hObject: *void) i32;
