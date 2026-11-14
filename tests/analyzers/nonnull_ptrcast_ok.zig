// nonnull_ptrcast_ok.zig — Task 9h D4h fixture.
//
// `@ptrCast` of the address of a local is a statically non-null base, so the
// dereference of the cast result must not emit WARN_6002.
fn ptrcast_ok() u64 {
    var bits: u64 = 0x3FF0000000000000;
    var p: *u64 = @ptrCast(*u64, &bits);
    return p.*;
}

pub fn main() void {
    _ = ptrcast_ok();
}
