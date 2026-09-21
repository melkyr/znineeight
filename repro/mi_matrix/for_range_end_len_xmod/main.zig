// for_range_end_len_xmod — Task 11P pin for the `for (start..end)` range-operand
// resolution defect.
//
// DEFECT (before the fix). `semanticAnalyzerResolveExpr`'s `range_exclusive` /
// `range_inclusive` arm (sf/src/semantic_analyzer.zig) typed the range node as
// `u32` and returned WITHOUT resolving `child_0` (start) or `child_1` (end), so
// neither operand received a resolved-type entry. The lowerer lowers the range
// operands directly (lower.zig `for_stmt`), and any operand whose lowering
// consults the resolved-type table — concretely `.len` on a struct/union ARRAY
// or SLICE field (`s.a.len`, via `fieldStaticLenForBase`) — found no entry and
// fell through to an unassigned temp. Under `-ffast` that temp is zero, so
// `for (0..s.a.len)` silently iterated 0 times. The loop capture itself was
// fine (the range node was typed); only the END value was wrong. The START form
// (`for (s.a.len..N)`) failed harder (pointer-typed temp -> gcc error).
//
// FIX (Task 11P, one edit in sf/src/semantic_analyzer.zig). The range arm now
// resolves `child_0`, and `child_1` when present, before returning the range
// type. No lowerer change is needed: the existing Task 11N `.len` machinery
// then fires for the operands. The fix repairs BOTH the end (silent 0) and the
// start forms.
//
// SCOPE. The range capture stays `u32` (the spec's `usize` is a pre-existing,
// out-of-scope divergence). `for (0..p.len)` on a `[*]T` is now cleanly
// rejected (correct Zig) rather than silently lowered — the 11O review flagged
// this behavior change for the classifier join-diff.
//
// EXPECTED after the fix (deterministic one-line stdout, RUNRC=0). Before the
// fix this fixture compiled but `@panic`ed at runtime (the struct/slice-field
// counts were 0):
//
//   field_len=4 slice_field_len=4 nested=4 global=4 byval=4 byptr=4 local_arr=4 var=4 xy=4 sizeof=8
//   for_range_end ok
//
// The `@panic` below is the runtime guard against the silent-`0` miscompile
// (the compile-only corpus classifier cannot see it).
const std = @import("std");

const S = struct { a: [4]u8 };
const Sl = struct { a: []u8 };
const N = struct { inner: S, b: u8 };
const T = struct { x: u32, y: u32 };

var g_s: S = undefined;

fn countByVal(s: S) u32 {
    var c: u32 = 0;
    for (0..s.a.len) |i| { _ = i; c += 1; }
    return c;
}

fn countByPtr(s: *S) u32 {
    var c: u32 = 0;
    for (0..s.a.len) |i| { _ = i; c += 1; }
    return c;
}

pub fn main() void {
    var s: S = undefined;
    var nn: N = undefined;
    var buf: [8]u8 = undefined;
    var sl: Sl = undefined;
    sl.a = buf[0..4];

    var bad: u32 = 0;

    var c1: u32 = 0;
    for (0..s.a.len) |i| { _ = i; c1 += 1; }
    if (c1 != 4) bad += 1;

    var c2: u32 = 0;
    for (0..sl.a.len) |i| { _ = i; c2 += 1; }
    if (c2 != 4) bad += 1;

    var c3: u32 = 0;
    for (0..nn.inner.a.len) |i| { _ = i; c3 += 1; }
    if (c3 != 4) bad += 1;

    var c4: u32 = 0;
    for (0..g_s.a.len) |i| { _ = i; c4 += 1; }
    if (c4 != 4) bad += 1;

    if (countByVal(s) != 4) bad += 1;
    if (countByPtr(&s) != 4) bad += 1;

    var arr: [4]u8 = undefined;
    var c5: u32 = 0;
    for (0..arr.len) |i| { _ = i; c5 += 1; }
    if (c5 != 4) bad += 1;

    var n: u32 = 4;
    var c6: u32 = 0;
    for (0..n) |i| { _ = i; c6 += 1; }
    if (c6 != 4) bad += 1;

    var x: u32 = 1;
    var y: u32 = 5;
    var c7: u32 = 0;
    for (x..y) |i| { _ = i; c7 += 1; }
    if (c7 != 4) bad += 1;

    var c8: u32 = 0;
    for (0..@sizeOf(T)) |i| { _ = i; c8 += 1; }
    if (c8 != 8) bad += 1;

    std.io.write("field_len=");
    std.io.printInt(@intCast(i32, c1));
    std.io.write(" slice_field_len=");
    std.io.printInt(@intCast(i32, c2));
    std.io.write(" nested=");
    std.io.printInt(@intCast(i32, c3));
    std.io.write(" global=");
    std.io.printInt(@intCast(i32, c4));
    std.io.write(" byval=");
    std.io.printInt(@intCast(i32, countByVal(s)));
    std.io.write(" byptr=");
    std.io.printInt(@intCast(i32, countByPtr(&s)));
    std.io.write(" local_arr=");
    std.io.printInt(@intCast(i32, c5));
    std.io.write(" var=");
    std.io.printInt(@intCast(i32, c6));
    std.io.write(" xy=");
    std.io.printInt(@intCast(i32, c7));
    std.io.write(" sizeof=");
    std.io.printInt(@intCast(i32, c8));
    std.io.write("\n");

    if (bad != 0) @panic("for_range_end: wrong count");
    std.io.write("for_range_end ok\n");
}
