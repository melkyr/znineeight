// tuple_model_reject_xmod — FB (Volume II D4) reject fixture for the tuple
// type/access model.
//
// Every reject class the model must produce instead of silently emitting
// invalid C:
//   1. `p[5]` / `p.9` out of range            -> error[3070]
//      (`index N outside tuple of length L`, Zig 0.15.2 wording)
//   2. `p[i]` runtime index                    -> error[3069]
//      (`tuple field index must be comptime-known`, Zig's note wording)
//   3. `.73` on a non-tuple struct             -> error[3060], never a
//      silent name-id alias (`len` has name id 73 pre-registration order)
//   4. arity mismatch  A{2} -> B{3}            -> error[3000], level 0
//   5. element mismatch A{i32,i32} -> C{i32,f32} -> error[3000], level 0
//   6. tuple with an array element             -> error[3000] (operator-ruled
//      clean reject: no field-wise C array assignment; in the standalone
//      `array_reject.zig` entry: a type-resolution error suppresses the later
//      sema census, so it cannot share this file)
//   7. mixed named/positional fields           -> error[2000] (standalone
//      `parse_reject.zig` entry: a parse error aborts the module)
//   8. packed positional fields                -> error[2000] (same)
//   9. cross-module tuple index out of range   -> error[3070] in helper.zig
//
// Exact census is recorded in `EXPECTED_FAIL.md`; shape parses/sema may emit
// adjacent cascades on the same node.
const std = @import("std");
const helper = @import("helper.zig");

const A = struct { i32, i32 };
const B = struct { i32, i32, i32 };
const C = struct { i32, f32 };
const S = struct { len: i32, cap: i32 };

pub fn main() void {
    const p: A = .{ 1, 2 };
    const x = p[5];
    const y = p.9;
    var i: usize = 1;
    const z = p[i];
    const s = S{ .len = 3, .cap = 9 };
    const w = s.73;
    const a: A = .{ 1, 2 };
    const b: B = a;
    const c: C = a;
    const h = helper.oob(p);
    std.io.print("{} {} {} {} {} {} {}\n", .{ x, y, z, w, h, b, c });
}
