// stdlib_layout_align8_xmod — FX14 regression: the emitted C pins the Z98
// 32-bit layout model (i64/u64/f64 size 8 align 8) on every host compiler.
//
// DEFECT (before the fix): `sf/src/type_registry.zig` registers i64/u64/f64 as
// size 8 / align 8 and `@sizeOf`/`@alignOf`/`@offsetOf` fold from that model,
// but the emitted C spelled the carriers as plain `long long`/`double`
// (`sf/src/c89_emit.zig` `emitInt64Type`/`emitUint64Type`; f64 as bare
// `double` in `getCTypeName`). On i386 System V (`gcc -m32` — every gate,
// fixture and manual transcript recipe) those have align 4, so the built
// binary's layout disagreed with the values the compiler printed:
// `S{a:u8,b:i64,c:u8}` was `16/4/4/12` in the binary while Z98 reported
// `24/8/8/16`.
//
// FIX (FX14-F, operator ruling A): per-program carrier typedefs carry the
// alignment — `typedef long long <carrier> Z98_ALIGN8;`,
// `typedef unsigned long long <carrier> Z98_ALIGN8;`, plus a new f64 carrier
// `typedef double <carrier> Z98_ALIGN8;` — and `zig_compat.h`'s shared
// z64/zu64/f64 typedefs get the same `Z98_ALIGN8` (empty on MSVC/OpenWatcom,
// whose 32-bit defaults already align 8; `__attribute__((aligned(8)))` on
// gcc/clang/mingw). Every declaration site funnels through `getCTypeName`, so
// structs, unions, tagged unions, optionals, error unions, tuples, arrays and
// standalone vars all inherit the model alignment.
//
// This fixture pins BOTH sides per shape:
//   - the folded model values (`@sizeOf`/`@alignOf`/`@offsetOf`), unchanged by
//     the fix, and
//   - the REAL emitted-C layout, measured in the built binary via `@ptrToInt`
//     (field offsets and `[2]T` strides) — the check that was red before the
//     fix for every 64-bit-bearing shape.
//
// Controls (model == real on both compilers, must stay byte-identical):
// `?u8` (8/4) and the no-64-bit bool fixture set.
//
// Contract: deterministic stdout below, rc 0, byte-exact 3x.
//
//   sizeof-S=24
//   alignof-S=8
//   S-offb=8
//   S-offc=16
//   sizeof-F=24
//   alignof-F=8
//   F-offb=8
//   F-offc=16
//   sizeof-M=24
//   alignof-M=8
//   M-offc=16
//   sizeof-MS=32
//   alignof-MS=8
//   MS-offm=8
//   sizeof-A=32
//   alignof-A=8
//   A-offb=8
//   A-offc=24
//   sizeof-U=8
//   alignof-U=8
//   sizeof-US=16
//   alignof-US=8
//   US-offu=8
//   sizeof-T=16
//   alignof-T=8
//   sizeof-TS=24
//   alignof-TS=8
//   TS-offt=8
//   sizeof-O=32
//   alignof-O=8
//   O-offo=8
//   O-offc=24
//   sizeof-opti64=16
//   alignof-opti64=8
//   sizeof-optu8=8
//   alignof-optu8=4
//   sizeof-arr2f64=16
//   alignof-arr2f64=8
//   sizeof-helper-HS=24
//   alignof-helper-HS=8
//   S-real-size-ok
//   S-real-offb-ok
//   S-real-offc-ok
//   F-real-size-ok
//   F-real-offb-ok
//   F-real-offc-ok
//   A-real-size-ok
//   A-real-offb-ok
//   A-real-offc-ok
//   MS-real-offm-ok
//   US-real-offu-ok
//   TS-real-offt-ok
//   O-real-size-ok
//   O-real-offo-ok
//   O-real-offc-ok
//   HS-real-size-ok
//   HS-real-offb-ok
//   HS-real-offc-ok
//   HF-real-size-ok
//   HF-real-offb-ok
//   HF-real-offc-ok
//   f64-roundtrip-ok
//   done
const std = @import("std");
const helper = @import("helper.zig");

const S = struct { a: u8, b: i64, c: u8 };
const F = struct { a: u8, b: f64, c: u8 };
const M = struct { a: i64, b: f64, c: u64 };
const MS = struct { a: u8, m: M };
const A = struct { a: u8, b: [2]i64, c: u8 };
const U = union { x: i64, y: u8 };
const US = struct { a: u8, u: U };
const T = union(enum) { x: i64, y: u8 };
const TS = struct { a: u8, t: T };
const O = struct { a: u8, o: ?i64, c: u8 };

fn pl(n: i32) void {
    std.io.printInt(n);
    std.io.print("\n");
}

fn pv(v: i32) void {
    pl(v);
}

fn okmark(cond: bool) void {
    if (cond) {
        std.io.print("-ok\n");
    } else {
        std.io.print("-bad\n");
    }
}

