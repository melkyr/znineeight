// stdlib_print_enum_errset_xmod — Task 5 (z98-print-formatting) positive
// runtime fixture: `{}` on an enum prints Zig 0.15.2's `.member` and `{}` on
// an error set prints `error.Name`, resolved at runtime against the
// compiler-generated static name tables (frozen-table rows B1/F1 in
// task-0-report.md; spec §4/§5).
//
// Covers: top-level enum `{}` (variable, function parameter, module const,
// direct literal), the explicit `{d}`/`{x}` numeric control (unchanged Task-2
// route — `basic`/`explicit`/`ite`), explicit non-contiguous member values
// (`EC`), a wide `enum(u64)` member above u32 max reached through `@intToEnum`
// (the enum LITERAL path truncates above u32 — a pre-existing sema
// `enum_value_table` defect recorded as a Task-5 bounded residual; the runtime
// value and the name lookup are exact), two error sets with distinct global
// codes, and the Task-4 closure extension: enum / error-set fields inside a
// struct, a nested struct, a tagged-union payload, a tuple element, and an
// untagged-union negative control (`{ ... }`).
//
// Golden contract (rc 0, 3x byte-exact, Zig-0.15.2-twin byte-identical
// `/tmp/t5/oracle/fixture_twin.zig`):
//   param=.c
//   basic .a 2 2
//   glob .c
//   explicit .green 9 9
//   ite .blue 12 c
//   wide .big 5000000001 12a05f201
//   errs error.A error.B
//   errx error.OOM
//   se=.{ .e = error.B, .n = 42 }
//   se2=.{ .e = .b, .n = 7 }
//   sn=.{ .s = .{ .e = .c, .n = 1 }, .t = .a }
//   tu=.{ .e = .b }
//   u=.{ ... }
//   tup=.{ .c, error.A, 3 }
//   direct=.b error.B
//   done
//
// Bounded residuals NOT pinned here (documented): a packed-struct enum field
// still rejects the aggregate argument with error[3063] (Task-4 packed model);
// an enum member literal above u32 max truncates at the literal (pre-existing);
// a bare `error.X` with no expected type resolves to void and rejects (Zig
// needs an inference site too).
const std = @import("std");
const E1 = enum { a, b, c };
const EC = enum(u8) { red = 3, green = 9, blue = 12 };
const EW = enum(u64) { big = 5000000001, small = 7 };
const EA = error{ A, B };
const EB = error{ C, D, OOM };
const SE = struct { e: EA, n: i32 };
const SEnum = struct { e: E1, n: i32 };
const SNest = struct { s: SEnum, t: E1 };
const TU = union(enum) { e: E1, n: i32 };
const UE = union { a: i32, b: i32 };
const GE = E1.c;

fn showE(v: E1) void {
    std.io.print("param={}\n", .{v});
}

pub fn main() void {
    var va: E1 = .a;
    var vc: E1 = .c;
    showE(vc);
    std.io.print("basic {} {d} {x}\n", .{ va, vc, vc });
    std.io.print("glob {}\n", .{GE});
    var g: EC = .green;
    std.io.print("explicit {} {d} {x}\n", .{ g, g, g });
    var bl: EC = @intToEnum(EC, 12);
    std.io.print("ite {} {d} {x}\n", .{ bl, bl, bl });
    var w: EW = @intToEnum(EW, 5000000001);
    std.io.print("wide {} {d} {x}\n", .{ w, w, w });
    var err1: EA = error.A;
    var err2: EA = error.B;
    std.io.print("errs {} {}\n", .{ err1, err2 });
    var errx: EB = error.OOM;
    std.io.print("errx {}\n", .{errx});
    var se = SE{ .e = error.B, .n = 42 };
    std.io.print("se={}\n", .{se});
    var se2 = SEnum{ .e = .b, .n = 7 };
    std.io.print("se2={}\n", .{se2});
    var sn = SNest{ .s = SEnum{ .e = .c, .n = 1 }, .t = .a };
    std.io.print("sn={}\n", .{sn});
    var tu = TU{ .e = .b };
    std.io.print("tu={}\n", .{tu});
    var u = UE{ .a = 1 };
    std.io.print("u={}\n", .{u});
    var ev: E1 = .c;
    var erv: EA = error.A;
    var tup = .{ ev, erv, 3 };
    std.io.print("tup={}\n", .{tup});
    std.io.print("direct={} {}\n", .{ E1.b, err2 });
    std.io.print("done\n");
}
