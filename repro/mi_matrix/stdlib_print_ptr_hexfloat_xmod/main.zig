// stdlib_print_ptr_hexfloat_xmod — Task 6 (z98-print-formatting) positive
// runtime fixture: `{}` on pointers / fn-pointers prints Zig 0.15.2's
// `T@<lowercase-hex>` form (NO `0x` prefix; operator ruling R3) or delegates to
// the pointee printer, and float `{x}` prints a hand-rolled C89 hex-float
// (`0x1.8p0`). Frozen-table rows G1/G2/G5 + C3 (task-0-report.md); spec §4.
//
// Addresses are nondeterministic (ASLR / link layout), so every address-bearing
// row reaches the printer through `@intToPtr` with a fixed integer: the golden
// pins the printer's FORMAT (`i32@1234`, `fn (i32, u8) i32@2300`,
// `error{A,B}@1500`) without pinning any real address. Real globals are used
// only for the pointee-delegation rows (`*S` -> `.{ ... }`, `*E` -> `.y`, ...),
// whose output contains the pointee value and no address.
//
// Covers: one-pointers to i32/*const*/u8/bool/f64/c_char/void, fn pointers
// (`fn () void`, `fn (i32, u8) i32`), `**i32`, `*?i32`, `*[]const u8`,
// `*error{A,B}`, `*E!i32`, one-pointer-to-struct/enum/tagged-union/untagged-
// union/packed-struct/packed-union delegation, and the Task-4 closure
// extension: pointer / fn-pointer / many-pointer / pointer-to-optional /
// pointer-to-slice / pointer-to-error-set / pointer-to-packed fields inside
// aggregates (plus a `*S` delegation field and a `*E` enum-delegation field).
// Float `{x}` rows (f64 and f32; zero, negative zero, negative, denormal via
// runtime division, 1/3, 1e20) are byte-compared with the Zig-0.15.2 twin.
//
// Golden contract (rc 0, 3x byte-exact; the 18 oracle rows below are
// byte-identical to the Zig-0.15.2 twin `/tmp/t6/oracle/fixture_twin.zig`
// (931 B / 18 lines); Z98 appends its own `done` marker line — golden
// 936 B / 19 lines):
//   p1=i32@1234 p2=i32@1234 p3=u8@1235 p4=bool@1236 p5=f64@1240 p6=c_char@1237 p7=void@1238
//   f1=fn () void@2200 f2=fn (i32, u8) i32@2300 pp=*i32@1200 po=?i32@1300 psl=[]const u8@1400 pes=error{A,B}@1500
//   peu=error{A,B}!i32@2100
//   ps=.{ .a = 1, .b = 2 } pe=.y ptu=.{ .a = 7 } pu=.{ ... }
//   ppacked=.{ .a = 1, .b = 2, .c = true } ppu=.{ .a = 7, .b = 7 }
//   pf=.{ .p = i32@1600, .n = 1 }
//   sf=.{ .p = .{ .a = 1, .b = 2 }, .n = 2 }
//   ef=.{ .p = .y, .n = 3 }
//   ff=.{ .f = fn () void@1700, .ok = true }
//   mf=.{ .p = i32@1800, .n = 4 }
//   ppf=.{ .p = *i32@1900, .n = 5 }
//   pof=.{ .p = ?i32@1a00, .n = 6 }
//   psf=.{ .p = []const u8@1b00, .n = 7 }
//   pesf=.{ .p = error{A,B}@1c00, .n = 8 }
//   ppkf=.{ .p = .{ .a = 1, .b = 2, .c = true }, .n = 9 }
//   ppuf=.{ .p = .{ .a = 7, .b = 7 }, .n = 10 }
//   d1=0x1.8p0 d2=0x0.0p0 d3=-0x0.0p0 d4=0x1p1 d5=-0x1p1 d6=0x1.5555555555555p-2 d7=0x1.5af1d78b58c4p66 d8=0x0.00000000316a2p-1022
//   g1=0x1.8p0 g2=0x1.99999ap-4 g3=0x1.5af1d8p66 g4=-0x0.0p0
//   done
//
// Bounded residuals NOT pinned here (documented): a composite pointee name
// that contains a NAMED enum/struct/union rejects the argument with
// error[3063] (`*?S`, `**S`, `*?E`; Zig container-qualifies those names, e.g.
// `main.S`); a one-pointer-to-array field rejects (print as slice residual);
// float denormal/nan/inf cannot be built via a Z98 literal (`5e-324` parses
// as 0.0; `@bitCast` rejects f64 - pre-existing), so d8 is computed at runtime.
const std = @import("std");

const S = struct { a: i32, b: i32 };
const E = enum { x, y, z };
const TU = union(enum) { a: i32, b: bool };
const U = union { a: i32, b: bool };
const ES = error{ A, B };
const EU = ES!i32;
const PS = packed struct { a: u3, b: u5, c: bool };
const PU = packed union { a: u8, b: u8 };

