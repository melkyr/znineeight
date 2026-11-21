// stdlib_mem_xmod — STDLIB std_mem raw-memory helpers GREEN fixture.
//
// std_mem.zig is a PURE (no externs, no cstdio) Z98 module re-exported from
// std.zig as `mem`; this fixture imports it via a BARE `@import("std")` and
// exercises every public function: copyU8 / copyU32 / copyU64 / zeroU8 /
// eqlU8. Z98 has NO generics / comptime type params, so the module ships
// CONCRETE per-width variants (the design-spec §3.2 generic `copy` is
// deliberately NOT provided).
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - u32 and u64 integer widths through real multi-byte stores: a u32 value
//     with bit 8 set (256 = 0x00000100) must land as exactly FOUR bytes and a
//     u64 value 2^32 (bit 32 set) as exactly EIGHT bytes (little-endian
//     x86/lx host — the byte lanes are read back to prove the width + that no
//     extra bytes were clobbered past the copy)
//   - [*]T many-pointer parameters, *T -> [*]T / *T -> [*]const T coercion,
//     @ptrCast to a wider pointee type
//   - 64-bit `<<` shift on a u64, i32 negative handling in printInt
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0), one
// result per line (std.io.printInt + '\n'):
//   1       copyU8 then eqlU8 true
//   0       eqlU8 false after one byte differs
//   1       zeroU8 zeroes all 6 bytes
//   200     copyU32 dst[1]
//   300     copyU32 dst[2]
//   0       u32 256 written at b4[0] (LSB byte 0)
//   1       u32 256 written at b4[1] (byte 0x01) — 4-byte little-endian store
//   0       b4[7] untouched (store was exactly 4 bytes)
//   2000000 copyU64 dst64[1]
//   0       u64 2^32 written at b8[0]
//   1       u64 2^32 written at b8[4] (bit 32 lands in the high dword)
//   0       b8[8] untouched (store was exactly 8 bytes)
const std = @import("std");

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn pb(cond: bool) void {
    if (cond) {
        p(1);
    } else {
        p(0);
    }
}

pub fn main() void {
    var s8: [6]u8 = undefined;
    var d8: [6]u8 = undefined;
    s8[0] = 1;
    s8[1] = 2;
    s8[2] = 3;
    s8[3] = 4;
    s8[4] = 5;
    s8[5] = 6;
    std.mem.copyU8(&d8[0], &s8[0], 6);
    pb(std.mem.eqlU8(&d8[0], &s8[0], 6));
    d8[3] = 0;
    pb(std.mem.eqlU8(&d8[0], &s8[0], 6));
    std.mem.zeroU8(&d8[0], 6);
    var zok: i32 = 1;
    var z: usize = 0;
    while (z < 6) : (z += 1) {
        if (d8[z] != 0) {
            zok = 0;
        }
    }
    p(zok);

    var s32: [3]u32 = undefined;
    var d32: [3]u32 = undefined;
    s32[0] = 100;
    s32[1] = 200;
    s32[2] = 300;
    std.mem.copyU32(&d32[0], &s32[0], 3);
    p(@intCast(i32, d32[1]));
    p(@intCast(i32, d32[2]));

    var s64: [2]u64 = undefined;
    var d64: [2]u64 = undefined;
    s64[0] = 1000000;
    s64[1] = 2000000;
    std.mem.copyU64(&d64[0], &s64[0], 2);
    p(@intCast(i32, d64[1]));

    var b4: [8]u8 = undefined;
    std.mem.zeroU8(&b4[0], 8);
    var v32: u32 = 256;
    std.mem.copyU32(@ptrCast([*]u32, &b4[0]), &v32, 1);
    p(@intCast(i32, b4[0]));
    p(@intCast(i32, b4[1]));
    p(@intCast(i32, b4[7]));

    var b8: [16]u8 = undefined;
    std.mem.zeroU8(&b8[0], 16);
    var v64: u64 = @intCast(u64, 1);
    v64 = v64 << 32;
    std.mem.copyU64(@ptrCast([*]u64, &b8[0]), &v64, 1);
    p(@intCast(i32, b8[0]));
    p(@intCast(i32, b8[4]));
    p(@intCast(i32, b8[8]));
}
