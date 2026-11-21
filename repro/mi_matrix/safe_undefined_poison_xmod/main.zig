// safe_undefined_poison_xmod — RED->GREEN `-fsafe`/`-ffast` fixture (A3F).
//
// `var x: i32 = undefined` is read before it is written. Under the default
// `-fsafe` mode the compiler poisons the storage with a byte-exact 0xAA fill
// (`zig_poison_fill`), so the read is observably wrong: 0xAAAAAAAA as a signed
// i32 is -1431655766. Under `-ffast` the historical deterministic zeroing is
// kept, so the same program prints 0. Before A3F (and under `-ffast`) the
// program printed a plausible 0 with no indication the value was undefined.
//
// Observable: stdout. RED (pre-A3F / `-ffast`) `0\n`; GREEN (default `-fsafe`)
// `-1431655766\n`.
const std = @import("std");

fn readUndefined() i32 {
    var x: i32 = undefined;
    return x;
}

pub fn main() void {
    std.io.printInt(readUndefined());
    std.io.writeStr("\n");
}
