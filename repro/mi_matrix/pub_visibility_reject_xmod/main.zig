// pub_visibility_reject_xmod — Task 15 (S3) cross-module `pub` visibility reject.
//
// DEFECT (before the fix): a non-`pub` function was callable from an importing
// module (`helper.secret(21)` compiled rc=0, built, ran, printed 21), and the
// asymmetric shapes were accepted too (non-`pub` const read folded silently,
// non-`pub` type annotation, non-`pub` var store, nested `mod.sub.member`,
// direct `@import("x.zig").member`). Official Zig 0.15.2 rejects every one
// with `error: '<name>' is not marked 'pub'` (see the fixture sites below).
//
// FIX (Task 15): `ERR_3007_VISIBILITY_VIOLATION` is emitted for a cross-module
// reference to a non-`pub` declaration in both expression and type positions;
// same-module access is unchanged (see stdlib_pub_visibility_ok_xmod).
//
// Sites (each independently Zig-0.15.2-rejected):
//   * `helper.secret(21)`                     flat non-pub fn call
//   * `helper.hidden_const`                   flat non-pub const read
//   * `helper.HiddenAlias`                    flat non-pub type annotation
//   * `helper.hidden_var = 4`                 flat non-pub var store
//   * `helper.inner.secret2(21)`              nested non-pub fn call
//   * `helper.inner.hidden_const2`            nested non-pub const read
//   * `@import("helper.zig").secret(21)`      direct-import non-pub fn call
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3007]` per site (7 total);
// no `error[3000]`, so this dir buckets as FAIL under the corpus classifier.
// The controls live in `stdlib_pub_visibility_ok_xmod` and the standalone
// `repro/pub_visibility.z98`.
const helper = @import("helper.zig");

pub fn main() void {
    var a: i32 = helper.secret(21);
    var b: i32 = helper.hidden_const;
    var c: helper.HiddenAlias = 3;
    helper.hidden_var = 4;
    var d: i32 = helper.inner.secret2(21);
    var e: i32 = helper.inner.hidden_const2;
    var f: i32 = @import("helper.zig").secret(21);
    _ = a;
    _ = b;
    _ = c;
    _ = d;
    _ = e;
    _ = f;
}
