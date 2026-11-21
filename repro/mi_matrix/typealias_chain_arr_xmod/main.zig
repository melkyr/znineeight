// typealias_chain_arr_xmod — RED->GREEN (A9F-a). An alias chain to an aggregate
// (`const A = [3]i32; const B = A;`). `constAliasPrepass` set `B.type_id` but
// never `B.kind`, so main classified B as a value global and emitted a bogus
// type-storage global (`zG_..._B` initialized from `zT_811C9DC5_`) — bad C.
// Fix (A9F-a): `constAliasPrepass` sets `sym.kind = type_alias`; front-resolution
// classifies `const X = Y` as a type alias when `Y` is itself a type alias.
// Blast radius (recorded): drops the same bogus `const X = Y` type-storage
// globals in `emission_type_storage_{control,extern_struct,extern_threealias}_xmod`;
// behavior unchanged.
// Contract: compile-clean, run prints 15\n.
const std = @import("std");

const A = [3]i32;
const B = A;

pub fn main() void {
    var x: B = [_]i32{ 4, 5, 6 };
    std.io.printInt(x[0] + x[1] + x[2]);
    std.io.writeByte('\n');
}
