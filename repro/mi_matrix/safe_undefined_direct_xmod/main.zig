// safe_undefined_direct_xmod — A17 `undefined` poison via backend-neutral LIR (C89AHEAD).
//
// Direct `undefined` expression (`AstKind.undefined_literal` in lowering, the
// emitter's old `.undefined_const` safe branch) plus the hoisted-temp poison net
// (the call-result temp `zT_*` is statically-unwritten from the net's point of
// view and is poisoned under `-fsafe`). Under `-fsafe` the read observes the
// byte-exact 0xAA fill: 0xAAAAAAAA as a signed i32 is -1431655766. Under
// `-ffast` the historical deterministic zeroing is kept and the same program
// prints 0. A17 moves the mode decision out of the emitter into lowering
// (`poison_init`) / the `LirFunction.poison_uninit` flag, but the observable
// bytes must stay PRE==POST in both modes.
//
// Observable: stdout. `-fsafe` `-1431655766\n`; `-ffast` `0\n`.
const std = @import("std");

fn get() i32 {
    return undefined;
}

pub fn main() void {
    std.io.printInt(get());
    std.io.writeByte('\n');
}
