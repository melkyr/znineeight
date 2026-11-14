// print_fmt_noprinter_reject_xmod — Task 3 (z98-print-formatting) reject
// fixture: argument types with no std.fmt printer, error[3063] at the ARGUMENT
// span.
//
// Frozen table `.superpowers/sdd/2026-09-22-z98-print-formatting-plan/task-0-report.md`
// rows D5/F4/F6/G6/G7/H1/H2/H3/H4/H4b/H5/H6/H7, including the operator-ruled
// Q3 bounded residuals where Zig accepts and the plan deliberately does not
// implement: `[]const u8 {x}` (D5), `[N]u8`/`[N]T` `{s}`/`{x}` (H2/H3),
// `*const [N]u8 {s}`/`{x}` (G7), `void`/`null`/`type` (H4/H4b/H5/H6). The
// `undefined` row (H7), arrays (H1) and optional/error-union/fn-body are
// Zig-rejected too, so the clean reject matches the oracle.
//
// Contract: dump rc=2, 0 `.c`, exactly 20 x error[3063], 0 x error[3013]
// (canonical classifier FAIL). The H4 void site would SIGSEGV the compiler
// without the `TEMP_NONE`/temp-range guard in `lowerPrintFmt`.
const std = @import("std");
const E = error{ A };
fn foo() void {}

pub fn main() void {
    // D5: `[]const u8 {x}` (Q3 residual; Zig accepts byte-hex) (1 site).
    var rb = [_]u8{ 'h', 'i' };
    const rs: []const u8 = rb[0..];
    std.io.print("{x}", .{rs});
    // F4/F6: optional / error-union `{}` (2 sites).
    const o: ?i32 = 5;
    std.io.print("{}", .{o});
    const eu: E!i32 = 5;
    std.io.print("{}", .{eu});
    // G6: function body value `{}` (1 site).
    std.io.print("{}", .{foo});
    // G7: byte-view pointers / string literal (Q3 residual) (3 sites).
    const ba = [2]u8{ 'h', 'i' };
    const bp: *const [2]u8 = &ba;
    std.io.print("{s}", .{bp});
    std.io.print("{x}", .{bp});
    std.io.print("{s}", .{"hi"});
    // H1: array `{}`/`{d}`/`{c}` (3 sites).
    const ia = [3]i32{ 1, 2, 3 };
    std.io.print("{}", .{ia});
    std.io.print("{d}", .{ia});
    std.io.print("{c}", .{ia});
    // H2: `[N]u8` `{s}`/`{x}` (Q3 residual) (2 sites).
    const ua = [2]u8{ 'h', 'i' };
    std.io.print("{s}", .{ua});
    std.io.print("{x}", .{ua});
    // H3: `[N]T`, T!=u8, `{s}`/`{x}` (2 sites).
    std.io.print("{s}", .{ia});
    std.io.print("{x}", .{ia});
    // H4/H4b: `void` `{}` alone and as a later argument (2 sites).
    std.io.print("{}", .{foo()});
    std.io.print("a={} b={}", .{1, foo()});
    // H5: `null` `{}` (Q3 residual) (1 site).
    std.io.print("{}", .{null});
    // H6: `type` `{}` (Q3 residual) (1 site).
    std.io.print("{}", .{u32});
    // H7: `undefined` `{}`/`{d}` (Zig rejects) (2 sites).
    std.io.print("{}", .{undefined});
    std.io.print("{d}", .{undefined});
}
