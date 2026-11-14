// w3000_undefined_manyptr_xmod — Task 0k warning[3000] pin (VALID Z98 -> (a)).
//
// Reproduces the compiler's own `sf/src/type_registry.zig:340` /
// `state_map.zig:65` / `module_registry.zig:477-484` shape: assigning
// `undefined` to a many-pointer field/target. The checker reports
// `warning[3000]` with source kind `type` (the `undefined` type id has no
// TypeKind arm, so `typeKindSrcStr` falls through to `source: type`) and target
// `many-pointer`.
//
// `undefined` is valid for ANY type (Language_Spec_Z98.md:363-368: it is the
// opt-out of `error[3014]`), so this is a type-checker false positive.
//
// Classification (Task 0k): (a) valid Z98, fix = type-checker accuracy
// (`undefined` must be assignable to every type).
//
// Runtime (today): prints `1`; the assignment is dead storage.
const std = @import("std");
const S = struct { p: [*]u8 };

pub fn main() void {
    var s: S = undefined;
    s.p = undefined;
    _ = s;
    std.io.printInt(@intCast(i32, 1));
    std.io.writeByte('\n');
}
