// D5/D10 sibling probe: a cdecl extern definition referenced as a function
// value (the atexit(cb) / callback-registration shape) as well as called
// directly. The definition is emitted under its original symbol, so the
// function value must reference that symbol too, not a mangled local name.
const std = @import("std");

const Cb = extern fn(u32) i32;

pub extern fn cv(x: u32) i32 {
    return @intCast(i32, x) + 6;
}

pub fn main() void {
    var f: Cb = cv;
    std.io.printInt(cv(40));
    std.io.writeByte(' ');
    std.io.printInt(f(40));
    std.io.writeByte('\n');
}
