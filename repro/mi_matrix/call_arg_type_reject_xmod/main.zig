// call_arg_type_reject_xmod — Task 14 (S2) argument-type reject fixture.
//
// DEFECT (before the fix): a wrong argument type built, linked and ran —
// `add(1, true)` printed `2` via a silent `bool` -> `i32` coercion (official
// Zig 0.15.2 rejects `expected type 'i32', found 'bool'`).
//
// FIX (Task 14): `semanticAnalyzerResolveFnCall` enforces per-argument
// assignability at the call site (`error[3000]`, the existing "type mismatch
// in function argument" diagnostic + source/target notes) for cross-family
// mismatches, on both the direct-call and the fn-value paths, so the program
// rejects with rc=2 and 0 emitted `.c`. Z98's established implicit integer and
// pointer conversions stay accepted (see `stdlib_call_arity_types_ok_xmod`).
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `add(1, true)`        bool for i32  (Zig: expected type 'i32', found
//                                          'bool')
//   * `takeBool(1)`         int for bool  (Zig: expected type 'bool', found
//                                          'comptime_int')
//   * `takeF(i)` (i: i32)   int for f32   (Zig: expected type 'f32', found
//                                          'i32')
//
// EXPECTED: dump rc=2, 0 `.c`, 3 x `error[3000]`; the `error[3000]`-only
// shape buckets as GREEN under the corpus classifier. The int->f32 site lives
// in a helper whose parameter is a runtime i32, matching the Zig oracle's
// runtime-`i32` probe (a comptime-known Zig i32 is coercible to f32 where
// Z98's runtime `var` is not — the strict direction).
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn takeBool(b: bool) bool {
    return b;
}

fn takeF(x: f32) f32 {
    return x;
}

fn passF(i: i32) f32 {
    return takeF(i);
}

pub fn main() void {
    var u: i32 = add(1, true);
    _ = u;
    var xb: bool = takeBool(1);
    _ = xb;
    var y: f32 = passF(5);
    _ = y;
}
