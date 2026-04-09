const Status = union(enum) {
    Alive,
    Dead: i32,
};

pub fn main() void {
    // 1. Tag requires a value (naked tag)
    // var s1: Status = .Dead; // Expected error

    // 2. Tag requires a value (qualified tag)
    // var s2: Status = Status.Dead; // Expected error

    // 3. Tag not found
    var s3: Status = .Missing; // Expected error
}
