// print_fmt_type_reject_xmod — Task 3 (z98-print-formatting) reject fixture:
// specifier/type mismatches, error[3013] at the ARGUMENT span.
//
// Frozen table `.superpowers/sdd/2026-09-22-z98-print-formatting-plan/task-0-report.md`
// rows A18/A19/A20/A21/B4/C4/D2/D4/D6/D7/E7/F2/G3/G4/G8/G9/G11/G12 plus the
// existing H9 unknown-specifier check. Every site is oracle-cross-checked with
// official Zig 0.15.2: Zig rejects the same shape, EXCEPT A20 (`{c}` on an
// integer literal), the operator-ruled R5 bounded residual — Zig accepts an
// in-range comptime literal, Z98 rejects it (documented in EXPECTED_FAIL.md).
//
// Contract: dump rc=2, 0 `.c`, exactly 60 x error[3013], 0 x error[3063]
// (canonical classifier FAIL). The argument-node span is the caret target (the
// two H9 unknown-specifier sites keep the existing fmt-string span).
const std = @import("std");
const S = struct { a: i32, b: i32 };
const U = union(enum) { a: i32, b: f32 };
const E = error{ A, B };
const C = enum { red, green };
fn id() void {}

pub fn main() void {
    // A18: non-u8 integer kinds `{c}` (9 sites).
    const i32c: i32 = 65; std.io.print("{c}", .{i32c});
    const i8c: i8 = 65; std.io.print("{c}", .{i8c});
    const u16c: u16 = 65; std.io.print("{c}", .{u16c});
    const u32c: u32 = 65; std.io.print("{c}", .{u32c});
    const u64c: u64 = 65; std.io.print("{c}", .{u64c});
    const uszc: usize = 65; std.io.print("{c}", .{uszc});
    const iszc: isize = 65; std.io.print("{c}", .{iszc});
    const cchc: c_char = 65; std.io.print("{c}", .{cchc});
    const u40c: u40 = 65; std.io.print("{c}", .{u40c});
    // A19: non-u8 integer kinds `{s}` (6 sites).
    const i32s: i32 = 65; std.io.print("{s}", .{i32s});
    const i64s: i64 = 65; std.io.print("{s}", .{i64s});
    const u16s: u16 = 65; std.io.print("{s}", .{u16s});
    const u40s: u40 = 65; std.io.print("{s}", .{u40s});
    const uszs: usize = 65; std.io.print("{s}", .{uszs});
    const cchs: c_char = 65; std.io.print("{s}", .{cchs});
    // A20/A21: integer literal `{c}`/`{s}` (2 sites; A20 = R5 residual).
    std.io.print("{c}", .{65});
    std.io.print("{s}", .{65});
    // B4: enum `{c}`/`{s}` (2 sites).
    const ec: C = .green; std.io.print("{c}", .{ec});
    const es: C = .green; std.io.print("{s}", .{es});
    // C4: float `{c}`/`{s}` (4 sites).
    const f64c: f64 = 65.0; std.io.print("{c}", .{f64c});
    const f64s: f64 = 65.0; std.io.print("{s}", .{f64s});
    const f32c: f32 = 65.0; std.io.print("{c}", .{f32c});
    const f32s: f32 = 65.0; std.io.print("{s}", .{f32s});
    // D2: bool `{d}`/`{x}`/`{c}`/`{s}` (4 sites).
    std.io.print("{d}", .{true});
    const bx = true; std.io.print("{x}", .{bx});
    std.io.print("{c}", .{true});
    const bs = true; std.io.print("{s}", .{bs});
    // D4/D6: `[]const u8` `{}`/`{c}`/`{d}` (3 sites).
    var ub = [_]u8{ 'h', 'i' };
    const us: []const u8 = ub[0..];
    std.io.print("{}", .{us});
    std.io.print("{c}", .{us});
    std.io.print("{d}", .{us});
    // D7: non-u8 slice `{}`/`{s}`/`{x}`/`{c}`/`{d}` (5 sites).
    const ia = [_]i32{ 1, 2, 3 };
    const is: []const i32 = &ia;
    std.io.print("{}", .{is});
    std.io.print("{s}", .{is});
    std.io.print("{x}", .{is});
    std.io.print("{c}", .{is});
    std.io.print("{d}", .{is});
    // E7: aggregates explicit specs (5 sites: struct d/x/c/s + tagged union d).
    const st = S{ .a = 1, .b = 2 };
    std.io.print("{d}", .{st});
    std.io.print("{x}", .{st});
    std.io.print("{c}", .{st});
    std.io.print("{s}", .{st});
    const tu = U{ .a = 1 };
    std.io.print("{d}", .{tu});
    // F2: error set explicit specs (4 sites).
    const esv: E = E.A;
    std.io.print("{d}", .{esv});
    std.io.print("{x}", .{esv});
    std.io.print("{c}", .{esv});
    std.io.print("{s}", .{esv});
    // G3: one-pointer to array `{}` (2 sites; Zig delegates to a slice).
    const ba = [2]u8{ 'h', 'i' };
    const bp: *const [2]u8 = &ba;
    std.io.print("{}", .{bp});
    const pa = [3]i32{ 1, 2, 3 };
    const pp: *[3]i32 = &pa;
    std.io.print("{}", .{pp});
    // G4: many-pointer `{}` (2 sites).
    const ma = [_]i32{ 1, 2, 3 };
    const mp: [*]i32 = &ma;
    std.io.print("{}", .{mp});
    var mb = [_]u8{ 'h', 'i', 0 };
    const mpb: [*]u8 = &mb;
    std.io.print("{}", .{mpb});
    // G8/G11: one-pointer `{d}`/`{s}`/`{x}` (3 sites).
    var x: i32 = 5;
    const px: *i32 = &x;
    std.io.print("{d}", .{px});
    std.io.print("{s}", .{px});
    std.io.print("{x}", .{px});
    // G9: many-pointer `{s}`/`{x}` (3 sites; Zig rejects via std.mem.span).
    std.io.print("{s}", .{mpb});
    std.io.print("{x}", .{mpb});
    std.io.print("{s}", .{mp});
    // G12: fn-pointer `{d}`/`{x}`/`{s}`/`{c}` (4 sites).
    const fp = &id;
    std.io.print("{d}", .{fp});
    std.io.print("{x}", .{fp});
    std.io.print("{s}", .{fp});
    std.io.print("{c}", .{fp});
    // H9: unknown specifier, existing check (2 sites). The second site is the
    // no-double-report control: `{q}` is already invalid, so the bool type
    // check must be suppressed and this emits exactly one error[3013].
    std.io.print("{q}", .{x});
    std.io.print("{q}", .{true});
}
