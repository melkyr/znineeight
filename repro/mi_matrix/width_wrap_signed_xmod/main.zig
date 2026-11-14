// width_wrap_signed_xmod — A18 signed arbitrary-width normalization pin.
//
// `i3` 3 `+%` 1 wraps to -4; the backend-neutral `width_wrap` LIR op emitted by
// lowering normalizes the result with the signed mask/sign-extend form
// `(signed char)(((v & 7) ^ 4) - 4)` (the former emitter-side
// `emitWidthWrapStmt`), so both modes print `-4 3` (rc 0). Complements the
// unsigned intwidth_wrap_xmod/intwidth_full_xmod fixtures.
const std = @import("std");

pub fn main() void {
    var a: i3 = @intCast(i3, 3);
    var b: i3 = @intCast(i3, 1);
    var w = a +% b;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte(32);
    var x: i3 = @intCast(i3, -3);
    var y: i3 = @intCast(i3, -2);
    var w2 = x +% y;
    std.io.printInt(@intCast(i32, w2));
    std.io.writeByte(10);
}
