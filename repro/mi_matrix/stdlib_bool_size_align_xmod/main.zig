// stdlib_bool_size_align_xmod — Task 11L regression: `bool` is 1 byte / align 1,
// matching Zig.
//
// DEFECT (before the fix): `type_registry.zig` registered `bool` with size 4 /
// align 4 and `c89_emit.zig` mapped `bool` to C `int`. Zig's `bool` is 1 byte /
// align 1, so `@sizeOf(bool)`/`@alignOf(bool)` were wrong and every struct /
// array with a bool field was oversized. The registry and the C emission MUST
// change together: the folded `@sizeOf`/`@offsetOf` come from the registry while
// the actual C layout comes from the emitted type, so a registry-only or
// emission-only change would make Z98's folded layout disagree with gcc's
// layout of the emitted C.
//
// FIX (Task 11L):
//   - `sf/src/type_registry.zig`: bool size/align 4/4 -> 1/1;
//   - `sf/src/c89_emit.zig` `getCTypeName`: bool C type `int` -> `unsigned char`;
//   - `intTypeByteWidth` bool -> 1; `classifyIntSignedness` bool -> unsigned.
//
// The fixture pins the folded layout (runtime stdout) AND cross-checks it
// against the EMITTED C layout via `@ptrToInt` self-consistency (a registry-only
// fix would make the struct field pointer differ from `@offsetOf`) and the
// `[*]bool` stride. Residuals NOT fixed here (documented, out of scope):
// `?bool` stays 8 bytes and `E!bool` keeps a 4-byte floor.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   sizeof-bool=1
//   alignof-bool=1
//   bitsizeof-bool=1
//   sizeof-arr4=4
//   alignof-arr4=1
//   SB-size=2
//   SB-offa=0
//   SB-offb=1
//   S3-size=3
//   S3-offb=1
//   SU-size=12
//   SU-offa=0
//   SU-offb=4
//   SU-offc=8
//   S5-size=5
//   U1-size=1
//   U1-align=1
//   selfconsistency-ok
//   stride-ok
//   roundtrip-true-ok
//   roundtrip-false-ok
//   done
const std = @import("std");

const SB = struct { a: bool, b: bool };
const S3 = struct { a: u8, b: bool, c: u8 };
const SU = struct { a: bool, b: u32, c: bool };
const S5 = struct { a: bool, b: bool, c: bool, d: bool, e: bool };
const U1 = union { b: bool };

fn idb(b: bool) bool {
    return b;
}

pub fn main() void {
    std.io.print("sizeof-bool=");
    std.io.printInt(@intCast(i32, @sizeOf(bool)));
    std.io.print("\n");
    std.io.print("alignof-bool=");
    std.io.printInt(@intCast(i32, @alignOf(bool)));
    std.io.print("\n");
    std.io.print("bitsizeof-bool=");
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.print("\n");

    std.io.print("sizeof-arr4=");
    std.io.printInt(@intCast(i32, @sizeOf([4]bool)));
    std.io.print("\n");
    std.io.print("alignof-arr4=");
    std.io.printInt(@intCast(i32, @alignOf([4]bool)));
    std.io.print("\n");

    std.io.print("SB-size=");
    std.io.printInt(@intCast(i32, @sizeOf(SB)));
    std.io.print("\n");
    std.io.print("SB-offa=");
    std.io.printInt(@intCast(i32, @offsetOf(SB, "a")));
    std.io.print("\n");
    std.io.print("SB-offb=");
    std.io.printInt(@intCast(i32, @offsetOf(SB, "b")));
    std.io.print("\n");

    std.io.print("S3-size=");
    std.io.printInt(@intCast(i32, @sizeOf(S3)));
    std.io.print("\n");
    std.io.print("S3-offb=");
    std.io.printInt(@intCast(i32, @offsetOf(S3, "b")));
    std.io.print("\n");

    std.io.print("SU-size=");
    std.io.printInt(@intCast(i32, @sizeOf(SU)));
    std.io.print("\n");
    std.io.print("SU-offa=");
    std.io.printInt(@intCast(i32, @offsetOf(SU, "a")));
    std.io.print("\n");
    std.io.print("SU-offb=");
    std.io.printInt(@intCast(i32, @offsetOf(SU, "b")));
    std.io.print("\n");
    std.io.print("SU-offc=");
    std.io.printInt(@intCast(i32, @offsetOf(SU, "c")));
    std.io.print("\n");

    std.io.print("S5-size=");
    std.io.printInt(@intCast(i32, @sizeOf(S5)));
    std.io.print("\n");

    std.io.print("U1-size=");
    std.io.printInt(@intCast(i32, @sizeOf(U1)));
    std.io.print("\n");
    std.io.print("U1-align=");
    std.io.printInt(@intCast(i32, @alignOf(U1)));
    std.io.print("\n");

    var s: SB = SB{ .a = true, .b = false };
    const off_b: i32 = @intCast(i32, @offsetOf(SB, "b"));
    const ptr_b: i32 = @intCast(i32, @ptrToInt(&s.b)) - @intCast(i32, @ptrToInt(&s));
    if (ptr_b == off_b) {
        std.io.print("selfconsistency-ok\n");
    } else {
        std.io.print("selfconsistency-bad\n");
    }

    var v: [4]bool = undefined;
    v[0] = true;
    v[1] = false;
    v[2] = true;
    v[3] = false;
    const stride: i32 = @intCast(i32, @ptrToInt(&v[3])) - @intCast(i32, @ptrToInt(&v[0]));
    if (stride == 3) {
        std.io.print("stride-ok\n");
    } else {
        std.io.print("stride-bad\n");
    }

    if (idb(true)) {
        std.io.print("roundtrip-true-ok\n");
    } else {
        std.io.print("roundtrip-true-bad\n");
    }
    if (idb(false)) {
        std.io.print("roundtrip-false-bad\n");
    } else {
        std.io.print("roundtrip-false-ok\n");
    }

    std.io.print("done\n");
}
