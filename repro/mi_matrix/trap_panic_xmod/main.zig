// trap_panic_xmod — RED->GREEN trap fixture (A2F). `@panic(msg)` is retyped
// `noreturn`: it evaluates and prints the argument, then traps via pal_trap().
//
// RED (seed v9): `@panic` is a no-op (payload/side effects dropped); execution
// continues to "after", rc 0, stdout `before\nafter\n`. GREEN: prints
// `before\n` to stdout and `panic: boom\n` to stderr, then pal_trap() fires;
// rc != 0.
const std = @import("std");

pub fn main() void {
    std.io.writeStr("before\n");
    @panic("boom");
    std.io.writeStr("after\n");
}
