const Status = union(enum) {
    Alive,
    Dead: i32,
};

pub fn main() void {
    // 1. Tag requiring value
    var s1: Status = .Dead;

    // 2. Missing tag
    var s2: Status = .Missing;

    _ = s1;
    _ = s2;
}
