pub const Value = union(enum) {
    Int: i32,
    Cons: struct { car: *Value, cdr: *Value },
};

pub fn process(v: *Value) i32 {
    return 0;
}
