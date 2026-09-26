// union_offset_reject_xmod — FF (Volume II D9) reject fixture.
//
// Zig-0.15.2 parity: `@offsetOf`/`@bitOffsetOf` are struct-only. Every union
// kind rejects with level-0 `error[3072]` `expected struct type, found 'X'`
// (the packed-union offset fold is deleted; the former lowering net raised the
// internal `error[3043]`), an unknown or non-literal struct field name rejects
// with `error[3073]`, and an unresolved type argument or a wrong argument
// count rejects with `error[3074]`. No shape may ICE, and no `.c` is emitted.
//
// Shapes (exact census below is re-counted from the FF compiler run):
//   bare-union offset, tagged-union bit offset, packed-union offset,
//   packed-union bit offset, scalar target, cross-module helper site  -> 3072
//   unknown struct field, non-literal name (`const N`), int name       -> 3073
//   missing argument, extra argument, `@sizeOf` extra argument,
//   unresolved type (`Nope`)                                            -> 3074
// Controls that stay clean (in helper.zig's positive shape): the struct
// offsets used by the positive fixture are untouched.
const std = @import("std");
const helper = @import("helper.zig");

const Raw = union { i: i32, u: u32 };
const T = union(enum) { i: i32, u: u32 };
const PU = packed union { a: u4, b: u4 };
const S = struct { a: i32, b: u32 };
const N = "a";

fn bareOffset() void {
    std.io.print("x={}\n", .{@offsetOf(Raw, "i")});
}

fn taggedBitOffset() void {
    std.io.print("x={}\n", .{@bitOffsetOf(T, "i")});
}

fn packedOffset() void {
    std.io.print("x={}\n", .{@offsetOf(PU, "a")});
}

fn packedBitOffset() void {
    std.io.print("x={}\n", .{@bitOffsetOf(PU, "a")});
}

fn scalarOffset() void {
    std.io.print("x={}\n", .{@offsetOf(i32, "x")});
}

fn unknownField() void {
    std.io.print("x={}\n", .{@offsetOf(S, "nope")});
}

fn constName() void {
    std.io.print("x={}\n", .{@offsetOf(S, N)});
}

fn intName() void {
    std.io.print("x={}\n", .{@offsetOf(S, 1)});
}

fn missingArg() void {
    std.io.print("x={}\n", .{@offsetOf(S)});
}

fn extraArg() void {
    std.io.print("x={}\n", .{@offsetOf(S, "a", 1)});
}

fn sizeofExtra() void {
    std.io.print("x={}\n", .{@sizeOf(S, 1)});
}

fn unresolvedType() void {
    std.io.print("x={}\n", .{@sizeOf(Nope)});
}

pub fn main() void {
    bareOffset();
    taggedBitOffset();
    packedOffset();
    packedBitOffset();
    scalarOffset();
    unknownField();
    constName();
    intName();
    missingArg();
    extraArg();
    sizeofExtra();
    unresolvedType();
    helper.badOffset();
}
