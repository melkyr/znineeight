// manyptr_len_reject_xmod — Task 11S (b) negative control (silent-lowering shape).
//
// DEFECT: `semanticAnalyzerResolveFieldAccess` auto-derefs both `*T` and `[*]T`
// and the final fallback returns TYPE_VOID with no diagnostic for an
// unrecognized field. `p: [*]u8; p.len` therefore resolved to TYPE_VOID. In a
// return position the lowerer consumed the void temp without declaring it, so
// the BASELINE compiler accepted this file (dump rc=0, gcc clean, OK) and
// silently returned a wrong value; `[*]T` has no `.len` in Z98 or official Zig.
//
// FIX (Task 11S): the many-ptr branch of `semanticAnalyzerResolveFieldAccess`
// now emits error[3000] when `.len` is accessed on a many-item pointer, in any
// position.
//
// CONTRACT: this fixture is **OK under the baseline compiler** (silent
// acceptance) and **GREEN only with the fix** (dump rc=2, 0 `.c`,
// `error[3000]`) — i.e. it moves OK→GREEN in the corpus join-diff. The
// `for (0..p.len)` range shape (a gcc-class FAIL under the baseline) is pinned
// separately by `manyptr_len_range_reject_xmod`.
const S = struct { p: [*]u8 };

fn localLen(p: [*]u8) u32 {
    return p.len;
}

fn fieldLen(s: S) u32 {
    return s.p.len;
}

pub fn main() void {
    var buf: [4]u8 = undefined;
    var p: [*]u8 = &buf;
    var s: S = undefined;
    s.p = &buf;
    var c: u32 = localLen(p) + fieldLen(s);
    _ = c;
}
