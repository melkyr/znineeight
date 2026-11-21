// undef_ident_xmod_reject_xmod — imported module holding the undeclared
// identifier. `nope()` on line 2 must clean-reject with `error[20]` and a
// precise `lib.zig:2:5` span. See `main.zig`.
pub fn go() void {
    nope();
}
