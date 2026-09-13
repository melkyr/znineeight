// volatile_fastpaths_xmod — GREEN (A10F G1/G2). Every `getCTypeName`
// flag-blind fast path (`u8`/`u32`/`i32`/`f64`/`c_char`/`usize`) must render
// the volatile pointee qualifier, and the multi-level append rule must place
// the qualifier on the pointee pointer (`*volatile *u32` emits
// `unsigned int* volatile*`, never a naive `volatile unsigned int**`).
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: compile/link/run clean, prints "1 2 3 1 65 6 7\n".
const std = @import("std");

pub fn main() void {
    var bu8: u8 = 0;
    var bu32: u32 = 0;
    var bi32: i32 = 0;
    var bf64: f64 = 0;
    var bc: c_char = 0;
    var bus: usize = 0;

    const p8: *volatile u8 = &bu8;
    const p32: *volatile u32 = &bu32;
    const pi32: *volatile i32 = &bi32;
    const pf64: *volatile f64 = &bf64;
    const pc: *volatile c_char = &bc;
    const pus: *volatile usize = &bus;

    p8.* = 1;
    p32.* = 2;
    pi32.* = 3;
    pf64.* = 4.5;
    pc.* = 'A';
    pus.* = 6;

    std.io.printInt(@intCast(i32, p8.*));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, p32.*));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, pi32.*));
    std.io.writeByte(' ');
    var fok: i32 = 0;
    if (pf64.* == 4.5) {
        fok = 1;
    }
    std.io.printInt(fok);
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, pc.*));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, pus.*));
    std.io.writeByte(' ');

    var inner: u32 = 7;
    var ip: *u32 = &inner;
    const vpp: *volatile *u32 = &ip;
    std.io.printInt(@intCast(i32, vpp.*.*));
    std.io.writeByte('\n');
}
