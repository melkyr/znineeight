// empty_named_struct_field_xmod — A2 regression: an empty struct as a field.
//
// DEFECT (seed v90): an empty named `struct {}` kept `payload_idx = 0` (see
// `empty_named_struct_xmod`), so nesting it as a field aliased another struct's
// payload and the compiler rejected the program with
// `error[24]: circular type dependency detected (type refers to itself)`.
//
// FIX (A2-F): container kinds are always populated, so `E` gets a real empty
// `StructPayload` (size 1 / align 1) and the emitter writes
// `unsigned char _[1];` for the empty C struct, keeping the real layout in
// step with the folded one.
//
// GREEN contract: rc 0 and stdout `1\n1\n2` (RUNRC 0): `@sizeOf(E)` is 1,
// `e` sits at offset 1, `b` at offset 2.
// Seed v90 is RED: dump rc 2, `error[24]` circular.
const std = @import("std");
const E = struct {};
const S = struct { a: u8, e: E, b: u8 };
fn pl(n: i32) void { std.io.printInt(n); std.io.print("\n"); }
pub fn main() void {
    pl(@intCast(i32, @sizeOf(E)));
    pl(@intCast(i32, @offsetOf(S, "e")));
    pl(@intCast(i32, @offsetOf(S, "b")));
}
