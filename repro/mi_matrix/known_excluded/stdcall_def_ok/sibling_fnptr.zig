// D5/D10 sibling probe: the stdcall definition called directly AND through a
// convention-qualified function pointer.
const std = @import("std");

const Cb = extern "stdcall" fn(u32) i32;

pub extern "stdcall" fn cb(x: u32) i32 {
    return @intCast(i32, x) + 1;
}

pub fn main() void {
    var f: Cb = cb;
    std.io.printInt(cb(41));
    std.io.writeByte(' ');
    std.io.printInt(f(41));
    std.io.writeByte('\n');
}
