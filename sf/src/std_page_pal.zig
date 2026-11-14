// std_page_pal.zig — Z98 std_page std-side PAL: target-selected extern "c"
// OS bindings (the std_os_pal.zig / std_time_pal.zig pattern, R8). The
// compiler PAL (pal.zig / zig_pal.c) is NOT touched: the compiler's cost is
// what it imports, the library's cost is what emits.
//
// std_page_prelude.h (found on the compiler include path and emitted next to
// the program) supplies the per-OS C prototypes, because the C89 emitter emits
// no fallback prototype for a module carrying @cInclude. The externs are
// declared here; the @isWindows() guards live in std_page.zig, which also
// @cIncludes the prelude so the prototypes are visible at its call sites.
//
// POSIX is Linux-targeted: the constants below are the Linux 2.2+ ABI values
// (MAP_ANON is 0x20 on Linux; modern systems alias MAP_ANONYMOUS to it). The
// mmap offset is i32 to match a 32-bit off_t; _FILE_OFFSET_BITS is never
// defined (LFS/mmap64 is out of scope and must fail loudly).

@cInclude("<std_page_prelude.h>");

// POSIX: map/unmap pages. mmap reports failure as MAP_FAILED ((void*)-1), so
// it is declared non-optional and std_page.zig converts the sentinel to null.
pub extern "c" fn mmap(addr: ?*void, len: usize, prot: i32, flags: i32, fd: i32, off: i32) *void;
pub extern "c" fn mprotect(addr: *void, len: usize, prot: i32) i32;
pub extern "c" fn munmap(addr: *void, len: usize) i32;

pub const PROT_NONE: i32 = 0;
pub const PROT_READ: i32 = 1;
pub const PROT_WRITE: i32 = 2;
pub const MAP_PRIVATE: i32 = 2;
pub const MAP_FIXED: i32 = 16;
pub const MAP_ANON: i32 = 32;

// Win32 (kernel32, always present on Win9x): reserve/commit/decommit/release
// page ranges. VirtualAlloc failure is a null return, converted in std_page.zig
// with @ptrToInt == 0 (the z9git rule); VirtualFree returns non-zero on success.
// The address and return are plain `*void` (not `?*void`) to match <windows.h>'s
// LPVOID prototype exactly: the emitted stdcall call casts through the extern's
// function type, so wrappered optionals would mismatch the prelude, pass a
// struct by value, and make the optional-return cast unrepresentable.
pub extern "stdcall" fn VirtualAlloc(addr: *void, size: usize, typ: u32, protect: u32) *void;
pub extern "stdcall" fn VirtualFree(addr: *void, size: usize, typ: u32) i32;

pub const MEM_COMMIT: u32 = 0x1000;
pub const MEM_RESERVE: u32 = 0x2000;
pub const MEM_DECOMMIT: u32 = 0x4000;
pub const MEM_RELEASE: u32 = 0x8000;
pub const PAGE_NOACCESS: u32 = 1;
pub const PAGE_READWRITE: u32 = 4;