const PField = struct { p: *i32, n: i32 };
const SField = struct { p: *S, n: i32 };
const EField = struct { p: *E, n: i32 };
const FnField = struct { f: fn() void, ok: bool };
const ManyField = struct { p: [*]i32, n: i32 };
const PpField = struct { p: **i32, n: i32 };
const PoField = struct { p: *?i32, n: i32 };
const PslField = struct { p: *[]const u8, n: i32 };
const PesField = struct { p: *ES, n: i32 };
const PpkField = struct { p: *PS, n: i32 };
const PpuField = struct { p: *PU, n: i32 };

var gs: S = S{ .a = 1, .b = 2 };
var ge: E = .y;
var gtu: TU = .{ .a = 7 };
var gu: U = .{ .a = 9 };
var gps: PS = PS{ .a = 1, .b = 2, .c = true };
var gpu: PU = PU{ .a = 7 };

fn makeEU() EU {
    return 5;
}

pub fn main() void {
    var p1: *i32 = @intToPtr(*i32, 0x1234);
    var p2: *const i32 = @intToPtr(*const i32, 0x1234);
    var p3: *u8 = @intToPtr(*u8, 0x1235);
    var p4: *bool = @intToPtr(*bool, 0x1236);
    var p5: *f64 = @intToPtr(*f64, 0x1240);
    var p6: *c_char = @intToPtr(*c_char, 0x1237);
    var p7: *void = @intToPtr(*void, 0x1238);
    var f1: fn() void = @intToPtr(fn() void, 0x2200);
    var f2: fn(i32, u8) i32 = @intToPtr(fn(i32, u8) i32, 0x2300);
    var pp: **i32 = @intToPtr(**i32, 0x1200);
    var po: *?i32 = @intToPtr(*?i32, 0x1300);
    var psl: *[]const u8 = @intToPtr(*[]const u8, 0x1400);
    var pes: *ES = @intToPtr(*ES, 0x1500);
    var peu: *EU = @intToPtr(*EU, 0x2100);
    std.io.print("p1={} p2={} p3={} p4={} p5={} p6={} p7={}\n", .{ p1, p2, p3, p4, p5, p6, p7 });
    std.io.print("f1={} f2={} pp={} po={} psl={} pes={}\n", .{ f1, f2, pp, po, psl, pes });
    std.io.print("peu={}\n", .{peu});
    std.io.print("ps={} pe={} ptu={} pu={}\n", .{ &gs, &ge, &gtu, &gu });
    std.io.print("ppacked={} ppu={}\n", .{ &gps, &gpu });

    var pf: PField = PField{ .p = @intToPtr(*i32, 0x1600), .n = 1 };
    var sf: SField = SField{ .p = &gs, .n = 2 };
    var ef: EField = EField{ .p = &ge, .n = 3 };
    var ff: FnField = FnField{ .f = @intToPtr(fn() void, 0x1700), .ok = true };
    var mf: ManyField = ManyField{ .p = @intToPtr([*]i32, 0x1800), .n = 4 };
    var ppf: PpField = PpField{ .p = @intToPtr(**i32, 0x1900), .n = 5 };
    var pof: PoField = PoField{ .p = @intToPtr(*?i32, 0x1a00), .n = 6 };
    var psf: PslField = PslField{ .p = @intToPtr(*[]const u8, 0x1b00), .n = 7 };
    var pesf: PesField = PesField{ .p = @intToPtr(*ES, 0x1c00), .n = 8 };
    var ppkf: PpkField = PpkField{ .p = &gps, .n = 9 };
    var ppuf: PpuField = PpuField{ .p = &gpu, .n = 10 };
    std.io.print("pf={}\n", .{pf});
    std.io.print("sf={}\n", .{sf});
    std.io.print("ef={}\n", .{ef});
    std.io.print("ff={}\n", .{ff});
    std.io.print("mf={}\n", .{mf});
    std.io.print("ppf={}\n", .{ppf});
    std.io.print("pof={}\n", .{pof});
    std.io.print("psf={}\n", .{psf});
    std.io.print("pesf={}\n", .{pesf});
    std.io.print("ppkf={}\n", .{ppkf});
    std.io.print("ppuf={}\n", .{ppuf});

    var d1: f64 = 1.5;
    var d2: f64 = 0.0;
    var d3: f64 = -0.0;
    var d4: f64 = 2.0;
    var d5: f64 = -2.0;
    var d6: f64 = 1.0 / 3.0;
    var d7: f64 = 1e20;
    var d8: f64 = 1e-308 / 1e10;
    var g1: f32 = 1.5;
    var g2: f32 = 0.1;
    var g3: f32 = 1e20;
    var g4: f32 = -0.0;
    std.io.print("d1={x} d2={x} d3={x} d4={x} d5={x} d6={x} d7={x} d8={x}\n", .{ d1, d2, d3, d4, d5, d6, d7, d8 });
    std.io.print("g1={x} g2={x} g3={x} g4={x}\n", .{ g1, g2, g3, g4 });
    std.io.print("done\n", .{});
}
