// stdout_order_ok — Phase 3.5 D8 repro.
//
// Mixed stdout stack: `std.io.print` routes through `std.fmt` -> PAL
// (`pal_print_stdout`, unbuffered), while the `@stdoutWrite` / `@putChar`
// builtins currently emit C stdio (`fwrite` / `putchar`, buffered). Program
// order is A, B, C, then the echo of the byte read by `@getChar`.
//
// Pre-fix this may pass by luck on a normal exit (the buffered data flushes at
// exit after the unbuffered PAL write). The ordering value is proven post-fix
// on BOTH the CRT and the no-CRT builds.
//
// GREEN (post-fix) contract: stdout `A\nB\nC\nDZ\n`, rc 0, with stdin `Z\n`.
const std = @import("std");

pub fn main() void {
    std.io.print("A\n");
    @stdoutWrite("B\n", 2);
    @putChar(@intCast(u8, 'C'));
    @putChar(@intCast(u8, '\n'));
    const c = @getChar();
    @putChar(@intCast(u8, 'D'));
    @putChar(c);
    @putChar(@intCast(u8, '\n'));
}
