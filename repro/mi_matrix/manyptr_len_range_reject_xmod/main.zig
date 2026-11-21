// manyptr_len_range_reject_xmod — Task 11S (b) negative control (range shape).
//
// DEFECT: `p: [*]u8; p.len` resolved to TYPE_VOID (the many-ptr branch of
// `semanticAnalyzerResolveFieldAccess` auto-derefs `[*]T` and the fallback has
// no diagnostic for an unrecognized field). In a `for (0..p.len)` range end the
// BASELINE compiler accepted the file (dump rc=0) but the lowerer emitted a
// void-typed temp that C89 never declared, so gcc failed (`'zT_N' undeclared`)
// — a FAIL, not a clean reject. `[*]T` has no `.len` in Z98 or official Zig.
//
// FIX (Task 11S): the many-ptr branch now emits error[3000] when `.len` is
// accessed on a many-item pointer, in any position.
//
// CONTRACT: FAIL under the baseline compiler (gcc-class) and GREEN only with
// the fix (dump rc=2, 0 `.c`, `error[3000]`) — it moves FAIL→GREEN in the
// corpus join-diff. The silent-lowering return shape (OK under the baseline)
// is pinned by `manyptr_len_reject_xmod`.
const S = struct { p: [*]u8 };

pub fn main() void {
    var buf: [4]u8 = undefined;
    var p: [*]u8 = &buf;
    var s: S = undefined;
    s.p = &buf;
    var c: u32 = 0;
    for (0..p.len) |i| { _ = i; c += 1; }
    for (0..s.p.len) |i| { _ = i; c += 1; }
    _ = c;
}
