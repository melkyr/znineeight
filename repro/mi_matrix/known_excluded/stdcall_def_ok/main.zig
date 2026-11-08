// stdcall_def_ok — Phase 3.5 D5/D10 repro (extern "stdcall" definition).
//
// An `extern "stdcall" fn ... { ... }` with a body must emit a real C
// definition carrying `Z98_STDCALL` (empty on non-Windows, so the linux build
// is cdecl-clean). Pre-fix the body is analyzed and silently dropped: the
// emitted C has no definition and gcc rejects the call with
// `'cb' undeclared` (no Z98 diagnostic).
//
// GREEN (post-fix): dump rc=0, gcc clean, stdout `42\n`, rc 0.
const std = @import("std");

pub extern "stdcall" fn cb(x: u32) i32 {
    return @intCast(i32, x) + 1;
}

pub fn main() void {
    std.io.printInt(cb(41));
    std.io.writeByte('\n');
}
