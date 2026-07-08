extern fn __bootstrap_print_int(x: i32) void;

const Value = union(enum) {
    Nil: void,
    Int: i64,
    Flag: i32,
};

fn make_int(n: i64) Value {
    return Value{ .Int = n };
}

pub fn main() void {
    var a: Value = Value{ .Int = @intCast(i64, 42) };
    var ra: i32 = @intCast(i32, 0);
    switch (a) {
        .Int => |v| ra = @intCast(i32, v),
        .Flag => |f| ra = f,
        .Nil => ra = @intCast(i32, 0),
    }

    var b: Value = make_int(@intCast(i64, 100));
    var rb: i32 = @intCast(i32, 0);
    switch (b) {
        .Int => |v| rb = @intCast(i32, v),
        .Flag => |f| rb = f,
        .Nil => rb = @intCast(i32, 0),
    }

    __bootstrap_print_int(ra + rb);
}
