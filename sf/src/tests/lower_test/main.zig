pub fn test_return() void {
    return;
}

pub fn test_arith() void {
    var x = 1 + 2;
}

pub fn test_if() void {
    var cond = true;
    if (cond) {
        var a = 1;
    } else {
        var b = 2;
    }
}

pub fn test_defer() void {
    defer { var z = 0; }
    return;
}

pub fn test_multi_return_defer() void {
    defer { var z = 0; }
    var cond = true;
    if (cond) return;
    return;
}
