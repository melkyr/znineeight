// m4_array_to_slice_len_xmod — M4 positive pin (array -> slice REAL length).
//
// Track4 S23 I. `sf/src/lower.zig:6627` `applyCoercion`'s `array_to_slice` arm
// initializes `var arr_len: u32 = 1;` and only overwrites it when the coerced
// node's resolved type is a pointer-to-array or an array. The `1` is the
// "no length source" default.
//
// Task 0i reachability verdict: UNREACHABLE. A marker instrumented at the
// default branch (compiler `4089cf7c`) fired 0 times across all 641 corpus dirs,
// 0 times in a targeted stress probe (direct var-decl, struct field, if-expr,
// call-arg, return), and 0 times in the compiler's own `sf/src` self-compile
// (48 `.c`). Reason: `classifyCoercion` only returns `array_to_slice` for an
// array / pointer-to-array source, and `applyCoercion` reads that same node's
// resolved type, so the lookup hits in every live path.
//
// This fixture is the positive pin: array -> slice in several positions must
// carry the REAL length (5), not the `arr_len=1` default. If the default ever
// becomes reachable this fixture panics / mismatches.
//
// Corpus class: OK (dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `hello|5`).
const std = @import("std");

const A = struct { s: []const u8 };

fn take(s: []const u8) usize {
    return s.len;
}

pub fn main() void {
    var a: [5]u8 = undefined;
    a[0] = 104;
    a[1] = 101;
    a[2] = 108;
    a[3] = 108;
    a[4] = 111;

    var s: []const u8 = a;
    if (s.len != 5) { @panic("m4_array_to_slice_len_xmod: var-decl len != 5 (arr_len default?)"); }

    var st = A{ .s = a };
    if (st.s.len != 5) { @panic("m4_array_to_slice_len_xmod: field-init len != 5 (arr_len default?)"); }

    var s2: []const u8 = if (true) a else a;
    if (s2.len != 5) { @panic("m4_array_to_slice_len_xmod: if-expr len != 5 (arr_len default?)"); }

    var n: usize = take(a);
    if (n != 5) { @panic("m4_array_to_slice_len_xmod: call-arg len != 5 (arr_len default?)"); }

    std.io.write(s);
    std.io.writeByte('|');
    std.io.printInt(@intCast(i32, s.len));
    std.io.writeByte('\n');
}
