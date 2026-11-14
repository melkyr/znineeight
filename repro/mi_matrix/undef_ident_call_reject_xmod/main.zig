// undef_ident_call_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a free-function callee is invalid Zig
// (official Zig: `use of undeclared identifier 'nope'`). Before the fix Z98's
// `semanticAnalyzerResolveIdent` fallback returned `TYPE_VOID` with NO
// diagnostic, so this compiled rc=0 and emitted uncompilable C
// (`zT_0 = nope; (void)zT_0();`).
//
// FIX (Task 6F, variant S): the `semanticAnalyzerResolveIdent` fallback now
// emits `error[3001]` (numeric code 20) with a precise `file:line:col` span for
// the undeclared identifier; the post-sema `hasErrors` gate exits rc=2 before
// lowering, so 0 `.c` are emitted.
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:16:4.
pub fn main() void {
    nope();
}
