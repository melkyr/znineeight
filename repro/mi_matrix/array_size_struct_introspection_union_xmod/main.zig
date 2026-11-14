// array_size_struct_introspection_union_xmod — Task 11H negative control: a
// UNION type in an array-size position must stay a clean `error[3050]`.
//
// The Task 11H fold completes only `struct_type` on demand (unions/tagged/
// packed unions/tuples/optionals/error unions are deferred, matching the 11G
// investigation's safe default), so the union introspection never folds.
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
const U = union { a: u32, b: u64 };

var g: [@sizeOf(U)]u8 = undefined;

pub fn main() void {
    _ = g;
}
