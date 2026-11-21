// typealias_pub_arr_xmod — RED->GREEN (A9F-a). A cross-module `pub const
// T = [3]i32` used as the declared type of a local and as a param type.
//
// RED baseline (A9I `7a9a9081`): the imported alias's `sym.type_id` stays 0,
// so `lib.T` resolves to nothing: the imported module is not reached and the
// generated element copy loop references a phantom `x`/`a` (`gcc: 'a'
// undeclared`) with NO diagnostic — the A7F/A19 silent-bad-C class.
// GREEN: `lib.T` resolves to `[3]i32`; compile/link/run clean, prints 6\n.
// Fix (A9F-a): `typeResolverResolveNames.resolveNamedTypeExpressions` writes the
// resolved named type back to the alias symbol (`sym.type_id`).
const lib = @import("mod_b.zig");
const std = @import("std");

pub fn main() void {
    var a: lib.T = [_]i32{ 1, 2, 3 };
    std.io.printInt(lib.sum(a));
    std.io.writeByte('\n');
}
