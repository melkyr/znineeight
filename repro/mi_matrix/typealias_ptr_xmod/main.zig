// typealias_ptr_xmod — RED->GREEN (A9F-b). A pointer type alias
// (`const P = *u8`) held in a `const` alias target (in-module and
// cross-module `pub`), used in annotation, parameter and return positions.
//
// RED baseline (A9I `parser.zig:391-446`): `parserParsePrimary` has no `*`
// case, so `const P = *u8;` fails with `error[2000]` before registration.
// GREEN: the alias registers/resolves to `*u8` via the A9F-a ident/symbol
// path; compile/link/run clean, prints 42\n4\n41\n.
const lib = @import("mod_b.zig");
const std = @import("std");

const P = *u8;

fn bump(p: P) u8 {
    return p.* + 1;
}

pub fn main() void {
    var b: u8 = 41;
    var p: P = &b;
    std.io.printInt(@intCast(i32, bump(p)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(P)));
    std.io.writeByte('\n');
    var q: lib.P = &b;
    std.io.printInt(@intCast(i32, lib.deref(q)));
    std.io.writeByte('\n');
}
