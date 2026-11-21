// len_array_field_xmod — Task 11N pin for `.len` on a struct/union array field.
//
// DEFECT (before the fix). `semanticAnalyzerResolveFieldAccess` decays every
// struct/union field whose declared type is an array `[N]T` to a bare element
// pointer `*T`, discarding the length. So `s.a` resolves to `*u8`, `.len` on
// `*u8` matches neither the array-`.len` arm nor the struct/slice arms, and the
// final fallback returns `void`. Depending on the consuming position this
// surfaces as a front-end `error[3000] cannot declare variable of type void`
// (untyped `const n = s.a.len`), as gcc `'zT_N' undeclared` (comparison /
// global), or — worst — as a SILENT `0` (return / call-argument positions).
// The array-field decay is deliberately PRESERVED (it is load-bearing for
// `s.arr[i]` / A5F bounds checks); the fix recovers the declared length.
//
// FIX (Task 11N, two coordinated edits). `semantic_analyzer.zig` gains
// `semanticAnalyzerArrayFieldLen` (wired into the final fallback) so `.len` on
// an array field resolves to `usize`; `lower.zig` intercepts `.len` whose base
// is a field access with a declared array field and emits the compile-time
// `int_const` length.
//
// SCOPE NOTE. `for (0..s.a.len)` remains broken after this fix (the for-range
// end is not resolved by the semantic analyzer — a separate defect). This pin
// deliberately avoids that position and indexes/compares instead.
//
// EXPECTED after the fix (deterministic stdout, RUNRC=0). Before the fix this
// fixture failed to compile at all (the local untyped `const n`).
//
//   local=4
//   byval=4
//   byptr=4
//   global=4
//   union=4
//   nested=4
//   len_array_field ok
//
// The `@panic` below is the runtime guard against the silent-`0` miscompile in
// the by-value / pointer / union / nested return positions (the compile-only
// corpus classifier cannot see that regression).
const std = @import("std");

const S = struct { a: [4]u8 };
const N = struct { inner: S, b: u8 };
const U = union { a: [4]u8, b: u32 };

var g_s: S = undefined;

fn byval(s: S) usize {
    return s.a.len;
}

fn byptr(s: *S) usize {
    return s.a.len;
}

fn nested(n: N) usize {
    return n.inner.a.len;
}

fn ulen(u: U) usize {
    return u.a.len;
}

pub fn main() void {
    var s: S = undefined;
    var u: U = undefined;
    var nn: N = undefined;

    const n = s.a.len;

    std.io.write("local=");
    std.io.printInt(@intCast(i32, n));
    std.io.write("\n");
    std.io.write("byval=");
    std.io.printInt(@intCast(i32, byval(s)));
    std.io.write("\n");
    std.io.write("byptr=");
    std.io.printInt(@intCast(i32, byptr(&s)));
    std.io.write("\n");
    std.io.write("global=");
    std.io.printInt(@intCast(i32, g_s.a.len));
    std.io.write("\n");
    std.io.write("union=");
    std.io.printInt(@intCast(i32, ulen(u)));
    std.io.write("\n");
    std.io.write("nested=");
    std.io.printInt(@intCast(i32, nested(nn)));
    std.io.write("\n");

    var bad: u32 = 0;
    if (n != 4) bad += 1;
    if (byval(s) != 4) bad += 1;
    if (byptr(&s) != 4) bad += 1;
    if (g_s.a.len != 4) bad += 1;
    if (ulen(u) != 4) bad += 1;
    if (nested(nn) != 4) bad += 1;
    if (bad != 0) @panic("len_array_field: wrong length");

    std.io.write("len_array_field ok\n");
}
