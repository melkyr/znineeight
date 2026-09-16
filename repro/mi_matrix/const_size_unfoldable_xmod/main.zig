// const_size_unfoldable_xmod — a NON-FOLDABLE array size (a runtime mutable
// value), which must be a HARD ERROR, never silent invalid C.
//
// `var N: usize = 4;` is a mutable runtime global, so `[N]u8` cannot be
// const-folded. Today the compiler resolves the size to 0xFFFFFFFF, leaves
// `arr_resolved` false, returns `TYPE_UNDEFINED`, and emits NO diagnostic:
//
// RED today (Task 2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b):
//   dump rc=0, 4 `.c`, stderr empty — SILENT.
//   The module global degrades to a scalar `int zG_..._g;` and the emitted C is
//   invalid; gcc then fails:
//     error: subscripted value is neither array nor pointer nor vector
//     error: 'zT_4' undeclared (first use in this function)
//   (corpus classifier FAIL: gcc exit nonzero).
// The same shape as a function-local array (`var x: [N]u8`) also mis-resolves;
// with a later use it reports `error[20]` instead of a meaningful diagnostic.
//
// Expected GREEN contract (Task 2c-F): a hard frontend error
// `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` (explicit numeric 3050 per
// `sf/src/diagnostics.zig`), dump rc=2, 0 `.c`. Never silent invalid C.
//
// Fix locus: after the fold attempt in the `array_type` arm
// (`sf/src/type_resolver.zig:1109-1173`), when `arr_resolved` is still false,
// emit the new hard error. `TypeResolveEnv` has no diagnostics handle
// (`:26-33`), so either emit it in sema (where `self.diag` exists) or thread
// the handle into `TypeResolveEnv`. See report Q4.
var N: usize = 4;

var g: [N]u8 = undefined;

pub fn main() void {
    g[0] = 1;
    if (g.len != 4) {
        @panic("const_size_unfoldable_xmod: unexpected");
    }
}
