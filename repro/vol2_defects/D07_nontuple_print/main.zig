// D7 in-module RED: `print(fmt, <non-tuple literal>)` is silently accepted.
// The placeholder is dropped and the argument is never printed; here only the
// trailing newline of the format text survives. rc 0, silent no-op.
const std = @import("std");

pub fn main() void {
    std.io.print("{}\n", 5);
}
