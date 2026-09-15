// nonliteral_ptr_to_slice_xmod — COMPILE-FAIL fixture (gcc rejects the emitted C).
//
// F-M4 (Track4 S22), FIXED in Task 0h (A1 root cause): string literals are now
// typed `*const [N]u8` (length in the type). A bare `*const u8` carries no
// length, so `*const u8 -> []const u8` is NO LONGER a coercion — it was removed
// from `coercion.classifyCoercion` and `typeRegistryIsAssignable` — and must not
// silently become a length-1 slice.
//
// Here `pick` takes bare `*const u8` params and coerces them to a slice. The
// frontend no longer records/inserts a `make_slice` (no length source), so the
// emitted C assigns a raw pointer to a Slice and gcc rejects it:
//   error: incompatible types when assigning to type
//          'zT_..._Slice_zT_..._u' from type 'unsigned char *'
// Pre-fix the emitted C hard-coded `len = 1` and RAN with the wrong length
// (stdout `h|1`/`w|1`, run rc=133); there is no runtime GREEN contract now.
//
// Corpus class: FAIL (gcc). Declared in repro/mi_matrix/EXPECTED_FAIL.md.
//
// Declared by Task 0g; FIXED by Task 0h.
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
