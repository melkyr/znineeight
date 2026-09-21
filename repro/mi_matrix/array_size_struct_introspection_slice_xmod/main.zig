// array_size_struct_introspection_slice_xmod — Task 11H negative control: a
// SLICE type in an array-size position must stay a clean `error[3050]`.
//
// `evalConstScalarKind` excludes `slice_type` and the Task 11H fold only
// completes `struct_type` on demand, so the slice introspection never folds.
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
var g: [@sizeOf([]u8)]u8 = undefined;

pub fn main() void {
    _ = g;
}
