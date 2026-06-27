const Value = union(enum) {
    Int: i64,
    Bool: bool,
    Cons: struct { car: *Value, cdr: *Value },
    Nil: void,
};
