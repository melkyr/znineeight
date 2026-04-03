const value_mod = union(enum) {
    Nil: void,
    Int: i64,
    Cons: struct { car: *value_mod, cdr: *value_mod },
};

pub fn main() void {
    // This is a placeholder for the recursion issue symptom
    // Currently the symptom is that recursive environment lookups return unexpected values (Nil)
    // after in-place mutation of environment nodes.
}
