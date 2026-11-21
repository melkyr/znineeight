// safe_int_mixed_sign_xmod — `-fsafe` mixed-sign false-positive CONTROL (A6F).
//
// `i32 MIN + u32 1` resolves to i32 (same-width mixed sign keeps the LHS type)
// and is representable: MIN + 1 = -2147483647. The regular `+` path emits raw,
// uncast operands, so a naive signed guard run under C's usual arithmetic
// conversions would promote to unsigned and falsely trap. A6F must cast both
// operands to the result type before comparing.
//
// Expected under `-fsafe`, `-ffast`, and PRE: rc 0, `-2147483647`.
const std = @import("std");

pub fn main() void {
    var a: i32 = -2147483647 - 1;
    var b: u32 = 1;
    var r: i32 = a + b;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
