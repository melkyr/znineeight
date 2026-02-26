// Test A: ?[]u8 assigned to ?[*]u8 (Optional Covariance)
pub fn test_optional_covariance() void {
    var slice: []u8 = "hello"[0..5];
    var opt_slice: ?[]u8 = slice;
    var opt_ptr: ?[*]u8 = opt_slice;
    _ = opt_ptr;
}

// Test B: Struct with optional fields initialized via tuple .{ .field = null }
const S = struct {
    a: ?i32,
    b: ?[]u8,
};

pub fn test_struct_tuple_init() void {
    var s: S = .{ 42, null };
    _ = s;
}

// Test C: Nested initializers .{ .{1, 2}, .{3, 4} }
const Point = struct { x: i32, y: i32 };
const Rect = struct { p1: Point, p2: Point };

pub fn test_nested_tuple_init() void {
    var r: Rect = .{ .{ 1, 2 }, .{ 3, 4 } };
    _ = r;
}

// Test D: Return statement with coercion (Regression test for emitReturn)
fn get_opt_ptr(s: []u8) ?[*]u8 {
    return s;
}

pub fn main() void {
    test_optional_covariance();
    test_struct_tuple_init();
    test_nested_tuple_init();
    var slice: []u8 = "test"[0..4];
    _ = get_opt_ptr(slice);
}
