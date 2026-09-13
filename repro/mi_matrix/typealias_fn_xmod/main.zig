// typealias_fn_xmod — RED->GREEN (A9F-b). A function type alias
// (`const F = fn(i32) i32`, which resolves to a pointer-to-function type)
// held in a `const` alias target (in-module and cross-module `pub`), used in
// annotation and parameter positions.
//
// RED baseline (A9I `parser.zig:391-446`): `parserParsePrimary` has no `fn`
// case, so `const F = fn(i32) i32;` fails with `error[2000]`.
// GREEN: the alias registers/resolves to `*fn(i32)i32`; compile/link/run
// clean, prints 42\n4\n7\n.
const lib = @import("mod_b.zig");
const std = @import("std");

const F = fn(i32) i32;

fn addone(x: i32) i32 {
    return x + 1;
}

fn apply(f: F, x: i32) i32 {
    return f(x);
}

pub fn main() void {
    var f: F = addone;
    std.io.printInt(apply(f, 41));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(F)));
    std.io.writeByte('\n');
    var g: lib.F = lib.addone;
    std.io.printInt(g(6));
    std.io.writeByte('\n');
}
