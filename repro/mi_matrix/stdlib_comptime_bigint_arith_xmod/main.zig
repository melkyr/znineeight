// stdlib_comptime_bigint_arith_xmod — Task 2 (ComptimeInt core + arithmetic)
// positive runtime fixture.
//
// Pins arbitrary-precision comptime arithmetic (Zig `comptime_int` parity):
// every expression below evaluates UNTYPED arithmetic whose exact intermediate
// magnitude exceeds 64 bits (up to 2^200), and the final result is materialised
// into a u64/i64 slot with `@as` and printed. The OLD 64-bit fold wrapped or
// truncated these shapes (and left `1 << 100` unfolded), so the emitted C ran
// wrong values; the new big-int core folds the exact result and the lowerer
// emits the exact constant.
//
// Covered:
//   * add/sub/mul/div/mod at 2^64 and 2^100 magnitudes (no wrap);
//   * Zig-truncating division and remainder signs (`e`/`f`);
//   * floor right shift on a negative magnitude (`g`);
//   * exact left shift beyond 64 bits, shifted back down (`h`);
//   * bitwise ops on an infinite two's-complement negative (`i`, `u`, `v`) and
//     the Z98-only `~` (`w`; the Zig twin spells it `-x - 1`);
//   * exact multiplication beyond 64 bits, positive and negative (`r`, `s`);
//   * bitwise OR/XOR beyond 64 bits (`t`, `u`);
//   * far floor shifts: negative -> -1, positive -> 0 (`x1`, `x2`);
//   * all four truncated div/mod sign combinations (`x3`-`x6`) and a
//     quotient-3 division across the 2^63 boundary (`x7`);
//   * exact multi-word left shifts whose reduced results are observable
//     (`y1` = 2^164 >> 164, `y2` = 2^64 >> 32) — review fix coverage for the
//     `word > 0` cap path (the cap-overflow twins themselves are only
//     observable as unfolds until Task 4, so they live in the unit test);
//   * u64 max via `(1 << 64) - 1` (`j`);
//   * mixed-sign exact subtraction (`k`);
//   * no-over-rejection controls: in-range arithmetic keeps folding and
//     materialising exactly (`l`, `m`, `n`, `o`, `p`).
//
// Oracle: official Zig 0.15.2 twin with `@rem` for the signed remainder
// (Zig rejects `%` on signed comptime_int; Z98's `%` is the runtime C-`%`
// truncating form, so the fixture's expected value is the `@rem` value).
// Every value is Zig-0.15.2-checked.
//
// Contract: stdout below, rc 0, byte-exact 3x.
//
//   a=9223372036854775808
//   b=1024
//   c=12345
//   d=6148914691236517205
//   e=-9223372036854775808
//   f=-1
//   g=-9223372036854775808
//   h=1024
//   i=255
//   j=18446744073709551615
//   k=9223372036854775808
//   l=-2
//   m=0
//   n=1099511627781
//   o=-1537228672809129301
//   p=9223372036854775805
//   r=48
//   s=-48
//   t=17
//   u=-1
//   v=-2
//   w=-4611686018427387905
//   x1=-1
//   x2=0
//   x3=-3
//   x4=-3
//   x5=-1
//   x6=1
//   x7=3
//   y1=1
//   y2=4294967296
const std = @import("std");

pub fn main() void {
    const a: u64 = @as(u64, ((1 << 64) + 1) / 2);
    const b: u64 = @as(u64, ((1 << 100) + 12345) / (1 << 90));
    const c: u64 = @as(u64, ((1 << 100) + 12345) % (1 << 90));
    const d: u64 = @as(u64, ((1 << 64) - 1) / 3);
    const e: i64 = @as(i64, (0 - (1 << 64)) / 2);
    const f: i64 = @as(i64, (0 - ((1 << 64) + 3)) % 2);
    const g: i64 = @as(i64, (0 - (1 << 64)) >> 1);
    const h: u64 = @as(u64, (1 << 200) >> 190);
    const i: i64 = @as(i64, ((0 - (1 << 100)) - 1) & 0xFF);
    const j: u64 = @as(u64, (1 << 64) - 1);
    const k: u64 = @as(u64, (1 << 64) + (0 - (1 << 63)));
    const l: i64 = @as(i64, ((0 - (1 << 100)) - 1) >> 100);
    const m: u64 = @as(u64, (1 << 100) - (1 << 100));
    const n: u64 = @as(u64, (1 << 40) + 5);
    const o: i64 = @as(i64, (0 - (1 << 62)) / 3);
    const p: u64 = @as(u64, ((1 << 64) - 3) % (1 << 63));
    const r: u64 = @as(u64, ((1 << 100) * 3) >> 96);
    const s: i64 = @as(i64, ((0 - (1 << 100)) * 3) >> 96);
    const t: u64 = @as(u64, ((1 << 100) | (1 << 96)) >> 96);
    const u: i64 = @as(i64, ((0 - (1 << 100)) ^ ((1 << 100) - 1)));
    const v: i64 = @as(i64, (((0 - (1 << 100)) | 3) >> 99));
    const w: i64 = @as(i64, ~(1 << 62));
    const x1: i64 = @as(i64, (0 - 1) >> 200);
    const x2: u64 = @as(u64, (1 << 100) >> 200);
    const x3: i64 = @as(i64, (0 - 7) / 2);
    const x4: i64 = @as(i64, 7 / (0 - 2));
    const x5: i64 = @as(i64, (0 - 7) % 2);
    const x6: i64 = @as(i64, 7 % (0 - 2));
    const x7: u64 = @as(u64, ((1 << 63) + (1 << 64)) / (1 << 63));
    const y1: u64 = @as(u64, ((1 << 100) << 64) >> 164);
    const y2: u64 = @as(u64, ((1 << 32) << 32) >> 32);
    if (c != 12345) { @panic("bigint mod"); }
    if (h != 1024) { @panic("bigint shr"); }
    if (n != 1099511627781) { @panic("in-range add"); }
    if (r != 48 or t != 17 or x7 != 3) { @panic("bigint mul/bit/div"); }
    if (y1 != 1 or y2 != 4294967296) { @panic("bigint shl word"); }
    std.io.print("a={}\n", .{a});
    std.io.print("b={}\n", .{b});
    std.io.print("c={}\n", .{c});
    std.io.print("d={}\n", .{d});
    std.io.print("e={}\n", .{e});
    std.io.print("f={}\n", .{f});
    std.io.print("g={}\n", .{g});
    std.io.print("h={}\n", .{h});
    std.io.print("i={}\n", .{i});
    std.io.print("j={}\n", .{j});
    std.io.print("k={}\n", .{k});
    std.io.print("l={}\n", .{l});
    std.io.print("m={}\n", .{m});
    std.io.print("n={}\n", .{n});
    std.io.print("o={}\n", .{o});
    std.io.print("p={}\n", .{p});
    std.io.print("r={}\n", .{r});
    std.io.print("s={}\n", .{s});
    std.io.print("t={}\n", .{t});
    std.io.print("u={}\n", .{u});
    std.io.print("v={}\n", .{v});
    std.io.print("w={}\n", .{w});
    std.io.print("x1={}\n", .{x1});
    std.io.print("x2={}\n", .{x2});
    std.io.print("x3={}\n", .{x3});
    std.io.print("x4={}\n", .{x4});
    std.io.print("x5={}\n", .{x5});
    std.io.print("x6={}\n", .{x6});
    std.io.print("x7={}\n", .{x7});
    std.io.print("y1={}\n", .{y1});
    std.io.print("y2={}\n", .{y2});
}
