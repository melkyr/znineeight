// print_ptr_name_cap_reject_xmod — Task 8 (z98-print-formatting Amendment 1,
// B2 + B3) reject fixture: the two pointer-name caps, both clean
// `error[3063]` (rc 2, 0 `.c`, 2 sites).
//
//  1. Rendered-name byte budget: `*E512` whose `error{...}` name is EXACTLY
//     512 bytes (46 x 10-char members: 6 + 460 + 45 + 1 = 512); the emitter's
//     512-byte buffer plus the trailing `@` needs 513, so the validator's byte
//     mirror rejects. Before Task 8 this was accepted rc=0 and the value was
//     silently dropped (the program printed `pe=` with no name/address).
//  2. Structural depth cap 16: struct field `*A16` where A16 is a 16-wrapper
//     `?*?*?*?*?*?*?*?*i32` chain; the validator's name walk exceeds depth 16.
//
// ORACLE NOTE: official Zig 0.15.2 accepts and prints BOTH shapes (arbitrarily
// long `@typeName`; arbitrary pointer depth). The two caps are documented Z98
// bounded residuals (Language_Spec §4) — clean rejects, never broken C.
const std = @import("std");

const A16 = ?*?*?*?*?*?*?*?*i32;
const S16 = struct { p: *A16, n: i32 };

const E512 = error{
    E00aaaaaaa, E01aaaaaaa, E02aaaaaaa, E03aaaaaaa, E04aaaaaaa,
    E05aaaaaaa, E06aaaaaaa, E07aaaaaaa, E08aaaaaaa, E09aaaaaaa,
    E10aaaaaaa, E11aaaaaaa, E12aaaaaaa, E13aaaaaaa, E14aaaaaaa,
    E15aaaaaaa, E16aaaaaaa, E17aaaaaaa, E18aaaaaaa, E19aaaaaaa,
    E20aaaaaaa, E21aaaaaaa, E22aaaaaaa, E23aaaaaaa, E24aaaaaaa,
    E25aaaaaaa, E26aaaaaaa, E27aaaaaaa, E28aaaaaaa, E29aaaaaaa,
    E30aaaaaaa, E31aaaaaaa, E32aaaaaaa, E33aaaaaaa, E34aaaaaaa,
    E35aaaaaaa, E36aaaaaaa, E37aaaaaaa, E38aaaaaaa, E39aaaaaaa,
    E40aaaaaaa, E41aaaaaaa, E42aaaaaaa, E43aaaaaaa, E44aaaaaaa,
    E45aaaaaaa,
};

pub fn main() void {
    var pe: *E512 = @intToPtr(*E512, 0x512);
    std.io.print("pe={}\n", .{pe});

    var s16 = S16{ .p = @intToPtr(*A16, 0x1600), .n = 16 };
    std.io.print("s16={}\n", .{s16});
}
