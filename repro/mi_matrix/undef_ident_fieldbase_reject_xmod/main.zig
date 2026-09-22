// undef_ident_fieldbase_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a FIELD-ACCESS BASE (`nope.foo()`). Baseline
// already diagnosed this ONCE via `semanticAnalyzerResolveFieldAccess`'s own
// `error[3001]` fallback. Variant S adds a second diagnostic at the base
// `semanticAnalyzerResolveIdent`, so Task 6F's companion DEDUP drops the
// field-access emission and keeps the branch's early return.
//
// This fixture PINS the dedup: exactly ONE `error[20]` must be emitted (a
// regression would print two identical diagnostics).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, exactly one `error[20]` at
// main.zig:15:4.
pub fn main() void {
    nope.foo();
}
