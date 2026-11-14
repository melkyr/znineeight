fn helper() u8 { return 1; }

fn testWithCall() u8 {
    var count: u8 = 0;
    var outer: i32 = 0;
    while (outer < 2) : (outer += 1) {
        var inner: i32 = 0;
        while (inner < 2) : (inner += 1) {
            if (inner == 0 and outer == 0) continue;
            const val = helper();
            if (val != 0) {
                switch (inner) {
                    0 => { count += 1; },
                    1 => { count += 1; },
                    else => {},
                }
            }
        }
    }
    return count;
}

pub fn main() i32 {
    var result: i32 = @intCast(i32, testWithCall());
    return result;
}
