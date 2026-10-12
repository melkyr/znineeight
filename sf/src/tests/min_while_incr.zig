fn testWhileIncr() i32 {
    var i: i32 = 0;
    var j: i32 = 0;
    while (i < 3) : (i += 1) {
        j += i;
    }
    return j;
}

pub fn main() void {
    var result = testWhileIncr();
}
