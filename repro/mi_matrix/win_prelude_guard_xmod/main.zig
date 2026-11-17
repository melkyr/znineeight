// win_prelude_guard_xmod — console builtin + std_net in one module.
//
// The C89 console prelude (WINVER/_WIN32_WINDOWS/_WIN32_WINNT/NTDDI_VERSION/
// WIN32_LEAN_AND_MEAN + <windows.h>) must be guarded so a module whose header
// already pulled <net_prelude.h> -> <windows.h> does not redefine NTDDI_VERSION
// (OpenWatcom E1100). This fixture reproduces that include order: the emitted
// module header includes <std_net_<hash>.h>, which includes net_prelude.h, and
// the console block follows in the .c.
const std = @import("std");
const std_net = @import("std_net.zig");

pub fn main() void {
    const port = std_net.htonsManual(@intCast(u16, 4000));
    @consoleClear();
    @consoleGotoxy(0, 0);
    @consoleSetColor(7, 0);
    std.io.printInt(@intCast(i32, port));
    @exit(@intCast(u8, 0));
}
