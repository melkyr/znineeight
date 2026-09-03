// packed_enum_field_xmod — FEATURE-GAP RED fixture (L7: enum(u3) field inside a
//   packed struct; exercises B0+B3). GREEN (contract): "1 3 1 1\n" — size 1;
//   on=true(bit0), color=green(enum 1, bits1-3) => byte 0b00000011 = 3;
//   @enumToInt(Color.blue)==2; @sizeOf(Color)=1.
const std = @import("std");

const Color = enum(u3) { red, green, blue };
const Pixel = packed struct { on: bool, color: Color };

pub fn main() void {
    var p: Pixel = undefined;
    p.on = true;
    p.color = Color.green;
    std.io.printInt(@intCast(i32, @sizeOf(Pixel)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &p);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    var c: Color = Color.blue;
    if (@enumToInt(c) == 2) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @sizeOf(Color)));
    std.io.writeByte('\n');
}
