// stdlib_print_tuple_fwd_ok_xmod — Task 9 (z98-print-formatting Amendment 1,
// B5) positive runtime fixture, extended by fix round 3 (operator ruling Q7).
//
// Before Q7, a module-level tuple literal whose element referenced a global
// declared later froze the pass-1 `TYPE_VOID -> TYPE_I32` fallback and emitted
// gcc-invalid or silently wrong C. Q7 makes `__module_init` emit globals in a
// stable dependency order (same module and across modules) and lets the
// module-var fixpoint settle a forward-referenced element's true type, so the
// whole class now matches Zig 0.15.2. This fixture pins every class:
//   small/max/char   bare int/char literal const forward refs
//   xmod             aliased module member (`colors.C`)
//   paren            parenthesized forward ref
//   u32/i32          annotated integer literal consts
//   two              two forward refs in one tuple
//   back             a global declared BEFORE the tuple (control)
//   ann/neg/as       non-literal scalar consts (`5 + 7`, `-5`, `@as(i32, 5)`)
//   xc2              cross-module non-literal const (`colors.C2`)
//   imp              direct `@import("colors.zig").C` member
//   chain            transitive cross-module const (`aux.A = colors.C2`)
//   stf              struct-literal field forward ref
//   call             call-argument forward ref
//   pair             composite (struct) const element (type rebuilt to Pair)
//   direct           NON-tuple direct forward ref (`var g_direct = fwd_direct`
//                    with a later `const fwd_direct = Pair{...}`)
//   big              out-of-i32 literal (`3000000000`, type rebuilt to u32)
//   float/bool       f64 / bool elements (type rebuilt)
//
// Golden contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2 twin
// `std.debug.print` output): the 22 lines below, in order.
//   small=.{ 5, 7 }
//   max=.{ 2147483647, 7 }
//   char=.{ 65, 7 }
//   xmod=.{ 5, 7 }
//   paren=.{ 5, 7 }
//   u32=.{ 5, 7 }
//   i32=.{ 5, 7 }
//   two=.{ 5, 2147483647 }
//   back=.{ 12, 7 }
//   ann=.{ 12, 7 }
//   neg=.{ -5, 7 }
//   as=.{ 5, 7 }
//   xc2=.{ 12, 7 }
//   imp=.{ 5, 7 }
//   chain=.{ 12, 7 }
//   stf=.{ .{ .a = 12, .b = 2 }, 7 }
//   call=.{ 12, 7 }
//   pair=.{ .{ .a = 1, .b = 2 }, 7 }
//   direct=.{ .a = 1, .b = 2 }
//   big=.{ 3000000000, 7 }
//   float=.{ 1.5, 7 }
//   bool=.{ true, 7 }
const std = @import("std");
const colors = @import("colors.zig");
const aux = @import("aux.zig");

const Pair = struct { a: i32, b: i32 };
const Inner = struct { a: i32, b: i32 };

fn id(x: i32) i32 {
    return x;
}

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

var g_i32 = .{ fwd_i32, 7 };
const fwd_i32: i32 = 5;

var g_two = .{ fwd_small, fwd_max };

const back_arith: i32 = 5 + 7;
var g_back = .{ back_arith, 7 };

var g_ann = .{ fwd_ann, 7 };
const fwd_ann: i32 = 5 + 7;

var g_neg = .{ fwd_neg, 7 };
const fwd_neg: i32 = -5;

var g_as = .{ fwd_as, 7 };
const fwd_as = @as(i32, 5);

var g_xc2 = .{ colors.C2, 7 };

var g_imp = .{ @import("colors.zig").C, 7 };

var g_chain = .{ aux.A, 7 };

var g_stf = .{ Inner{ .a = fwd_stf, .b = 2 }, 7 };
const fwd_stf: i32 = 5 + 7;

var g_call = .{ id(fwd_call), 7 };
const fwd_call: i32 = 5 + 7;

var g_pair = .{ fwd_pair, 7 };
const fwd_pair = Pair{ .a = 1, .b = 2 };

// Final-review Minor 2: the NON-tuple direct forward reference (`var
// g_direct = fwd_direct;` with an aggregate const declared later). Q7's
// ident dep-scan orders fwd_direct first, so this prints Zig's value; the
// pre-Q7 residual claim (`.a = 0, .b = 0`) is retired.
var g_direct = fwd_direct;
const fwd_direct = Pair{ .a = 1, .b = 2 };

var g_big = .{ fwd_big, 7 };
const fwd_big = 3000000000;

var g_float = .{ fwd_float, 7 };
const fwd_float = 1.5;

var g_bool = .{ fwd_bool, 7 };
const fwd_bool = true;

fn show() void {
    std.io.print("small={}\n", .{g_small});
    std.io.print("max={}\n", .{g_max});
    std.io.print("char={}\n", .{g_char});
    std.io.print("xmod={}\n", .{g_xmod});
    std.io.print("paren={}\n", .{g_paren});
    std.io.print("u32={}\n", .{g_u32});
    std.io.print("i32={}\n", .{g_i32});
    std.io.print("two={}\n", .{g_two});
    std.io.print("back={}\n", .{g_back});
    std.io.print("ann={}\n", .{g_ann});
    std.io.print("neg={}\n", .{g_neg});
    std.io.print("as={}\n", .{g_as});
    std.io.print("xc2={}\n", .{g_xc2});
    std.io.print("imp={}\n", .{g_imp});
    std.io.print("chain={}\n", .{g_chain});
    std.io.print("stf={}\n", .{g_stf});
    std.io.print("call={}\n", .{g_call});
    std.io.print("pair={}\n", .{g_pair});
    std.io.print("direct={}\n", .{g_direct});
    std.io.print("big={}\n", .{g_big});
    std.io.print("float={}\n", .{g_float});
    std.io.print("bool={}\n", .{g_bool});
}

pub fn main() void {
    show();
}
