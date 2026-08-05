extern fn __bootstrap_print_int(n: i32) void;

const E = error{ Bad, Other };

fn anon() !i32 {
    return error.Bad;
}

const A = error{ Other, Bad };
const B = error{ Bad };

fn fromB() B!i32 {
    return error.Bad;
}

fn checkAnon() void {
    var x: E!i32 = anon();
    var r = x catch |err| {
        if (err == error.Bad) { __bootstrap_print_int(@intCast(i32, 1)); }
        else { __bootstrap_print_int(@intCast(i32, 0)); }
        return;
    };
    _ = r;
}

fn checkNamed() void {
    var y: A!i32 = fromB();
    var s = y catch |err2| {
        if (err2 == error.Bad) { __bootstrap_print_int(@intCast(i32, 1)); }
        else { __bootstrap_print_int(@intCast(i32, 0)); }
        return;
    };
    _ = s;
}

pub fn main() void {
    checkAnon();
    checkNamed();
}
