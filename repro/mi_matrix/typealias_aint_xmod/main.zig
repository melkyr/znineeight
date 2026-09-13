// typealias_aint_xmod — RED->GREEN (A9F-a review fix). Arbitrary-width
// integer aliases (`const T = u7` / `i5` / `u12` / `u33`) must register as
// usable types in annotation position.
//
// RED baseline (A9F-a fixed point `dcc89404`): `symbol_registrator`'s
// ident_expr branch only sets `type_alias` on a `nameCache` hit; lazily-built
// arbitrary-width names (`resolveTypeExprFull:801-805`) miss, so the alias
// stays a `global` with `type_id 0` and sema reports
// `error[3000]: cannot declare variable of type void`.
// GREEN: aliases resolve to their arb-int TypeId; compile/run clean.
// Fix (A9F-a review): resolve `uN`/`iN` in the ident_expr registration branch
// via `parseArbIntWidth` + `typeRegistryGetOrCreateArbInt`.
// Contract: compile-clean, run prints 5\n-3\n4000\n8\n.
const std = @import("std");

const U7 = u7;
const I5 = i5;
const U12 = u12;
const U33 = u33;

pub fn main() void {
    var a: U7 = 5;
    var b: I5 = -3;
    var c: U12 = 4000;
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, c));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(U33)));
    std.io.writeByte('\n');
}
