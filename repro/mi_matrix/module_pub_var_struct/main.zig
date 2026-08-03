extern fn __bootstrap_print_int(n: i32) void;

const Writer = struct {
    tag: i32,
};

pub var out: Writer = undefined;

pub fn main() void {
    out.tag = 7;
    __bootstrap_print_int(out.tag);
}
