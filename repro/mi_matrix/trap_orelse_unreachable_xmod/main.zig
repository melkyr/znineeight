// trap_orelse_unreachable_xmod — RED->GREEN trap fixture (A2F). `orelse
// unreachable` on a null optional MUST terminate via pal_trap() instead of
// reading the garbage payload of the null optional.
//
// RED (seed v9): the null arm is empty and falls into the payload read; the
// program continues and prints the garbage payload (rc 0). GREEN: pal_trap()
// fires on the null path; stdout `before\n`, rc != 0.
const std = @import("std");

fn get() ?i32 {
    return null;
}

pub fn main() void {
    std.io.writeStr("before\n");
    var x = get() orelse unreachable;
    std.io.printInt(x);
    std.io.writeByte('\n');
}
