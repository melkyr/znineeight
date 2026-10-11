// console.zig — z9torr M5 T3b: is stdout an interactive console?
//
// The 1 Hz progress line is rewritten in place with a carriage return ('\r')
// only when stdout is a console. When stdout is redirected (to a file or a
// pipe) a '\r' does not return the cursor to column 0, so each refresh would be
// appended as raw CR bytes; in that case the caller emits one line per refresh
// ('\n') instead.
//
// EXAMPLE-ONLY (M5 operator ruling): the Win32 calls are declared here, not in
// sf/src. @cInclude pulls the shared std_os_prelude.h so the C prototypes are
// visible at the call sites (the std_os_pal.zig / std_stdin_pal.zig pattern).
// The @isWindows() guard prunes the other target's branch, so only the
// referenced extern is emitted; the compiler fixed point is untouched.
//
// Detection: win32 GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) == FILE_TYPE_CHAR
// (a character device = console); POSIX isatty(1) != 0.

@cInclude("<std_os_prelude.h>");

// win32 STD_OUTPUT_HANDLE == (DWORD)-11; FILE_TYPE_CHAR == 0x0002.
const STD_OUTPUT_HANDLE: i32 = -11;
const FILE_TYPE_CHAR: u32 = 2;

// kernel32, always present on win9x (see std_stdin_pal.zig). isatty comes from
// <unistd.h> via std_os_prelude.h on POSIX and is unreferenced on win32.
pub extern "stdcall" fn GetStdHandle(nStdHandle: i32) *void;
pub extern "stdcall" fn GetFileType(hFile: *void) u32;
pub extern "c" fn isatty(fd: i32) i32;

// True when stdout is an interactive console (Win9x character device / POSIX
// tty), false when redirected. GetFileType on an invalid handle returns
// FILE_TYPE_UNKNOWN (0), which is != FILE_TYPE_CHAR, so no null check is needed.
pub fn stdoutIsConsole() bool {
    if (@isWindows()) {
        var h: *void = GetStdHandle(STD_OUTPUT_HANDLE);
        return GetFileType(h) == FILE_TYPE_CHAR;
    } else {
        return isatty(1) != 0;
    }
}
