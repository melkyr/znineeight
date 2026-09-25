// stdlib_print_aggregate_xmod — Task 4 (z98-print-formatting) positive runtime
// fixture: `{}` on struct / tuple / tagged union / untagged union / packed
// struct / packed union prints Zig 0.15.2's aggregate form via the
// compiler-generated per-type printers.
//
// Covers the frozen-table shape family E1-E6 (task-0-report.md) plus the
// generated-printer details this task froze from the oracle: field order and
// separators, tuple form, active-tagged-union field only, untagged union
// `.{ ... }`, packed-union all-fields, nested aggregates, the
// std.fmt.default_max_depth = 3 recursion cap (4th nested level `.{ ... }`),
// mixed scalar field widths/signedness, a struct value passed as a parameter, a
// module-level struct global, module-level tuple `var`/`const` globals (fix
// round 1 Critical 1), a direct tuple-literal argument, and a nested tuple.
//
// Golden contract (rc 0, 3x byte-exact, Zig-0.15.2-twin byte-identical):
//   pair=.{ .a = 1, .b = 2 }
//   tup=.{ 10, 20, 30 }
//   tnest=.{ .{ 1, 2 }, 3 }
//   tmix=.{ 42, true, 1.5 }
//   tagged=.{ .b = 2.5 }
//   untagged=.{ ... }
//   uctrl=.{ ... }
//   packed=.{ .a = 1, .b = 2, .c = true }
//   punion=.{ .a = 7, .b = 7 }
//   outer=.{ .i = .{ .x = 5 }, .y = 6 }
//   mixed=.{ .a = -5, .b = 60000, .c = 3000000000, .d = -5000000000, .e = 1.5, .f = 65 }
//   depth=.{ .a = .{ .a = .{ .a = .{ ... } } } }
//   param=.{ .a = 3, .b = 4 }
//   glob=.{ .a = 11, .b = 12 }
//   gtupv=.{ 11, 22 } gtupc=.{ 33, 44 }
//   tdirect=.{ 5, 6 }
//   done
const std = @import("std");

const Pair = struct { a: i32, b: i32 };
const Inner = struct { x: i32 };
const Outer = struct { i: Inner, y: i32 };
const TU = union(enum) { a: i32, b: f64 };
const U = union { a: i32, b: i32 };
// Negative control: an untagged union with fields that have no route is still
// printable because the generated printer never reads an untagged field.
const US = union { s: []const u8, p: *i32 };
const PS = packed struct { a: u3, b: u5, c: bool };
const PU = packed union { a: u8, b: u8 };
const Mixed = struct { a: i8, b: u16, c: usize, d: i64, e: f32, f: c_char };
const L4 = struct { x: i32 };
const L3 = struct { a: L4 };
const L2 = struct { a: L3 };
const L1 = struct { a: L2 };

var g_pair = Pair{ .a = 11, .b = 12 };
var g_tupv = .{ 11, 22 };
const g_tupc = .{ 33, 44 };

fn showTuple() void {
    std.io.print("gtupv={} gtupc={}\n", .{ g_tupv, g_tupc });
}

fn showPair(p: Pair) void {
    std.io.print("param={}\n", .{p});
}

pub fn main() void {
    var p = Pair{ .a = 1, .b = 2 };
    if (p.a != 1) { @panic("pair.a"); }
    if (p.b != 2) { @panic("pair.b"); }

    var t = .{ 10, 20, 30 };
    var tn = .{ .{ 1, 2 }, 3 };
    var tm = .{ 42, true, 1.5 };

    var tu = TU{ .b = 2.5 };
    var u = U{ .a = 7 };
    var us = US{ .s = "hi" };
    var ps = PS{ .a = 1, .b = 2, .c = true };
    var pu = PU{ .a = 7 };
    var o = Outer{ .i = Inner{ .x = 5 }, .y = 6 };

    var mi_a: i8 = @intCast(i8, 0 - 5);
    var mi_b: u16 = 60000;
    var mi_c: usize = @intCast(usize, 3000000000);
    var mi_d: i64 = @intCast(i64, 0 - 5000000000);
    var mi_e: f32 = @floatCast(f32, 1.5);
    var mi_f: c_char = @intCast(c_char, 65);
    var mixed = Mixed{ .a = mi_a, .b = mi_b, .c = mi_c, .d = mi_d, .e = mi_e, .f = mi_f };

    var depth = L1{ .a = L2{ .a = L3{ .a = L4{ .x = 9 } } } };

    std.io.print("pair={}\n", .{p});
    std.io.print("tup={}\n", .{t});
    std.io.print("tnest={}\n", .{tn});
    std.io.print("tmix={}\n", .{tm});
    std.io.print("tagged={}\n", .{tu});
    std.io.print("untagged={}\n", .{u});
    std.io.print("uctrl={}\n", .{us});
    std.io.print("packed={}\n", .{ps});
    std.io.print("punion={}\n", .{pu});
    std.io.print("outer={}\n", .{o});
    std.io.print("mixed={}\n", .{mixed});
    std.io.print("depth={}\n", .{depth});
    showPair(Pair{ .a = 3, .b = 4 });
    std.io.print("glob={}\n", .{g_pair});
    showTuple();
    std.io.print("tdirect={}\n", .{ .{ 5, 6 } });
    std.io.write("done\n");
}
