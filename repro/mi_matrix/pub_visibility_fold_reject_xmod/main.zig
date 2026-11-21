// pub_visibility_fold_reject_xmod — Task 15 (S3) const-fold visibility reject.
//
// DEFECT (before fix round 1): the type-resolver's const-fold field-access path
// (`evalConstIntFull`, entered via `evalConstU32Full` for array sizes and
// `evalConstI64Full` for enum member values) resolved a cross-module const with
// no visibility check, so a non-`pub` const folded happily:
//   * `var arr: [helper.hidden_const]u8 = undefined;` compiled rc=0 and emitted
//     the array with the folded length 5;
//   * `const E = enum(u8) { A = helper.hidden_const, B };` compiled rc=0.
// Official Zig 0.15.2 rejects every one with `'hidden_const' is not marked
// 'pub'`. This fixture is separate from `pub_visibility_reject_xmod` because a
// type-resolution diagnostic short-circuits the pipeline before semantic
// analysis (`main.zig` prints + exits after `phase_TypeResolution`), so fold
// sites and expression sites cannot be pinned in one program.
//
// FIX (fix round 1): the fold arm gates the module lookup with
// `typeResolverCheckMemberVisibility` before using the symbol, emitting the
// same level-0 `error[3007]` and declining the fold.
//
// Sites (each independently Zig-0.15.2-rejected):
//   * `[helper.hidden_const]u8`                    flat non-pub array size
//   * `enum(u8){ A = helper.hidden_const, B }`     flat non-pub enum initializer
//   * `[helper.inner.hidden_const2]u8`             nested non-pub array size
//   * `enum(u8){ A = helper.inner.hidden_const2 }` nested non-pub enum init
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3007]` per site (4 total),
// plus the declined-fold cascades `error[3050]` (2x) and `error[3055]` (2x);
// no `error[3000]`, so this dir buckets as FAIL under the corpus classifier.
// The positive fold controls live in `stdlib_pub_visibility_ok_xmod` and the
// standalone `repro/pub_visibility_fold.z98` / `repro/pub_visibility_ok.z98`.
const helper = @import("helper.zig");

var folded_arr: [helper.hidden_const]u8 = undefined;
const FoldedEnum = enum(u8) {
    A = helper.hidden_const,
    B,
};
var folded_nested_arr: [helper.inner.hidden_const2]u8 = undefined;
const FoldedNestedEnum = enum(u8) {
    A = helper.inner.hidden_const2,
    B,
};

pub fn main() void {
    if (folded_arr.len != 5) {
        @panic("flat folded array length");
    }
    var fe: FoldedEnum = FoldedEnum.B;
    if (@enumToInt(fe) != 6) {
        @panic("flat folded enum value");
    }
    if (folded_nested_arr.len != 6) {
        @panic("nested folded array length");
    }
    var fne: FoldedNestedEnum = FoldedNestedEnum.B;
    if (@enumToInt(fne) != 7) {
        @panic("nested folded enum value");
    }
}
