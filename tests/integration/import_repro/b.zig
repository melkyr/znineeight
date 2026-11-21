const Foo = @import("a.zig").Foo;
const a = @import("a.zig");
pub fn useFoo() void {
    var f = a.makeFoo(42);
    _ = f;
}
