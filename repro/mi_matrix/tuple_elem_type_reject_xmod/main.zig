// tuple_elem_type_reject_xmod — FB2 (Volume II inferred-tuple-element typing
// family) reject fixture.
//
// The FB element-typing fallbacks fabricated runtime elements from non-values:
// a `void` element became i32 (gcc-invalid construction), an untyped big
// integer element became i32 (silent truncation), and a TYPE used as a value
// was accepted (gcc `zT = i32;`). Every shape below now clean-rejects with the
// print-formatting rule instead:
//   1. `.{ vf(), 1 }` tuple variable print      -> error[3063] (void element)
//   2. `.{ vf(), 1 }` literal print             -> error[3063] (void element)
//   3. `print("agg={}", .{ v })` aggregate      -> error[3063] (void element)
//   4. `.{ i32, 5 }` builtin type value         -> error[3063] (TYPE_TYPE)
//   5. `.{ S, 5 }` named type value             -> error[3063] (TYPE_TYPE)
//   6. `.{ helper.Pair, 5 }` module type value  -> error[3063] (TYPE_TYPE)
//   7. `.{ u32, 5 }` literal type value         -> error[3063] (TYPE_TYPE)
//   8. `.{ struct { i32, i32 }, 5 }` inline type -> error[3063] (TYPE_TYPE)
//   9. `.{ 1 << 100, 1 }` >64-bit exact value   -> error[3000] (comptime bound)
//  10. `.{ -9223372036854775809, 1 }` >window   -> error[3000] (comptime bound)
//  11. `.{ s.v, 1 }` local void struct FIELD    -> error[3063] (void element;
//      fix round 1 — the FB2 unresolved-ref fallback must not treat a
//      value-base field read as an unresolved forward reference)
//  12. `.{ gvs.v, 1 }` global void field        -> error[3063]
//  13. `.{ p.v, 1 }` parameter void field       -> error[3063]
//  14. `print("vfl={} {}", .{ s.v, 1 })` literal -> error[3063] (control)
//
// Exact census is recorded in EXPECTED_FAIL.md; main.zig is the only entry
// (one module so every level-0 diagnostic is collected).
const std = @import("std");
const helper = @import("helper.zig");

fn vf() void {}

const S = struct { a: i32 };

// A void-typed struct FIELD is legal Z98 (`struct { v: void, a: i32 }`
// compiles and runs), so `s.v` is a REAL void value, not an unresolved
// forward reference: the element must keep `void` and reject 3063.
const SV = struct { v: void, a: i32 };

var gvs: SV = undefined;

fn showVoidField(p: SV) void {
    const tv = .{ p.v, 1 };
    std.io.print("vp={} {}\n", tv);
}

pub fn main() void {
    const v = .{ vf(), 1 };
    std.io.print("v={} {}\n", v);

    std.io.print("vl={} {}\n", .{ vf(), 1 });

    std.io.print("va={}", .{ v });

    const ty = .{ i32, 5 };
    std.io.print("ty={} {}\n", ty);

    const ts = .{ S, 5 };
    std.io.print("ts={} {}\n", ts);

    const tm = .{ helper.Pair, 5 };
    std.io.print("tm={} {}\n", tm);

    std.io.print("tl={} {}\n", .{ u32, 5 });

    std.io.print("ti={} {}\n", .{ struct { i32, i32 }, 5 });

    const w = .{ 1 << 100, 1 };
    std.io.print("w={} {}\n", w);

    const n = .{ -9223372036854775809, 1 };
    std.io.print("n={} {}\n", n);

    var s: SV = undefined;
    s.a = 7;
    const tf = .{ s.v, 1 };
    std.io.print("vf={} {}\n", tf);

    gvs.a = 9;
    const tg = .{ gvs.v, 1 };
    std.io.print("vg={} {}\n", tg);

    showVoidField(s);

    std.io.print("vfl={} {}\n", .{ s.v, 1 });
}
