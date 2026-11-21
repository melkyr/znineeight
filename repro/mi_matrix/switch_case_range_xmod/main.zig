// switch_case_range_xmod — FEATURE-GAP RED fixture (switch case ranges).
// Feature: prong items `a...b` (inclusive) lowered to real dispatch, not dropped.
// RED today: range nodes parsed (parser.zig:977-981) but switch lowering
//   ignores them (lower.zig) -> prongs fall to `else`. Class = clean FAIL (if
//   ranges rejected) OR runtime-wrong (compiles, prints zeros). RECORD ACTUAL.
// GREEN (contract): "130 47\n" — int ranges 1..5=>10, 6..9=>20 over 1..9;
//   char ranges 'a'..'e'=>1, 'f'..'z'=>2 over 'a'..'z'.
const std = @import("std");

fn inRange(n: i32) i32 {
    return switch (n) {
        1...5 => 10,
        6...9 => 20,
        else => 0,
    };
}

fn charClass(ch: u8) i32 {
    return switch (ch) {
        'a'...'e' => 1,
        'f'...'z' => 2,
        else => 0,
    };
}

pub fn main() void {
    var total: i32 = 0;
    var i: i32 = 1;
    while (i <= 9) : (i += 1) { total += inRange(i); }
    std.io.printInt(total);
    std.io.writeByte(' ');
    var c: u8 = 'a';
    var ctotal: i32 = 0;
    while (c <= 'z') : (c += 1) { ctotal += charClass(c); }
    std.io.printInt(ctotal);
    std.io.writeByte('\n');
}