fn idf(x: f64) f64 {
    return x;
}

pub fn main() void {
    std.io.print("sizeof-S="); pv(@intCast(i32, @sizeOf(S)));
    std.io.print("alignof-S="); pv(@intCast(i32, @alignOf(S)));
    std.io.print("S-offb="); pv(@intCast(i32, @offsetOf(S, "b")));
    std.io.print("S-offc="); pv(@intCast(i32, @offsetOf(S, "c")));

    std.io.print("sizeof-F="); pv(@intCast(i32, @sizeOf(F)));
    std.io.print("alignof-F="); pv(@intCast(i32, @alignOf(F)));
    std.io.print("F-offb="); pv(@intCast(i32, @offsetOf(F, "b")));
    std.io.print("F-offc="); pv(@intCast(i32, @offsetOf(F, "c")));

    std.io.print("sizeof-M="); pv(@intCast(i32, @sizeOf(M)));
    std.io.print("alignof-M="); pv(@intCast(i32, @alignOf(M)));
    std.io.print("M-offc="); pv(@intCast(i32, @offsetOf(M, "c")));
    std.io.print("sizeof-MS="); pv(@intCast(i32, @sizeOf(MS)));
    std.io.print("alignof-MS="); pv(@intCast(i32, @alignOf(MS)));
    std.io.print("MS-offm="); pv(@intCast(i32, @offsetOf(MS, "m")));

    std.io.print("sizeof-A="); pv(@intCast(i32, @sizeOf(A)));
    std.io.print("alignof-A="); pv(@intCast(i32, @alignOf(A)));
    std.io.print("A-offb="); pv(@intCast(i32, @offsetOf(A, "b")));
    std.io.print("A-offc="); pv(@intCast(i32, @offsetOf(A, "c")));

    std.io.print("sizeof-U="); pv(@intCast(i32, @sizeOf(U)));
    std.io.print("alignof-U="); pv(@intCast(i32, @alignOf(U)));
    std.io.print("sizeof-US="); pv(@intCast(i32, @sizeOf(US)));
    std.io.print("alignof-US="); pv(@intCast(i32, @alignOf(US)));
    std.io.print("US-offu="); pv(@intCast(i32, @offsetOf(US, "u")));

    std.io.print("sizeof-T="); pv(@intCast(i32, @sizeOf(T)));
    std.io.print("alignof-T="); pv(@intCast(i32, @alignOf(T)));
    std.io.print("sizeof-TS="); pv(@intCast(i32, @sizeOf(TS)));
    std.io.print("alignof-TS="); pv(@intCast(i32, @alignOf(TS)));
    std.io.print("TS-offt="); pv(@intCast(i32, @offsetOf(TS, "t")));

    std.io.print("sizeof-O="); pv(@intCast(i32, @sizeOf(O)));
    std.io.print("alignof-O="); pv(@intCast(i32, @alignOf(O)));
    std.io.print("O-offo="); pv(@intCast(i32, @offsetOf(O, "o")));
    std.io.print("O-offc="); pv(@intCast(i32, @offsetOf(O, "c")));

    std.io.print("sizeof-opti64="); pv(@intCast(i32, @sizeOf(?i64)));
    std.io.print("alignof-opti64="); pv(@intCast(i32, @alignOf(?i64)));
    std.io.print("sizeof-optu8="); pv(@intCast(i32, @sizeOf(?u8)));
    std.io.print("alignof-optu8="); pv(@intCast(i32, @alignOf(?u8)));
    std.io.print("sizeof-arr2f64="); pv(@intCast(i32, @sizeOf([2]f64)));
    std.io.print("alignof-arr2f64="); pv(@intCast(i32, @alignOf([2]f64)));

    std.io.print("sizeof-helper-HS="); pv(@intCast(i32, @sizeOf(helper.HS)));
    std.io.print("alignof-helper-HS="); pv(@intCast(i32, @alignOf(helper.HS)));

    var s: S = S{ .a = 1, .b = 2, .c = 3 };
    var sa: [2]S = undefined;
    sa[0] = s;
    sa[1] = s;
    std.io.print("S-real-size"); okmark(@intCast(i32, @ptrToInt(&sa[1])) - @intCast(i32, @ptrToInt(&sa[0])) == @intCast(i32, @sizeOf(S)));
    std.io.print("S-real-offb"); okmark(@intCast(i32, @ptrToInt(&s.b)) - @intCast(i32, @ptrToInt(&s)) == @intCast(i32, @offsetOf(S, "b")));
    std.io.print("S-real-offc"); okmark(@intCast(i32, @ptrToInt(&s.c)) - @intCast(i32, @ptrToInt(&s)) == @intCast(i32, @offsetOf(S, "c")));

    var f: F = F{ .a = 1, .b = 2.5, .c = 3 };
    var fa: [2]F = undefined;
    fa[0] = f;
    fa[1] = f;
    std.io.print("F-real-size"); okmark(@intCast(i32, @ptrToInt(&fa[1])) - @intCast(i32, @ptrToInt(&fa[0])) == @intCast(i32, @sizeOf(F)));
    std.io.print("F-real-offb"); okmark(@intCast(i32, @ptrToInt(&f.b)) - @intCast(i32, @ptrToInt(&f)) == @intCast(i32, @offsetOf(F, "b")));
    std.io.print("F-real-offc"); okmark(@intCast(i32, @ptrToInt(&f.c)) - @intCast(i32, @ptrToInt(&f)) == @intCast(i32, @offsetOf(F, "c")));

    var a: A = A{ .a = 1, .b = [2]i64{ 2, 3 }, .c = 4 };
    var aa: [2]A = undefined;
    aa[0] = a;
    aa[1] = a;
    std.io.print("A-real-size"); okmark(@intCast(i32, @ptrToInt(&aa[1])) - @intCast(i32, @ptrToInt(&aa[0])) == @intCast(i32, @sizeOf(A)));
    std.io.print("A-real-offb"); okmark(@intCast(i32, @ptrToInt(&a.b)) - @intCast(i32, @ptrToInt(&a)) == @intCast(i32, @offsetOf(A, "b")));
    std.io.print("A-real-offc"); okmark(@intCast(i32, @ptrToInt(&a.c)) - @intCast(i32, @ptrToInt(&a)) == @intCast(i32, @offsetOf(A, "c")));

    var ms: MS = undefined;
    std.io.print("MS-real-offm"); okmark(@intCast(i32, @ptrToInt(&ms.m)) - @intCast(i32, @ptrToInt(&ms)) == @intCast(i32, @offsetOf(MS, "m")));

    var us: US = undefined;
    std.io.print("US-real-offu"); okmark(@intCast(i32, @ptrToInt(&us.u)) - @intCast(i32, @ptrToInt(&us)) == @intCast(i32, @offsetOf(US, "u")));

    var ts: TS = undefined;
    std.io.print("TS-real-offt"); okmark(@intCast(i32, @ptrToInt(&ts.t)) - @intCast(i32, @ptrToInt(&ts)) == @intCast(i32, @offsetOf(TS, "t")));

    var o: O = undefined;
    var oa: [2]O = undefined;
    oa[0] = o;
    oa[1] = o;
    std.io.print("O-real-size"); okmark(@intCast(i32, @ptrToInt(&oa[1])) - @intCast(i32, @ptrToInt(&oa[0])) == @intCast(i32, @sizeOf(O)));
    std.io.print("O-real-offo"); okmark(@intCast(i32, @ptrToInt(&o.o)) - @intCast(i32, @ptrToInt(&o)) == @intCast(i32, @offsetOf(O, "o")));
    std.io.print("O-real-offc"); okmark(@intCast(i32, @ptrToInt(&o.c)) - @intCast(i32, @ptrToInt(&o)) == @intCast(i32, @offsetOf(O, "c")));

    var hs: helper.HS = helper.makeHS(1, 2, 3);
    var hsa: [2]helper.HS = undefined;
    hsa[0] = hs;
    hsa[1] = hs;
    std.io.print("HS-real-size"); okmark(@intCast(i32, @ptrToInt(&hsa[1])) - @intCast(i32, @ptrToInt(&hsa[0])) == @intCast(i32, @sizeOf(helper.HS)));
    std.io.print("HS-real-offb"); okmark(@intCast(i32, @ptrToInt(&hs.b)) - @intCast(i32, @ptrToInt(&hs)) == @intCast(i32, @offsetOf(helper.HS, "b")));
    std.io.print("HS-real-offc"); okmark(@intCast(i32, @ptrToInt(&hs.c)) - @intCast(i32, @ptrToInt(&hs)) == @intCast(i32, @offsetOf(helper.HS, "c")));

    var hf: helper.HF = helper.makeHF(1, 2.5, 3);
    var hfa: [2]helper.HF = undefined;
    hfa[0] = hf;
    hfa[1] = hf;
    std.io.print("HF-real-size"); okmark(@intCast(i32, @ptrToInt(&hfa[1])) - @intCast(i32, @ptrToInt(&hfa[0])) == @intCast(i32, @sizeOf(helper.HF)));
    std.io.print("HF-real-offb"); okmark(@intCast(i32, @ptrToInt(&hf.b)) - @intCast(i32, @ptrToInt(&hf)) == @intCast(i32, @offsetOf(helper.HF, "b")));
    std.io.print("HF-real-offc"); okmark(@intCast(i32, @ptrToInt(&hf.c)) - @intCast(i32, @ptrToInt(&hf)) == @intCast(i32, @offsetOf(helper.HF, "c")));

    if (idf(2.5) == @as(f64, 2.5)) {
        std.io.print("f64-roundtrip-ok\n");
    } else {
        std.io.print("f64-roundtrip-bad\n");
    }

    std.io.print("done\n");
}
