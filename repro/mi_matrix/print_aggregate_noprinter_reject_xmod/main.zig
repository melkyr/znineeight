// print_aggregate_noprinter_reject_xmod — Task 4 (z98-print-formatting) reject
// fixture for the documented bounded residual: an aggregate whose printer would
// have to read a field kind that has no final field route rejects the ARGUMENT
// with error[3063] at the argument span (rc 2, 0 .c), rather than emitting C
// that cannot compile. Official Zig 0.15.2 ACCEPTS every site (verified with a
// std.debug.print twin): arrays/slices print `{ ... }`, optionals payload/
// `null`, pointers `T@addr`, nested packed prints `.{ ... }`.
// Task 5 extended the closure for enum/error-set fields (the Task-4 enum-field
// site is removed; the positive fixture stdlib_print_enum_errset_xmod pins the
// replacement) and left a PACKED enum/error-set field on the packed-aggregate
// residual. Task 6 extends the closure for pointer fields;
// arrays/slices/optionals/error-unions are a standing bounded residual with no
// owning task. Controller ruling R8 (fix round 1): a packed struct/packed
// union NESTED inside another aggregate also rejects — its packed-VALUE C model
// has no working field route (pre-existing; out of Task 4 scope).
//
// Sites (each exactly one error[3063]):
//   1. struct with an array field          (Zig: prints `{ 1, 2, 3 }`)
//   2. struct with a slice field           (Zig: prints `{ 104, 105 }`)
//   3. struct with a one-pointer field     (Zig: prints `i32@...`) [Task 6]
//   4. struct with an optional field       (Zig: prints payload/`null`)
//   5. packed struct with a packed-struct field (Zig: prints nested)
//   6. tuple with a pointer element        (Zig: prints `i32@...`) [Task 6]
//   7. non-packed struct with a packed-struct field (R8; Zig: prints nested)
//
// Negative control that is NOT here: an untagged auto union with unsupported
// fields still prints `.{ ... }` (the printer never reads a field); the positive
// fixture stdlib_print_aggregate_xmod pins that control.
const std = @import("std");
const ArrS = struct { a: [3]i32, b: i32 };
const SliceS = struct { a: []const u8, b: i32 };
const PtrS = struct { p: *i32, b: i32 };
const OptS = struct { o: ?i32, b: i32 };
const PS2 = packed struct { x: u3 };
const PackedNested = packed struct { a: PS2, b: u5 };
const NonPackedPacked = struct { p: PS2, b: i32 };

pub fn main() void {
    var x: i32 = 5;

    var arr = ArrS{ .a = .{ 1, 2, 3 }, .b = 9 };
    std.io.print("arr={}\n", .{arr});

    var sl = SliceS{ .a = "hi", .b = 9 };
    std.io.print("sl={}\n", .{sl});

    var pt = PtrS{ .p = &x, .b = 9 };
    std.io.print("pt={}\n", .{pt});

    var op = OptS{ .o = @as(?i32, x), .b = 9 };
    std.io.print("op={}\n", .{op});

    var pn = PackedNested{ .a = PS2{ .x = 1 }, .b = 2 };
    std.io.print("pn={}\n", .{pn});

    var q: *i32 = &x;
    var t = .{ q, 3 };
    std.io.print("t={}\n", .{t});

    var np = NonPackedPacked{ .p = PS2{ .x = 1 }, .b = 2 };
    std.io.print("np={}\n", .{np});
}
