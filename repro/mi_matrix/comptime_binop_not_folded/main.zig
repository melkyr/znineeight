@cInclude("<stdio.h>");
extern fn printf(fmt: [*]const u8, a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32, k: i32, l: i32) i32;

const VADD: i32 = 30 + 10;
const VSUB: i32 = 30 - 10;
const VMUL: i32 = 30 * 10;
const VDIV: i32 = 30 / 10;
const VMOD: i32 = 30 % 10;
const VNEG: i32 = -30;
const VAND: i32 = 30 & 10;
const VOR:  i32 = 30 | 10;
const VXOR: i32 = 30 ^ 10;
const VSHL: i32 = 30 << 2;
const VSHR: i32 = 30 >> 2;
const VNOT: i32 = ~30;

pub fn main() void {
    var fmt_all: [*]const u8 = "%d %d %d %d %d %d %d %d %d %d %d %d\n";
    _ = printf(fmt_all, VADD, VSUB, VMUL, VDIV, VMOD,
               VNEG, VAND, VOR, VXOR, VSHL, VSHR, VNOT);
}
