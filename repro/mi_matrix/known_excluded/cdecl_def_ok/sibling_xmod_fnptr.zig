// D5 fix-round-2 sibling probe: cross-module cdecl extern definitions used as
// function values. `cv` is defined in sibling_xmod_cv.zig; this module must
// still emit the original C symbol (`cv`), not a mangled local name, when it
// takes `cv` as a value or calls it.
const std = @import("std");
const cvm = @import("sibling_xmod_cv.zig");

const Cb = extern fn(u32) i32;

pub fn main() void {
    var f: Cb = cvm.cv;
    std.io.printInt(cvm.cv(40));
    std.io.writeByte(' ');
    std.io.printInt(f(40));
    std.io.writeByte('\n');
}
