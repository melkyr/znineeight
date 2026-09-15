// nonliteral_ptr_to_slice_xmod — RUNTIME-RED fixture (compile-gate OK, run rc=133).
//
// F-M4 (Track4 S22 residual). `sf/src/lower.zig` `materializeInto`'s no-wrap-layer path
// (:2029-2035) and its error-union/optional payload path (:2048-2050) synthesize a
// `string_to_slice` coercion with `.node_idx = src_node` and call `applyCoercion`.
// `applyCoercion` (:6631-6646) sets the slice length from the string literal ONLY when
// `node_idx` is an `AstKind.string_literal`; for any other node it defaults `sllen = 1`
// (:6633). `coercion.classifyCoercion` returns `string_to_slice` for ANY
// `*const u8`/`*const c_char` -> `[]const u8` (coercion.zig:193-200), so a NON-literal
// pointer coerced to a slice on this path SILENTLY becomes a LENGTH-1 slice.
//
// Reachable construct (verified): `pick` takes `*const u8` params and does
// `var s: []const u8 = if (c) p else q;`. The if-expr arms are identifier nodes (NOT
// string literals), so materializeInto -> applyCoercion emits a hard-coded `len = 1`:
//     zT_6 = 1; zT_5.ptr = p; zT_5.len = zT_6;   (emitted main_*.c, RED)
// The pointers originate from the 5-byte literal "hello" and the 7-byte literal "world!!",
// so the real lengths are 5 and 7. RED stdout `h|1` then `w|1` (written unbuffered via
// `std.io.fileWrite` so the evidence survives the assert trap); the `a.len != 5` assert
// then traps (run rc=133).
//
// GREEN contract (once F-M4 is closed, Task 0h): stdout `hello|5` then `world!!|7`, run
// rc=0.
//
// Declared by Task 0g; the fix (if any) is Task 0h. NOT fixed here.
const std = @import("std");

fn pick(p: *const u8, q: *const u8, c: bool) []const u8 {
    var s: []const u8 = if (c) p else q;
    return s;
}

fn eq(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (actual[i] != expected[i]) return false;
    }
    return true;
}

fn writeLen(n: usize) void {
    var digits: [1]u8 = undefined;
    digits[0] = @intCast(u8, @intCast(i32, 48) + @intCast(i32, n));
    std.io.fileWrite(1, digits[0..1]);
}

fn show(s: []const u8) void {
    std.io.fileWrite(1, s);
    var bar: [1]u8 = undefined;
    bar[0] = '|';
    std.io.fileWrite(1, bar[0..1]);
    writeLen(s.len);
    var nl: [1]u8 = undefined;
    nl[0] = '\n';
    std.io.fileWrite(1, nl[0..1]);
}

pub fn main() void {
    var a = pick("hello", "world!!", true);
    show(a);
    var b = pick("hello", "world!!", false);
    show(b);
    if (a.len != 5) { @panic("nonliteral_ptr_to_slice_xmod: F-M4 non-literal *const u8 -> []const u8 len != 5 (silently length-1)"); }
    if (!eq(a, "hello")) { @panic("nonliteral_ptr_to_slice_xmod: F-M4 bytes != hello"); }
    if (b.len != 7) { @panic("nonliteral_ptr_to_slice_xmod: F-M4 non-literal *const u8 -> []const u8 len != 7 (silently length-1)"); }
    if (!eq(b, "world!!")) { @panic("nonliteral_ptr_to_slice_xmod: F-M4 bytes != world!!"); }
}
