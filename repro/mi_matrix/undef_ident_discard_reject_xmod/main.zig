// undef_ident_discard_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as the RHS of a discard `_ = nope;`. Before the
// fix it resolved silently to `TYPE_VOID`, compiled rc=0, and emitted
// `zT_0 = nope;` (gcc: `zT_0`/`nope` undeclared).
//
// NOTE: the bare `_` placeholder itself (`name_id == _stub_0`) stays silent by
// design; this fixture uses an actual undeclared NAME.
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:12:8.
pub fn main() void {
    _ = nope;
}
