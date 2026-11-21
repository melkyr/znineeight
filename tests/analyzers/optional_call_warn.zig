// optional_call_warn.zig — Task 9h2 D4h2 negative fixture.
//
// A call whose declared result is an optional pointer is `maybe`, so the
// dereference must emit exactly one WARN_6002.
fn optionalPtr() ?*u32 {
    return null;
}

fn optional_call_deref() u32 {
    var p = optionalPtr();
    return p.*;
}

pub fn main() void {
    _ = optionalPtr();
}
