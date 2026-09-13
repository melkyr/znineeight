// typealias_eu_xmod — RED->GREEN (A9F-b). An error-union type alias
// (`const E = error{Bad}!i32`) held in a `const` alias target (in-module and
// cross-module `pub`), used in annotation, parameter and return positions.
//
// RED baseline (A9I `parser.zig:391-446`: `kw_error` is routed to the error
// *literal*, so a following `!` fails), thus `const E = error{Bad}!i32;` fails
// with `error[2000]`.
// GREEN: the alias registers/resolves to the error-union type; compile/link/
// run clean, prints 42\n8\n7\n.
const lib = @import("mod_b.zig");
const std = @import("std");

const E = error{Bad}!i32;

fn eu(x: i32) E {
    if (x < 0) return error.Bad;
    return x;
}

pub fn main() void {
    var a: E = eu(42);
    var v: i32 = a catch 0;
    std.io.printInt(v);
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(E)));
    std.io.writeByte('\n');
    var b: lib.E = lib.eu(7);
    var w: i32 = b catch 0;
    std.io.printInt(w);
    std.io.writeByte('\n');
}
