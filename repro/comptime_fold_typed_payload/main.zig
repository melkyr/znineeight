extern fn __bootstrap_print_int(x: i32) void;

const Value = union(enum) {
    Nil: void,
    Int: i64,
    Flag: i32,
};

pub fn main() void {
    var a: Value = Value{ .Int = @intCast(i64, 42) };
    var ra: i32 = @intCast(i32, 0);
    switch (a) {
        .Int => |v| ra = @intCast(i32, v),
        .Flag => |f| ra = f,
        .Nil => ra = @intCast(i32, 0),
    }
    __bootstrap_print_int(ra);
}
