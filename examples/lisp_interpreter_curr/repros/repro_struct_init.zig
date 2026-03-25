pub const Value = union(enum) {
    Int: i64,
    Cons: struct {
        car: *Value,
        cdr: *Value,
    },
};

pub fn test_switch_capture(v: *Value) i64 {
    switch (v.*) {
        .Int => |val| return val,
        .Cons => |data| return test_switch_capture(data.car),
    }
}

pub fn main() void {
    var v: Value = Value{ .Int = 42 };
    _ = test_switch_capture(&v);
}
