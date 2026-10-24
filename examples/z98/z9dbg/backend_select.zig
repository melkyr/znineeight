// backend_select.zig — one compile-time backend-selection point.
//
// main.zig names only this module; the M4 Win32 backend replaces the Windows
// arm here, leaving the upper layer (main/dbg_core/map_reader) untouched.
// The Linux arm is the ptrace backend from M3.

const backend = @import("backend.zig");
const linux = @import("backend_linux.zig");

pub fn select() backend.Backend {
    if (@isWindows()) {
        // M4: return the Win32 Debug-API backend here.
        return linux.linuxBackend();
    }
    return linux.linuxBackend();
}
