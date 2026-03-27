fn testDefer() void {
    var x: i32 = 1;
    defer x = 2;
    x = 3;
}

pub fn main() void {
    testDefer();
}
