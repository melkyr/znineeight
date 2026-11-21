// typealias_opt_xmod — RED->GREEN (A9F-b). An optional type alias
// (`const O = ?i32`) held in a `const` alias target (in-module and
// cross-module `pub`), used in annotation, parameter and return positions.
//
// RED baseline (A9I `parser.zig:391-446`): `parserParsePrimary` has no
// `?` case, so `const O = ?i32;` fails with `error[2000]`.
// GREEN: the alias registers/resolves to `?i32`; compile/link/run clean,
// prints 42\n8\n7\n.
const lib = @import("mod_b.zig");
const std = @import("std");

const O = ?i32;

fn pick(x: i32) O {
    if (x < 0) return null;
    return x;
}

pub fn main() void {
    var a: O = pick(42);
    var v: i32 = a orelse 0;
    std.io.printInt(v);
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(O)));
    std.io.writeByte('\n');
    var b: lib.O = lib.pick(7);
    var w: i32 = b orelse 0;
    std.io.printInt(w);
    std.io.writeByte('\n');
}
