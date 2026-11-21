// array_size_struct_introspection_fwd_xmod — Task 11H negative control: a
// FORWARD-REFERENCED aggregate in an array-size position must stay a clean
// `error[3050]`, never a silently wrong dimension.
//
// `T` is defined before `S`, so when T's field types are resolved, `S` is not
// yet complete and T's field type is left at the `TYPE_VOID` registration
// placeholder. `layoutEnsure` treats `TYPE_VOID` as incomplete and defers, so
// the fold does not run and the array-size fallback emits the documented hard
// error. (Treating the placeholder as a real zero-size void field is exactly
// what produced the silent `[1]` hazard.)
//
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
const T = struct { data: [@sizeOf(S)]u8 };
const S = struct { a: u32, b: u64 };

pub fn main() void {
    var t: T = undefined;
    _ = t;
}
