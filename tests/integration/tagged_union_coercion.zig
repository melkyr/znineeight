const Status = union(enum) {
    Alive,
    Dead: i32,
};

pub fn main() void {
    // 1. Naked tag coercion
    var s1: Status = .Alive;

    // 2. Qualified tag coercion
    var s2: Status = Status.Alive;

    _ = s1;
    _ = s2;
}
