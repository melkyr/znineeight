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
