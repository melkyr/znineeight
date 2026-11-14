// trap_panic_xmod — RED->GREEN trap fixture (A2F). `@panic(msg)` is retyped
// `noreturn`: it evaluates and prints the argument, then traps via pal_trap().
//
// RED (seed v9): `@panic` is a no-op (payload/side effects dropped); execution
// continues to "after", rc 0, stdout `before\nafter\n`. GREEN: writes
// `panic: boom\n` to stderr, then pal_trap() fires before the stdout block
// buffer is flushed; stdout empty, rc 133 (SIGTRAP) — the observable is
// rc/stderr, not stdout.
const std = @import("std");

pub fn main() void {
    std.io.writeStr("before\n");
    @panic("boom");
    std.io.writeStr("after\n");
}
