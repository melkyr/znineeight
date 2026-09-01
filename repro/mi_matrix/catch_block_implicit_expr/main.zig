fn maybe() !i32 { return 42; }
pub fn main() void {
    var x = maybe() catch |err| {
        _ = err;
        0;
    };
    _ = x;
}
