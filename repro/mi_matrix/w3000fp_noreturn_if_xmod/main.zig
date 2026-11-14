// w3000fp_noreturn_if_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `const x: i32 = if (c) return 1 else return 2;` — both arms diverge, so the
// `if` expression is `noreturn`, which coerces to ANY type in Zig/Z98.
// `typeRegistryIsAssignable` (`sf/src/type_registry.zig:1151-1304`) has no
// `noreturn` source arm, so the var-decl warns `source: noreturn / target: i32`
// (`sf/src/semantic_analyzer.zig:2978-2993`).
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `1`; the diverging arm returns correctly.
const std = @import("std");

fn pick(c: bool) i32 {
    const x: i32 = if (c) return 1 else return 2;
    return x;
}

pub fn main() void {
    std.io.printInt(pick(true));
    std.io.writeByte('\n');
}
