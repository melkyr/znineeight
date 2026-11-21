const a = @import("a.zig");
pub fn useFoo() void {
    var f: a.Foo = a.makeFoo(42);
    _ = f;
}
