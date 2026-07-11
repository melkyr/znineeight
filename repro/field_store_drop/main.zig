const pal = @import("pal");

const Trio = struct {
    a: i32,
    b: i32,
    c: i32,
};

fn make(a: i32, b: i32, c: i32) Trio {
    var t: Trio = undefined;
    t.a = a;
    t.b = b;
    t.c = c;
    return t;
}

pub fn main() void {
    var x = make(10, 20, 30);
    __bootstrap_print_int(x.a);
    pal.stderr_write("\n");
    __bootstrap_print_int(x.b);
    pal.stderr_write("\n");
    __bootstrap_print_int(x.c);
    pal.stderr_write("\n");
}
