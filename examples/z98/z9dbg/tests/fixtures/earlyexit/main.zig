// P3-M3 entry-stop honesty fixture: module init exits before main. z9dbg must
// report the pre-entry exit explicitly, not as a normal entry stop.
const std = @import("std");

var x: u32 = early();

fn early() u32 {
    std.os.exit(7);
    return 0;
}

pub fn main() void {}
