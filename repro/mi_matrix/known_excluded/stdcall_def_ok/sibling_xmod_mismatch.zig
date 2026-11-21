// D5/D10 fix-round-2 sibling probe: the convention agreement check must cover
// the whole compilation unit. sibling_xmod_mismatch_decl.zig declares
// `xm_mismatch` as stdcall; this module defines it as cdecl. Sema must reject
// the disagreement (error[3000]) and emit no `.c`, rather than silently
// emitting a stdcall call to a cdecl definition (stack mismatch).
const std = @import("std");
const decl = @import("sibling_xmod_mismatch_decl.zig");

pub extern fn xm_mismatch(x: u32) i32 {
    return @intCast(i32, x);
}

pub fn main() void {
    std.io.printInt(decl.touch());
    std.io.writeByte(' ');
    std.io.printInt(xm_mismatch(41));
    std.io.writeByte('\n');
}
