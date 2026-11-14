// std_stdin_pal.zig — Z98 std_stdin std-side PAL: the process stdin handle
// (the std_os_pal.zig / std_file_pal.zig pattern, R8). The compiler PAL
// (pal.zig / zig_pal.c) is NOT touched, and the compiler-PAL `pal_file_*`
// surface is neither used nor extended: the compiler's cost is what it
// imports, the library's cost is what emits.
//
// POSIX stdin is the well-known descriptor 0 and needs no extern. win32 stdin
// is GetStdHandle(STD_INPUT_HANDLE) (kernel32, always present on win9x),
// declared extern "stdcall". The @isWindows() guard lives in std_stdin.zig,
// which also @cIncludes the shared OS prelude so the prototype is visible at
// its call sites. Plan B is not authorized to add a new compiler-emitted
// prelude (R8), so the shared OS include prelude is reused.

@cInclude("<std_os_prelude.h>");

pub extern "stdcall" fn GetStdHandle(nStdHandle: i32) *void;
