// print_recursive_aggregate_reject_xmod — final whole-branch review fix-wave
// reject fixture (Finding 2 / operator ruling R11): recursive aggregate types.
//
// `struct Node { v: i32, next: *Node }` and the mutual `A <-> B` pair reject
// `error[3063]` (rc 2, 0 .c). The aggregate-field validator recurses through a
// one-pointer field to its pointee (`printFmtAggFieldsOk` -> `printFmtPtrRouteOk`
// -> `printFmtAggFieldsOk`; lower.zig:1096/1257) and the depth cap (16) makes a
// recursive type a "no final route" reject instead of an unbounded printer.
//
// ORACLE NOTE: official Zig 0.15.2 ACCEPTS both forms and prints the nested
// value form, terminating a cycle at `std.fmt.default_max_depth = 3`:
//   node=.{ .v = 2, .next = .{ .v = 2, .next = .{ .v = 2, .next = .{ ... } } } }
//   a=.{ .b = .{ .a = .{ .b = .{ ... }, .n = 8 }, .n = 7 }, .n = 8 }
// (verified with a std.debug.print twin, 2026-09-25). Kept as a DOCUMENTED
// bounded residual (R11, operator ruling): no recursive-printer machinery is
// implemented.
//
// LATENT EMITTER RISK (recorded with R11): if the validator were later
// relaxed, `emitAggPrinterRec` (c89_emit.zig) emits per-type printers in
// post-order dependency order with NO forward declarations. A self-cycle would
// recurse forever at emission time, and a mutual cycle (A -> B -> A) would not
// produce a compilable order at all (one printer would call a printer defined
// later); printer root collection follows the same recursion. Relaxing the cap
// therefore requires forward declarations + a recursion strategy first.
//
// Sites (each exactly one error[3063]):
//   1. self-recursive struct `Node { v: i32, next: *Node }`
//   2. mutual recursion `A { b: *B }` / `B { a: *A }`
const std = @import("std");
const Node = struct { v: i32, next: *Node };
const A = struct { b: *B, n: i32 };
const B = struct { a: *A, n: i32 };

pub fn main() void {
    var leaf = Node{ .v = 1, .next = @intToPtr(*Node, 0) };
    var node = Node{ .v = 2, .next = &leaf };
    std.io.print("node={}\n", .{node});

    var b = B{ .a = @intToPtr(*A, 0), .n = 7 };
    var a = A{ .b = &b, .n = 8 };
    std.io.print("a={}\n", .{a});
}
