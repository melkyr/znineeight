// const_size_unfoldable_xmod — a NON-FOLDABLE array size (a runtime mutable
// value), which must be a HARD ERROR, never silent invalid C.
//
// `var N: usize = 4;` is a mutable runtime global, so `[N]u8` cannot be
// const-folded. At the Task-2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b
// the compiler resolved the size to 0xFFFFFFFF, left `arr_resolved` false,
// returned `TYPE_UNDEFINED`, and emitted NO diagnostic:
//   dump rc=0, 4 `.c`, stderr empty — SILENT.
//   The module global degraded to a scalar `int zG_..._g;` and the emitted C
//   was invalid; gcc then failed:
//     error: subscripted value is neither array nor pointer nor vector
//     error: 'zT_4' undeclared (first use in this function)
//
// GREEN (Task 2c-F): a hard frontend error `ERR_3050_ARRAY_SIZE_NOT_CONSTANT`
// is emitted from the `array_type` arm when `arr_resolved` is false (deduped
// per node). Fix round 1 additionally threads a real source file id into the
// diagnostic, so it is located:
//   repro/mi_matrix/const_size_unfoldable_xmod/main.zig:24:8: error[3050]:
//     array size is not a constant expression
// (column 8 = the `[N]u8` size expression); dump rc=2, 0 `.c`. Never silent
// invalid C.
var N: usize = 4;

var g: [N]u8 = undefined;

pub fn main() void {
    g[0] = 1;
    if (g.len != 4) {
        @panic("const_size_unfoldable_xmod: unexpected");
    }
}
