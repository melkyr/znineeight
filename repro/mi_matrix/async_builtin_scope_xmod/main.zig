fn plain_caller() void {
    @asyncSuspend(null);
}

pub fn main() void {
    plain_caller();
}
