// print_aggregate_noprinter_reject_xmod — Task 4 (z98-print-formatting) reject
// fixture for the documented bounded residual: an aggregate whose printer would
// have to read a field kind that has no final field route rejects the ARGUMENT
// with error[3063] at the argument span (rc 2, 0 .c), rather than emitting C
// that cannot compile. Official Zig 0.15.2 ACCEPTS every site (verified with a
// std.debug.print twin): arrays/slices print `{ ... }`, optionals payload/
// `null`, nested packed prints `.{ ... }`.
// Task 5 extended the closure for enum/error-set fields (the Task-4 enum-field
// site is removed; the positive fixture stdlib_print_enum_errset_xmod pins the
// replacement) and left a PACKED enum/error-set field on the packed-aggregate
// residual. Task 6 extended the closure for pointer/fn-pointer fields: the
// Task-4 one-pointer-field site and the tuple-pointer-element site now print
// (pinned by the positive fixture stdlib_print_ptr_hexfloat_xmod) and are
// removed here; arrays/slices/optionals/error-unions remain a standing bounded
// residual with no owning task. Controller ruling R8 (fix round 1): a packed
// struct/packed union NESTED inside another aggregate also rejects — its
// packed-VALUE C model has no working field route (pre-existing; out of Task 4
// scope).
// Task 6 fix round 1 (review Critical 1): a MANY-pointer field never delegates
// to the pointee printer — Zig's `.many, .c` arm calls `printAddress`, whose
// `@typeName(child)` is container-qualified for named aggregates
// (`main.S@addr`), so `[*]S`/`[*]E` aggregate FIELDS reject `error[3063]`
// (sites 6/7). A many-pointer to a scalar/composite child whose name renders
// exactly (`[*]i32`, `[*][]u8`, ...) still prints (`i32@addr`); the positive
// control `mf` row (`[*]i32` field) is pinned in stdlib_print_ptr_hexfloat_xmod.
//
// Sites (each exactly one error[3063]):
//   1. struct with an array field          (Zig: prints `{ 1, 2, 3 }`)
//   2. struct with a slice field           (Zig: prints `{ 104, 105 }`)
//   3. struct with an optional field       (Zig: prints payload/`null`)
//   4. packed struct with a packed-struct field (Zig: prints nested)
//   5. non-packed struct with a packed-struct field (R8; Zig: prints nested)
//   6. struct with a many-pointer-to-struct field (Zig: `main.S@addr`) [fix r1]
//   7. struct with a many-pointer-to-enum field   (Zig: `main.E@addr`) [fix r1]
//
// Negative control that is NOT here: an untagged auto union with unsupported
// fields still prints `.{ ... }` (the printer never reads a field); the positive
// fixture stdlib_print_aggregate_xmod pins that control.
const std = @import("std");
const ArrS = struct { a: [3]i32, b: i32 };
const SliceS = struct { a: []const u8, b: i32 };
const OptS = struct { o: ?i32, b: i32 };
const PS2 = packed struct { x: u3 };
const PackedNested = packed struct { a: PS2, b: u5 };
const NonPackedPacked = struct { p: PS2, b: i32 };
const S = struct { a: i32, b: i32 };
const E = enum { x, y, z };
const ManyS = struct { p: [*]S, n: i32 };
const ManyE = struct { p: [*]E, n: i32 };

pub fn main() void {
    var x: i32 = 5;

    var arr = ArrS{ .a = .{ 1, 2, 3 }, .b = 9 };
    std.io.print("arr={}\n", .{arr});

    var sl = SliceS{ .a = "hi", .b = 9 };
    std.io.print("sl={}\n", .{sl});

    var op = OptS{ .o = @as(?i32, x), .b = 9 };
    std.io.print("op={}\n", .{op});

    var pn = PackedNested{ .a = PS2{ .x = 1 }, .b = 2 };
    std.io.print("pn={}\n", .{pn});

    var np = NonPackedPacked{ .p = PS2{ .x = 1 }, .b = 2 };
    std.io.print("np={}\n", .{np});

    var ms = ManyS{ .p = @intToPtr([*]S, 0x1100), .n = 6 };
    std.io.print("ms={}\n", .{ms});

    var me = ManyE{ .p = @intToPtr([*]E, 0x1200), .n = 7 };
    std.io.print("me={}\n", .{me});
}
