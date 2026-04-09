const Status = union(enum) {
    Alive,
    Dead: i32,
    Nested: struct { x: i32, y: i32 },
};

const Data = struct {
    status: Status,
    buffer: [2]i32,
};

pub fn process(d: Data) i32 {
    return d.buffer[0];
}

pub fn main() void {
    // 1. Tag coercion (naked tag)
    var s1: Status = .Alive;

    // 2. Tag coercion (qualified tag)
    var s2: Status = Status.Alive;

    // 3. Anonymous aggregate (in assignment)
    var d1: Data = .{ .status = .Alive, .buffer = .{ 10, 20 } };

    // 4. Nested anonymous aggregate
    var s3: Status = .{ .Nested = .{ .x = 1, .y = 2 } };

    _ = s1;
    _ = s2;
    _ = d1;
    _ = s3;
}
