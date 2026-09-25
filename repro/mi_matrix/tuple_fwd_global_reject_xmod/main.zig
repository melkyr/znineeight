// tuple_fwd_global_reject_xmod — Task 9 (z98-print-formatting Amendment 1, B5)
// reject fixture: a module-level tuple literal whose element references a GLOBAL
// declared later ("forward reference"). Pass 1 of the module-var resolution loop
// resolves the tuple before the later global has a type, so the element falls
// back to `i32`; the Task-4 idempotent tuple type keeps that stale slot even
// after pass 2 resolves the global. Reusing it emitted gcc-invalid C (composite
// element: assigning a `Pair` into an `int`) or a silently wrong value (an
// integer element whose final carrier differs). Task 9 re-resolves the recorded
// tuple and clean-rejects a changed element list with error[3064].
//
// CENSUS: dump rc=2, 0 `.c`, exactly 3 x error[3064] (one per forward-ref tuple),
// and NO diagnostic for the stable control. The direct/global tuple fixtures
// (`stdlib_print_aggregate_xmod` `gtupv`/`gtupc`) stay accepted.
//
// ORACLE NOTE: official Zig 0.15.2 accepts all four shapes (container-level
// declarations are order-independent) and prints
//   g_pair = .{ .{ .a = 1, .b = 2 }, 7 }
//   g_small= .{ 5, 7 }
//   g_big  = .{ 3000000000, 7 }
// `__module_init` lowers globals in declaration order, so the composite case
// cannot become runtime-correct without a module-init dependency ordering
// change; the shape is a documented Z98 bounded residual (Language_Spec §4) —
// clean reject, never broken or silently wrong C.
const std = @import("std");

const Pair = struct { a: i32, b: i32 };

// 1. Composite forward reference (the reported RED: rc=0 then gcc
//    `incompatible types when assigning to type 'int' from type 'Pair'`).
var g_pair = .{ p, 7 };
const p = Pair{ .a = 1, .b = 2 };

// 2. Small scalar forward reference. The old compiler accepted it (the frozen
//    i32 slot happens to hold the value), but it is the same stale-inference
//    shape as 3, so it rejects for consistency.
var g_small = .{ s, 7 };
const s = 5;

// 3. Large scalar forward reference (was accepted rc=0 / gcc clean and printed
//    `-1294967296`; the frozen i32 slot cannot hold 3000000000).
var g_big = .{ t, 7 };
const t = 3000000000;

// Stable control: no forward reference; the element list is identical on every
// pass, so the Task-4 idempotent fast path returns the recorded type.
var g_ok = .{ 11, 22 };

pub fn main() void {
    std.io.print("ok={}\n", .{g_ok});
}
