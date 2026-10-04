// optional_void_present_xmod — A4 regression: a valueless `?void` return is
// PRESENT, not absent.
//
// DEFECT (fp 2794fe0): `emitValuelessReturn` (`sf/src/lower.zig`) handled
// `error_union` present construction but not `optional`, so `return;` (and
// fall-off) in a `?void` function lowered to `.ret_void`, which
// `c89_emit.zig` materialised as `zT_ret_void = {0}` -> has_value = 0 (absent).
//
// FIX (A4-F): add the optional(void) present branch to `emitValuelessReturn`
// (wrap_optional -> has_value = 1), symmetric to the existing error-union
// branch.
//
// GREEN contract: rc 0 and stdout `present\nabsent\npresent\npresent\nabsent`
// (Zig 0.15.2 oracle). Baseline prints line 1 and 3 as `absent`.
const std = @import("std");
fn done(flag: bool) ?void {
    if (flag) { return; }
    return null;
}
fn fall(flag: bool) ?void {
    if (flag) { return; }
}
fn take(x: ?void) void {
    if (x) |_| { std.io.print("present\n"); } else { std.io.print("absent\n"); }
}
pub fn main() void {
    if (done(true)) |_| { std.io.print("present\n"); } else { std.io.print("absent\n"); }
    take(done(false));
    take(fall(false));
    take({});
    take(null);
}
