const t = @import("types.zig");
pub fn printTag(tag: t.Tag) void { _ = tag; }
pub fn check(tag: t.Tag) i32 {
    if (tag == t.Tag.Null) {
        return 0;
    }
    return 1;
}
pub fn main() void {}
