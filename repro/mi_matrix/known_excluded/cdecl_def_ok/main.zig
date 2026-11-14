// cdecl_def_ok — Phase 3.5 D5 repro (bare and "c" extern definitions = cdecl).
//
// An `extern fn ... { ... }` / `extern "c" fn ... { ... }` with a body must
// emit a real cdecl definition. Pre-fix the body is analyzed and silently
// dropped (no definition, no prototype), so gcc rejects the call with
// `'cd'`/`'ce'` undeclared.
//
// GREEN (post-fix): dump rc=0, gcc clean, stdout `44 46\n`, rc 0.
const std = @import("std");

pub extern fn cd(x: u32) i32 {
    return @intCast(i32, x) + 2;
}

pub extern "c" fn ce(x: u32) i32 {
    return @intCast(i32, x) + 4;
}

pub fn main() void {
    std.io.printInt(cd(42));
    std.io.writeByte(' ');
    std.io.printInt(ce(42));
    std.io.writeByte('\n');
}
