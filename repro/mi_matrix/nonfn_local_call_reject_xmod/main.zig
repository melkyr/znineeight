// nonfn_local_call_reject_xmod — Task 6D regression fixture.
//
// Pins that the callability gap is GENERAL, not nested-module-specific: a local
// `const` of a non-function type called as a function is invalid Zig.
//
// DEFECT (before the fix): rc=0, no diagnostic, emitted `(void)x();` (gcc:
// called object 'x' is not a function or function pointer).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[3056]`.
pub fn main() void {
    const x: u32 = 5;
    x();
}
