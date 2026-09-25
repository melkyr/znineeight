// stdlib_print_tuple_fwd_ok_xmod — Task 9 fix round 1 (z98-print-formatting
// Amendment 1, B5 narrowing; operator ruling): the previously-working scalar
// forward-referenced tuple-global class stays accepted and prints
// Zig-identically.
//
// A module-level tuple literal whose element is a GLOBAL declared later is
// resolved on a later module-var pass than the tuple (pass 1 falls back to
// `TYPE_VOID -> TYPE_I32`). Task 9's original blanket reject was narrowed by
// the operator ruling to only the BROKEN shapes; the benign class is a module
// `const` initialised by a bare int/char literal whose exact value fits i32,
// because the literal is inlined at the use site (the module-init emitter
// skips literal consts), so the frozen i32 slot holds it exactly:
//   fwd_small = 5           -> .{ 5, 7 }
//   fwd_max   = 2147483647  -> .{ 2147483647, 7 }
//   fwd_char  = 'A'         -> .{ 65, 7 }
//   g_two     = .{ fwd_small, fwd_max } -> .{ 5, 2147483647 }
//
// Golden contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2 twin
// `std.debug.print` output): the four lines below, in order.
//   small=.{ 5, 7 }
//   max=.{ 2147483647, 7 }
//   char=.{ 65, 7 }
//   two=.{ 5, 2147483647 }
const std = @import("std");

var g_small = .{ fwd_small, 7 };
const fwd_small = 5;

var g_max = .{ fwd_max, 7 };
const fwd_max = 2147483647;

var g_char = .{ fwd_char, 7 };
const fwd_char = 'A';

var g_two = .{ fwd_small, fwd_max };

fn show() void {
    std.io.print("small={}\n", .{g_small});
    std.io.print("max={}\n", .{g_max});
    std.io.print("char={}\n", .{g_char});
    std.io.print("two={}\n", .{g_two});
}

pub fn main() void {
    show();
}
