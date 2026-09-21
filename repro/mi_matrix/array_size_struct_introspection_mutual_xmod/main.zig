// array_size_struct_introspection_mutual_xmod — Task 11H negative control:
// MUTUAL/CYCLIC aggregates in an array-size position must stay a clean
// `error[3050]`, never a silent wrong dimension and never an ICE / unbounded
// recursion.
//
// `A` refers to `B` and `B`'s array size refers back to `A`, so `layoutEnsure`
// recurses A -> B -> A ... until the depth cap (16, mirroring
// `resolveTypeExprFull`) returns false. The fold does not run and the
// array-size fallback emits the documented hard error.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
const A = struct { b: *B, x: [@sizeOf(B)]u8 };
const B = struct { a: *A, y: [@sizeOf(A)]u8 };

pub fn main() void {
    var a: A = undefined;
    _ = a;
}
