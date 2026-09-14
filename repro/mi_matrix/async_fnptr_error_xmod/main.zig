fn yielder() void {
    @asyncSuspend(null);
}

fn plain() void {
}

pub fn main() void {
    var fp: fn() void = yielder;
    fp();
    var gp: fn() void = plain;
    gp();
}
