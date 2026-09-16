// module_value_types_xmod — `pub const` of every value type via a 2-level alias.
//
// Each read below (`mid.leaf.<const>`) is a nested-module value-position access.
// The lowerer does not abort on `error[3042]`; it emits ONE diagnostic pair per
// failing read, so this fixture reports all EIGHT (verified):
//   bool, usize, i32, array `[3]u8`, slice `[]const u8`, struct value `Point`,
//   enum value `Color`, fn pointer `fn (i32,i32) i32`.
// The diagnostic does NOT depend on the const's type.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access   (x8)
//   warning[3023]: module used as value expression           (x8)
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
//
// Expected GREEN contract: all eight checks hold; dump rc=0, gcc clean,
// link+run rc=0, no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var b: bool = mid.leaf.FLAG;
    if (!b) {
        @panic("module_value_types_xmod: bool");
    }
    var n: usize = mid.leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_types_xmod: usize");
    }
    var s: i32 = mid.leaf.SMALL;
    if (s != -7) {
        @panic("module_value_types_xmod: i32");
    }
    var a: [3]u8 = mid.leaf.ARR;
    if (a[0] != 1) {
        @panic("module_value_types_xmod: array");
    }
    var sl: []const u8 = mid.leaf.BUF;
    if (sl.len != 2) {
        @panic("module_value_types_xmod: slice");
    }
    var p: mid.leaf.Point = mid.leaf.ORIGIN;
    if (p.x != 1) {
        @panic("module_value_types_xmod: struct value");
    }
    var c: mid.leaf.Color = mid.leaf.PICK;
    if (@enumToInt(c) != 1) {
        @panic("module_value_types_xmod: enum value");
    }
    var f: fn (i32, i32) i32 = mid.leaf.CB;
    if (f(2, 3) != 5) {
        @panic("module_value_types_xmod: fn pointer");
    }
}
