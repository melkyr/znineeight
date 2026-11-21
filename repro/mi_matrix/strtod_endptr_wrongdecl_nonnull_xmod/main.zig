// strtod_endptr_wrongdecl_nonnull_xmod — Task 0o2 pin (EXPECTED WARNING).
//
// The `strtod` extern declaration below is type-WRONG for libc: `endptr` is
// declared `?[*]const c_char` (C `const char*`), but `<stdlib.h>`'s real
// prototype is `double strtod(const char*, char**)`. Z98 emits no prototype for
// extern fns, so gcc type-checks the call against `<stdlib.h>`.
//
// Task 0o removed the spurious warning for a STATICALLY-NULL endptr (a null
// pointer constant is compatible with any object-pointer parameter). A NON-NULL
// endptr is a genuine type mismatch and still produces non-conforming C:
//
//   warning: passing argument 2 of 'strtod' from incompatible pointer type
//            [-Wincompatible-pointer-types]
//
// This fixture pins that behaviour (the offending syntax). The canonical
// examples/z98/json_parser* copies are FIXED to `?*[*]c_char`; examples/zig0/*
// still carry this wrong declaration (declared in EXPECTED_FAIL.md).
//
// `nptr` is a non-literal local buffer (not a string literal) so the fixture
// carries no Task-0p `string_const` shape-1/2 warning; the only warning is the
// endptr mismatch. The non-null endptr points at a writable 8-byte slot, so the
// run is memory-safe (strtod writes one pointer into it). Contract: gcc rc=0
// WITH the `-Wincompatible-pointer-types` warning; link rc=0; run rc=0,
// stdout `1`.
@cInclude("<stdlib.h>");
extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;
const std = @import("std");

pub fn main() void {
    var buf: [8]u8 = undefined;
    buf[0] = '3';
    buf[1] = '.';
    buf[2] = '5';
    buf[3] = 0;
    var slot: [8]u8 = undefined;
    var endp: [*]const c_char = @ptrCast([*]const c_char, &slot[0]);
    var v: f64 = strtod(@ptrCast([*]const c_char, &buf[0]), endp);
    if (v > 3.4 and v < 3.6) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
    std.io.writeByte('\n');
}
