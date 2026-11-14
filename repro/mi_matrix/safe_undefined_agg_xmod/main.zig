// safe_undefined_agg_xmod — A17 aggregate `undefined` poison (C89AHEAD).
//
// `var s: S = undefined` routes through lowering's undefined-init branch. Under
// `-fsafe` the storage is 0xAA-filled (A17 `poison_init`, previously the
// emitter's `.undefined_const` safe branch); under `-ffast` the historical
// deterministic zeroing is kept (the aggregate `undefined_const` zero path).
// Reading the two unwritten i32 fields observes the difference:
// `-fsafe` `-1431655766 -1431655766\n`; `-ffast` `0 0\n`.
const std = @import("std");

const S = struct { a: i32, b: i32 };

pub fn main() void {
    var s: S = undefined;
    std.io.printInt(s.a);
    std.io.writeByte(' ');
    std.io.printInt(s.b);
    std.io.writeByte('\n');
}
