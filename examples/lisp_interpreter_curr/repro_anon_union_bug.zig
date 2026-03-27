pub const Value = union(enum) {
    Cons: struct {
        car: i32,
        cdr: i32,
    },
};

pub fn foo() void {
    var v: Value = undefined;
    v = Value{ .Cons = .{ .car = 1, .cdr = 2 } };
}

pub fn main() void {
    foo();
}
