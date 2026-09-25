// stdlib_print_tuple_fwd_ok_xmod — Task 9 fix round 2 (z98-print-formatting
// Amendment 1, B5; operator Q6.1): the previously-working forward-referenced
// tuple-global classes stay accepted and print Zig-identically.
//
// A module-level tuple literal whose element is a GLOBAL declared later is
// resolved on a later module-var pass than the tuple (pass 1 falls back to
// `TYPE_VOID -> TYPE_I32`). Fix round 2 validates every recorded element:
// benign when the value is INLINED at the use site (a module `const` with a
// bare int/char literal whose value fits the recorded slot) or when the global
// is initialised before the tuple; broken otherwise. This fixture pins the
// benign/order-safe classes:
//   fwd_small = 5            int literal forward ref      -> .{ 5, 7 }
//   fwd_max   = 2147483647   int literal forward ref      -> .{ 2147483647, 7 }
//   fwd_char  = 'A'          char literal forward ref     -> .{ 65, 7 }
//   colors.C = 5             aliased module member        -> .{ 5, 7 }
//   (fwd_small)              parenthesized forward ref    -> .{ 5, 7 }
//   fwd_u32: u32 = 5         annotated int literal        -> .{ 5, 7 }
//   fwd_i32lit: i32 = 5      annotated int literal        -> .{ 5, 7 }
//   g_two = .{ fwd_small, fwd_max }  two forward refs     -> .{ 5, 2147483647 }
//   back_arith: i32 = 5 + 7  declared BEFORE the tuple     -> .{ 12, 7 }
//
// Golden contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2 twin
// `std.debug.print` output): the nine lines below, in order.
//   small=.{ 5, 7 }
//   max=.{ 2147483647, 7 }
//   char=.{ 65, 7 }
//   xmod=.{ 5, 7 }
//   paren=.{ 5, 7 }
//   u32=.{ 5, 7 }
//   i32lit=.{ 5, 7 }
//   two=.{ 5, 2147483647 }
//   back=.{ 12, 7 }
const std = @import("std");
const colors = @import("colors.zig");

var g_small = .{ fwd_small, 7 };
const fwd_small = 5;

var g_max = .{ fwd_max, 7 };
const fwd_max = 2147483647;

var g_char = .{ fwd_char, 7 };
const fwd_char = 'A';

var g_xmod = .{ colors.C, 7 };

var g_paren = .{ (fwd_small), 7 };

var g_u32 = .{ fwd_u32, 7 };
const fwd_u32: u32 = 5;

var g_i32lit = .{ fwd_i32lit, 7 };
const fwd_i32lit: i32 = 5;

var g_two = .{ fwd_small, fwd_max };

const back_arith: i32 = 5 + 7;
var g_back = .{ back_arith, 7 };

fn show() void {
    std.io.print("small={}\n", .{g_small});
    std.io.print("max={}\n", .{g_max});
    std.io.print("char={}\n", .{g_char});
    std.io.print("xmod={}\n", .{g_xmod});
    std.io.print("paren={}\n", .{g_paren});
    std.io.print("u32={}\n", .{g_u32});
    std.io.print("i32lit={}\n", .{g_i32lit});
    std.io.print("two={}\n", .{g_two});
    std.io.print("back={}\n", .{g_back});
}

pub fn main() void {
    show();
}
