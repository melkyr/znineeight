// manyptr_len_reject_xmod — Task 11S (b) negative control.
//
// DEFECT: `semanticAnalyzerResolveFieldAccess` auto-derefs both `*T` and `[*]T`
// and the final fallback returns TYPE_VOID with no diagnostic for an
// unrecognized field. `p: [*]u8; p.len` therefore resolved to TYPE_VOID: in a
// `for (0..p.len)` range end the lowerer allocated a void-typed temp that C89
// never declared (gcc `'zT_N' undeclared`), and a plain `const n = p.len` hit
// the downstream "cannot declare variable of type void". `[*]T` has no `.len`
// in Z98 or official Zig.
//
// FIX (Task 11S): the many-ptr branch of `semanticAnalyzerResolveFieldAccess`
// now emits error[3000] when `.len` is accessed on a many-item pointer, in any
// position.
//
// Contract: dump rc=2, 0 `.c`, `error[3000]` (GREEN clean-reject bucket).
const S = struct { p: [*]u8 };

pub fn main() void {
    var buf: [4]u8 = undefined;
    var p: [*]u8 = &buf;
    var c: u32 = 0;
    for (0..p.len) |i| { _ = i; c += 1; }
    var s: S = undefined;
    s.p = &buf;
    for (0..s.p.len) |i| { _ = i; c += 1; }
    const n = p.len;
    _ = n;
    _ = c;
}
