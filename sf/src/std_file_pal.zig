// std_file_pal.zig — Z98 std_file std-side PAL: target-selected extern "c" /
// extern "stdcall" OS file bindings (the std_os_pal.zig / std_time_pal.zig
// pattern, R8). The compiler PAL (pal.zig / zig_pal.c) is NOT touched, and the
// compiler-PAL `pal_file_*` surface is not used or extended: the compiler's
// cost is what it imports, the library's cost is what emits.
//
// Prototypes come from the authorized std_os_prelude.h (the net_prelude.h
// analog: `_WIN32` -> windows.h, else unistd.h), plus the portable <fcntl.h>
// (POSIX open flags) and <stdio.h> (rename). Plan B is not authorized to add a
// new compiler-emitted prelude (R8), so the shared OS include prelude is reused.
// The externs are declared here; the @isWindows() guards live in std_file.zig,
// which also @cIncludes the prelude and the two portable headers so the
// prototypes are visible at its call sites.

@cInclude("<std_os_prelude.h>");

// --- win32 (kernel32, always present on win9x) ------------------------------
// CreateFileA, never fopen (blueprint §3 L3). dwDesiredAccess / share /
// creation-disposition / flags are DWORD (u32); the security-attributes and
// template-file handles are null.
pub extern "stdcall" fn CreateFileA(lpFileName: [*]const u8, dwDesiredAccess: u32, dwShareMode: u32, lpSecurityAttributes: *void, dwCreationDisposition: u32, dwFlagsAndAttributes: u32, hTemplateFile: *void) *void;
pub extern "stdcall" fn ReadFile(hFile: *void, lpBuffer: [*]u8, nNumberOfBytesToRead: u32, lpNumberOfBytesRead: *u32, lpOverlapped: *void) i32;
pub extern "stdcall" fn WriteFile(hFile: *void, lpBuffer: [*]const u8, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: *u32, lpOverlapped: *void) i32;
// LARGE_INTEGER is byte-exact as i64 (QuadPart at offset 0, 8 bytes), the same
// S2-I layout-probe pattern std_time uses for QueryPerformanceCounter.
pub extern "stdcall" fn SetFilePointerEx(hFile: *void, liDistanceToMove: i64, lpNewFilePointer: *i64, dwMoveMethod: u32) i32;
// GetFileSizeEx, not ftell (blueprint §3 L3).
pub extern "stdcall" fn GetFileSizeEx(hFile: *void, lpFileSize: *i64) i32;
pub extern "stdcall" fn FlushFileBuffers(hFile: *void) i32;
pub extern "stdcall" fn CloseHandle(hObject: *void) i32;
pub extern "stdcall" fn GetFileAttributesA(lpFileName: [*]const u8) u32;
pub extern "stdcall" fn DeleteFileA(lpFileName: [*]const u8) i32;
pub extern "stdcall" fn MoveFileA(lpExistingFileName: [*]const u8, lpNewFileName: [*]const u8) i32;
// win32: attributes + last-write time WITHOUT opening the file (the mtime
// capability). fInfoLevelId is GET_FILEEX_INFO_LEVELS (GetFileExInfoStandard ==
// 0); lpFileInformation points at the caller's byte buffer for
// WIN32_FILE_ATTRIBUTE_DATA (read at a probed offset; see std_file.zig). Return
// is BOOL (0 on failure).
pub extern "stdcall" fn GetFileAttributesExA(lpFileName: [*]const u8, fInfoLevelId: u32, lpFileInformation: *void) i32;

// --- POSIX ----------------------------------------------------------------
// open flags are hardcoded by the caller (no dependence on the fcntl.h macro
// values); the pinned i386 target has a 32-bit off_t. 64-bit seeking goes
// through the generic syscall(2) entry point: glibc declares no author
// lseek64/_llseek prototype under the pinned -std=c89 (no _LARGEFILE64_SOURCE)
// compilation, and Z98 emits no extern prototypes (C declarations come only
// from the headers it @cIncludes), so a 64-bit-returning lseek64 would be
// called through an implicit `int` declaration and truncate the offset.
// syscall(2) returns `long` (32-bit on i386) and the _llseek syscall
// (i386 __NR__llseek == 140, supplied by the caller) writes the full 64-bit
// offset through `result`. The caller passes O_LARGEFILE so the file may grow
// past 2 GiB. The fixed arg list mirrors that syscall.
pub extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
pub extern "c" fn read(fd: i32, buf: [*]u8, count: u32) i32;
pub extern "c" fn write(fd: i32, buf: [*]const u8, count: u32) i32;
pub extern "c" fn syscall(number: i32, fd: i32, offset_high: u32, offset_low: u32, result: *i64, whence: i32) i32;
pub extern "c" fn close(fd: i32) i32;
pub extern "c" fn fsync(fd: i32) i32;
pub extern "c" fn unlink(path: [*]const u8) i32;
pub extern "c" fn rename(old_path: [*]const u8, new_path: [*]const u8) i32;
pub extern "c" fn access(path: [*]const u8, mode: i32) i32;
// POSIX stat(2)/fstat(2) for the file modification-time capability (mtime). The
// out-buffer is *void: the caller supplies a byte buffer sized for the target's
// `struct stat` and reads st_mtime at a probed offset (the S2-I opaque-layout
// pattern; see std_file.zig). The C prototype comes from <sys/stat.h>
// (@cInclude'd by std_file.zig); the plain `stat`/`fstat` names resolve to the
// glibc 2.33+ exported symbols under -m32 (probe 2026-10-08: links against
// stat@GLIBC_2.33 / fstat@GLIBC_2.33 on glibc 2.36/i386).
pub extern "c" fn stat(path: [*]const u8, buf: *void) i32;
pub extern "c" fn fstat(fd: i32, buf: *void) i32;
